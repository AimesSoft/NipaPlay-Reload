// ════════════════════════════════════════════════════════════════════
//  V6.0 Phase 1+2: 全帧 drawRawAtlas 画笔 + FNV-1a 整数哈希缓存键
//
//  替代 NipaPlayNextCanvasPainter:
//  - N 次 drawImageRect → 1 次 drawRawAtlas (GPU draw call 250x↓)
//  - String 缓存键 → int 哈希键 (CPU 5-10x↑)
//  - 每帧临时对象分配 → 预分配缓冲区零 GC
// ════════════════════════════════════════════════════════════════════

import 'dart:collection';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import 'danmaku_sprite_atlas.dart';
import 'nipaplay_next_engine.dart';

// ════════════════════════════════════════════════════════════════
//  FNV-1a 32-bit 组合哈希 — 零字符串分配缓存键 (Phase 2)
// ════════════════════════════════════════════════════════════════

/// FNV-1a offset basis & prime
const int _fnvOffsetBasis = 0x811c9dc5;
const int _fnvPrime = 0x01000193;

/// FNV-1a 组合哈希 — 将两个哈希值合并为一个正整数
/// 每次组合 = XOR + MUL，保证哈希分散性
int _combineHash(int h1, int h2) {
  int h = _fnvOffsetBasis;
  h = (h ^ h1) * _fnvPrime;
  h = (h ^ h2) * _fnvPrime;
  return h & 0x7FFFFFFF; // 保证正整数
}

/// 多值组合哈希 — 按序组合任意数量的 int 值
int _combineHashes(List<int> values) {
  int h = _fnvOffsetBasis;
  for (final v in values) {
    h = (h ^ v) * _fnvPrime;
  }
  return h & 0x7FFFFFFF;
}

// ════════════════════════════════════════════════════════════════
//  [ATLAS-DIAG-BUG1] 白色背景框诊断开关
//
//  用于定位 Bug 1 (彩色弹幕白色实心矩形背景框) 的根因。
//  切换以下模式并运行压测，观察白色背景是否消失：
//
//  0 = 正常 drawRawAtlas 模式 (默认)
//  1 = drawRawAtlas 颜色调制 alpha=0 (0x00FFFFFF) — 测试颜色调制
//  2 = drawRawAtlas BlendMode.src — 测试混合模式
//  3 = 回退到逐条 drawImageRect — 测试 drawRawAtlas 实现是否有 bug
//  4 = drawRawAtlas + 自定义 Paint blendMode=src — 测试 Paint 级 blendMode
//
//  如果模式 3 (drawImageRect 回退) 白色背景消失 → drawRawAtlas 实现有问题
//  如果模式 1 (alpha=0 颜色) 白色背景消失 → 颜色调制影响了透明区域
//  如果模式 2 (BlendMode.src) 白色背景消失 → srcOver 混合逻辑有问题
// ════════════════════════════════════════════════════════════════
const int _diagBug1Mode = 0;

// ════════════════════════════════════════════════════════════════
//  [ATLAS-DIAG-BUG3] Emoji 丢失诊断开关
//
//  用于定位 Bug 3 (Emoji/特殊字符丢失) 的根因。
//  压测日志显示 Emoji Paragraph 尺寸正常(zeroSize=0)但画面不可见，
//  说明问题在 drawParagraph→toImageSync 的光栅化阶段，而非排版阶段。
//
//  0 = 正常 toImageSync 路径 (默认)
//  1 = 含非 BMP 字符的弹幕跳过 toImageSync，直接 canvas.drawParagraph()
//
//  如果模式 1 下 Emoji 可见 → toImageSync 破坏了 Emoji 像素
//  如果模式 1 下 Emoji 仍不可见 → fontFamilyFallback 问题
// ════════════════════════════════════════════════════════════════
const int _diagBug3Mode = 0;

// ════════════════════════════════════════════════════════════════
//  诊断日志节流
// ════════════════════════════════════════════════════════════════

int _lastDiagPaintTimeMs = 0;
int _lastDiagSnapTimeMs = 0;
int _lastDiagDriftTimeMs = 0;
int _lastDiagRasterTimeMs = 0;
double _lastDiagPlaybackRate = 1.0;

/// [ATLAS-DIAG-BUG2] 渲染管线瓶颈诊断计数器
int _lastDiagBottleneckTimeMs = 0;
int _diagLayoutItems = 0;
int _diagCulledItems = 0;
int _diagAtlasFullItems = 0;
int _diagBufferFullItems = 0;
int _diagEdgeClipItems = 0;

/// [ATLAS-DIAG-BUG3] Emoji/特殊字符诊断计数器
int _lastDiagEmojiTimeMs = 0;
int _diagEmojiItemCount = 0;
int _diagEmojiZeroSizeCount = 0;
int _diagBug3EmojiBypassCount = 0; // 模式 1 bypass 计数

// ════════════════════════════════════════════════════════════════
//  主画笔
// ════════════════════════════════════════════════════════════════

/// V6.0 全帧 drawRawAtlas 弹幕画笔
///
/// 渲染管线：
///   layout → 字符串哈希键 → Paragraph 查找/构建 → 光栅化 → 精灵图集打包
///   → 预分配缓冲区填充 → 单次 drawRawAtlas → 1 次 GPU draw call
class DanmakuAtlasPainter extends CustomPainter {
  DanmakuAtlasPainter({
    required this.vsyncNotifier,
    required this.engine,
    required this.playbackTimeMs,
    required this.playbackRate,
    required this.isPlaying,
    required this.timeOffsetSeconds,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.locale,
    required this.outlineStyle,
    required this.shadowStyle,
    required this.devicePixelRatio,
  }) : super(repaint: vsyncNotifier);

  // ── 与 NipaPlayNextCanvasPainter 相同的输入参数 ──

  final Animation<double> vsyncNotifier;
  final NipaPlayNextEngine engine;
  final ValueListenable<double> playbackTimeMs;
  final double playbackRate;
  final bool isPlaying;
  final double timeOffsetSeconds;
  final double fontSize;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final Locale? locale;
  final DanmakuOutlineStyle outlineStyle;
  final DanmakuShadowStyle shadowStyle;
  final double devicePixelRatio;
  late final int _layoutVersion = engine.layoutVersion;

  // ════════════════════════════════════════════════════════════════
  //  Phase 2: 整数哈希缓存键
  // ════════════════════════════════════════════════════════════════

  /// fontFamilyFallback 预计算哈希（构造时计算一次）
  late final int _ffbHash = fontFamilyFallback != null
      ? _combineHashes(fontFamilyFallback!.map((s) => s.hashCode).toList())
      : 0;

  /// fontFamily 预计算哈希
  late final int _fontFamilyHash = fontFamily?.hashCode ?? 0;

  /// locale 预计算哈希
  late final int _localeHash = locale?.hashCode ?? 0;

  /// 不变前缀组合哈希 = fontFamily + ffb + locale
  late final int _keyPrefixHash =
      _combineHashes([_fontFamilyHash, _ffbHash, _localeHash]);

  /// 生成整数哈希缓存键 — 替代旧版 _key() 字符串拼接
  ///
  /// [content] 弹幕内容
  /// [fontSize] 字体大小
  /// [colorValue] ARGB32 颜色值
  /// [variantCode] 变体编码（uniform=1, stroke=2, fill=3, fillShadow=4）
  int _hashKey(
    DanmakuContentItem content,
    double fontSize,
    int colorValue,
    int variantCode,
  ) {
    var h = content.text.hashCode;
    h = _combineHash(h, (fontSize * 10).round()); // 量化到 0.1 精度
    h = _combineHash(h, colorValue);
    h = _combineHash(h, variantCode);
    if (content.countText != null) {
      h = _combineHash(h, content.countText!.hashCode);
    }
    h = _combineHash(h, _keyPrefixHash);
    return h;
  }

  /// 光栅化缓存键 — stroke+fill 合成时需要组合键
  int _rasterHashKey(int strokeHash, int fillHash) {
    return _combineHash(strokeHash, fillHash);
  }

  // ════════════════════════════════════════════════════════════════
  //  缓存 — int 键 HashMap (Phase 2) + FIFO 淘汰
  // ════════════════════════════════════════════════════════════════

  /// Paragraph 全局缓存（int 键替代 String 键）
  static final HashMap<int, ui.Paragraph> _pCache = HashMap<int, ui.Paragraph>();
  static const int _pCacheLimit = 6000;

  /// 段落键插入顺序（FIFO 淘汰用 — HashMap 本身无序）
  static final List<int> _pCacheOrder = <int>[];

  /// 光栅化图像缓存 — int 键替代 String 键
  static final HashMap<int, _RasterEntry> _rasterCache =
      HashMap<int, _RasterEntry>();
  static const int _rasterCacheLimit = 2000;
  static double _cacheDpr = 0.0;

  /// 光栅化键插入顺序
  static final List<int> _rasterCacheOrder = <int>[];

  // ════════════════════════════════════════════════════════════════
  //  Phase 1: 精灵图集 + 预分配缓冲区
  // ════════════════════════════════════════════════════════════════

  /// 精灵图集 — 所有弹幕预光栅化图像共享一张纹理
  static DanmakuSpriteAtlas? _spriteAtlas;

  /// drawRawAtlas 预分配缓冲区 — 零 GC 帧循环
  /// 每帧仅重置计数器，不分配新对象
  static Float32List? _atlasTransforms; // 4 floats/sprite: [scos, ssin, tx, ty]
  static Float32List? _atlasRects; // 4 floats/sprite: [l, t, w, h]
  static Int32List? _atlasColors; // 1 int/sprite: ARGB32

  /// 边缘裁剪回退用 — drawImageRect
  static final List<_EdgeClipSprite> _edgeClipSprites = [];

  /// 预分配缓冲区最大容量
  /// ⚠️ Bug 2 修复: 2048 → 4096
  /// 压测日志 ATLAS-DIAG-BUG2 显示 LAYOUT≈2278 但 RENDERED 恰好 2048，
  /// BUF_FULL 每帧丢弃 ~170 条可见弹幕导致矩形空洞。
  /// 图集 SLOTS 最高 741，远低于 _maxSlots=2000，不是瓶颈。
  static const int _bufferCapacity = 4096;

  /// 当前帧精灵数
  static int _spriteCount = 0;

  /// drawRawAtlas 共享 Paint
  static final Paint _atlasPaint = Paint()
    ..filterQuality = ui.FilterQuality.none;

  /// drawImageRect 回退 Paint
  static final Paint _imagePaint = Paint()
    ..filterQuality = ui.FilterQuality.none;

  /// 自发弹幕边框
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;

  /// [ATLAS-DIAG-BUG1] 模式 3: drawImageRect 回退绘制列表
  static final List<_DiagFallbackItem> _diagFallbackItems = [];

  /// [ATLAS-DIAG-BUG3] 模式 1: Emoji 直接 drawParagraph 绘制列表
  static final List<_DiagEmojiParagraphItem> _diagEmojiParagraphItems = [];

  // ════════════════════════════════════════════════════════════════
  //  墙钟 dt + EMA（与旧版完全一致）
  // ════════════════════════════════════════════════════════════════

  static final Stopwatch _wallClock = Stopwatch()..start();
  static int _lastWallUs = 0;
  static double _smoothedDtSeconds = 0.0;
  static const double _dtEmaAlpha = 0.3;

  /// uniform 描边8方向偏移
  static const List<(double, double)> _uniformOutlineDirs = [
    (-1.0, 0.0),
    (1.0, 0.0),
    (0.0, -1.0),
    (0.0, 1.0),
    (-1.0, -1.0),
    (1.0, -1.0),
    (-1.0, 1.0),
    (1.0, 1.0),
  ];

  // ════════════════════════════════════════════════════════════════
  //  主绘制循环 — vsync 驱动 + 墙钟增量定位 + drawRawAtlas 批量提交
  // ════════════════════════════════════════════════════════════════

  @override
  void paint(Canvas canvas, Size size) {
    final diagPaintSw = kDebugMode ? Stopwatch() : null;
    diagPaintSw?.start();

    // ── 墙钟 dt：真实帧间隔（与旧版完全一致） ──
    final currentWallUs = _wallClock.elapsedMicroseconds;
    final double rawDtSeconds;
    if (_lastWallUs == 0 || currentWallUs < _lastWallUs) {
      rawDtSeconds = 0.0;
    } else {
      final deltaUs = currentWallUs - _lastWallUs;
      rawDtSeconds = (deltaUs < 100000) ? deltaUs / 1000000.0 : 0.0;
    }
    _lastWallUs = currentWallUs;

    // ── EMA 平滑 dt ──
    final double dtSeconds;
    if (!isPlaying) {
      dtSeconds = 0.0;
    } else if (rawDtSeconds == 0.0) {
      dtSeconds = 0.0;
    } else if (_smoothedDtSeconds == 0.0) {
      dtSeconds = rawDtSeconds;
      _smoothedDtSeconds = rawDtSeconds;
    } else {
      _smoothedDtSeconds =
          _dtEmaAlpha * rawDtSeconds + (1.0 - _dtEmaAlpha) * _smoothedDtSeconds;
      dtSeconds = _smoothedDtSeconds;
    }

    final items =
        engine.layout(playbackTimeMs.value / 1000.0 + timeOffsetSeconds);
    if (items.isEmpty) {
      diagPaintSw?.stop();
      return;
    }

    // ── 预计算阴影参数 ──
    final shadowParams = _resolveShadowParams(fontSize);

    // ── DPR 变更检测 ──
    if (devicePixelRatio != _cacheDpr) {
      _clearRasterCache();
      _cacheDpr = devicePixelRatio;
      _spriteAtlas?.invalidate();
    }

    // ── 初始化/重建精灵图集 ──
    _spriteAtlas ??= DanmakuSpriteAtlas(devicePixelRatio: devicePixelRatio);

    // ── 初始化预分配缓冲区 ──
    _ensureBuffers();

    // ── playbackRate 变化检测 ──
    if (playbackRate != _lastDiagPlaybackRate) {
      if (!kReleaseMode) {
        debugPrint('[ATLAS-DIAG] RATE CHANGE: $_lastDiagPlaybackRate → $playbackRate');
      }
      _lastDiagPlaybackRate = playbackRate;
      for (final item in items) {
        if (item.scrollSpeed > 0.0) {
          item.displayX = item.x;
        }
      }
    }

    // ── 重置精灵计数与边缘裁剪列表 ──
    _spriteCount = 0;
    _edgeClipSprites.clear();
    if (_diagBug1Mode == 3) _diagFallbackItems.clear(); // [ATLAS-DIAG-BUG1]
    if (_diagBug3Mode == 1) {
      _diagEmojiParagraphItems.clear(); // [ATLAS-DIAG-BUG3]
      _diagBug3EmojiBypassCount = 0;
    }

    // ── [ATLAS-DIAG-BUG2] 重置瓶颈诊断计数器 ──
    _diagLayoutItems = items.length;
    _diagCulledItems = 0;
    _diagAtlasFullItems = 0;
    _diagBufferFullItems = 0;
    _diagEdgeClipItems = 0;

    // ── 视口矩形（用于边缘裁剪判断） ──
    final canvasRect = ui.Rect.fromLTWH(0, 0, size.width, size.height);

    int diagScrollItemCount = 0;

    // ══════════════════════════════════════════════════════════════
    //  遍历弹幕 — 增量定位 + 视口剔除 + 缓存查找 + 图集槽位分配
    // ══════════════════════════════════════════════════════════════

    for (final item in items) {
      final content = item.content;

      // ── 增量定位（与旧版完全一致） ──
      final double drawX;
      if (item.scrollSpeed > 0.0) {
        if (item.displayX.isNaN) {
          item.displayX = item.x;
        } else {
          item.displayX -= item.scrollSpeed * dtSeconds * playbackRate;
          final drift = item.displayX - item.x;
          final absDrift = drift.abs();
          if (absDrift > 200.0) {
            item.displayX = item.x;
            if (!kReleaseMode) {
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - _lastDiagSnapTimeMs >= 1000) {
                debugPrint('[ATLAS-DIAG] HARD SNAP: drift=${drift.toStringAsFixed(1)}px');
                _lastDiagSnapTimeMs = now;
              }
            }
          } else if (absDrift > 50.0) {
            item.displayX = item.displayX + (item.x - item.displayX) * 0.15;
            if (!kReleaseMode) {
              diagScrollItemCount++;
              if (diagScrollItemCount % 200 == 0) {
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - _lastDiagDriftTimeMs >= 2000) {
                  debugPrint('[ATLAS-DIAG] SOFT CORRECT: drift=${drift.toStringAsFixed(1)}px');
                  _lastDiagDriftTimeMs = now;
                }
              }
            }
          }
        }
        drawX = item.displayX;
      } else {
        drawX = item.x;
      }
      final drawY = item.y;

      // ── 视口剔除 ──
      final itemWidth = item.width;
      if (itemWidth > 0.0) {
        if (drawX + itemWidth < 0.0 || drawX > size.width) {
          _diagCulledItems++; // [ATLAS-DIAG-BUG2]
          continue;
        }
      }

      final adjFontSize = fontSize * content.fontSizeMultiplier;
      final itemStrokeColor = _getStrokeColor(textColor: content.color);
      final int colorVal = content.color.toARGB32();
      final int strokeColorVal = itemStrokeColor.toARGB32();

      // ── 获取或构建 Paragraph（int 键） ──
      final ui.Paragraph fillP;
      final ui.Paragraph? strokeP;
      int rasterHash; // 光栅化缓存哈希键

      if (outlineStyle == DanmakuOutlineStyle.uniform) {
        final radius = _resolveUniformOutlineRadius(adjFontSize);
        final uHash = _hashKey(content, adjFontSize, colorVal,
            1); // variantCode=1: uniform
        fillP = _getOrBuild(uHash, () => _buildUniformOutlineParagraph(
              content, adjFontSize, content.color, itemStrokeColor,
              radius, shadowParams,
            ));
        strokeP = null;
        rasterHash = uHash;
      } else if (outlineStyle == DanmakuOutlineStyle.stroke) {
        final strokeWidth = _resolveStrokeWidth(adjFontSize);
        final sHash = _hashKey(content, adjFontSize, strokeColorVal,
            2); // variantCode=2: stroke
        strokeP = _getOrBuild(sHash, () => _buildStrokeParagraph(
              content, adjFontSize, itemStrokeColor, strokeWidth, shadowParams,
            ));

        final fHash = _hashKey(content, adjFontSize, colorVal,
            3); // variantCode=3: fill
        fillP = _getOrBuild(fHash,
            () => _buildFillParagraph(content, adjFontSize, content.color));

        rasterHash = _rasterHashKey(sHash, fHash);
      } else if (shadowParams != null) {
        final fsHash = _hashKey(content, adjFontSize, colorVal,
            4); // variantCode=4: fill+shadow
        fillP = _getOrBuild(fsHash, () => _buildFillWithShadowParagraph(
              content, adjFontSize, content.color, shadowParams,
            ));
        strokeP = null;
        rasterHash = fsHash;
      } else {
        final fHash = _hashKey(content, adjFontSize, colorVal, 3);
        fillP = _getOrBuild(fHash,
            () => _buildFillParagraph(content, adjFontSize, content.color));
        strokeP = null;
        rasterHash = fHash;
      }

      // ── [ATLAS-DIAG-BUG3] 模式 1: 含 Emoji 弹幕跳过 toImageSync 路径 ──
      // 压测日志显示 Emoji Paragraph 尺寸正常但画面不可见，
      // 本开关让含 Emoji 弹幕直接走 canvas.drawParagraph()，
      // 对照确认 toImageSync 是否破坏了 Emoji 像素。
      if (_diagBug3Mode == 1) {
        final text = content.text;
        final hasNonBmp = text.runes.any((r) => r > 0xFFFF);
        if (hasNonBmp) {
          _diagBug3EmojiBypassCount++;
          _diagEmojiParagraphItems.add(_DiagEmojiParagraphItem(
            fillParagraph: fillP,
            strokeParagraph: strokeP,
            drawX: drawX,
            drawY: drawY,
          ));
          continue; // 跳过 toImageSync + atlas 路径
        }
      }

      // ── 光栅化：Paragraph → ui.Image ──
      final raster = _getOrRasterize(rasterHash, fillP, strokeP);

      // ── [ATLAS-DIAG-BUG3] 检测 Emoji/特殊字符尺寸异常 ──
      if (!kReleaseMode) {
        final text = content.text;
        final hasNonBmp = text.runes.any((r) => r > 0xFFFF);
        if (hasNonBmp) {
          _diagEmojiItemCount++;
          if (raster.logicalWidth <= 0 || raster.logicalHeight <= 0) {
            _diagEmojiZeroSizeCount++;
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastDiagEmojiTimeMs >= 3000) {
              _lastDiagEmojiTimeMs = now;
              debugPrint('[ATLAS-DIAG-BUG3] EMOJI ZERO SIZE! '
                  'logicalW=${raster.logicalWidth.toStringAsFixed(1)} '
                  'logicalH=${raster.logicalHeight.toStringAsFixed(1)} '
                  'text_sample=${text.length > 20 ? text.substring(0, 20) : text}');
            }
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastDiagEmojiTimeMs >= 5000) {
            _lastDiagEmojiTimeMs = now;
            debugPrint('[ATLAS-DIAG-BUG3] EMOJI STATS: '
                'total=$_diagEmojiItemCount zeroSize=$_diagEmojiZeroSizeCount '
                'sampleW=${raster.logicalWidth.toStringAsFixed(1)} '
                'sampleH=${raster.logicalHeight.toStringAsFixed(1)}');
          }
        }
      }

      // ── 精灵图集槽位查找/分配 ──
      var slot = _spriteAtlas!.getSlot(rasterHash);
      // 缓存未命中：分配新槽位
      slot ??= _spriteAtlas!.addSprite(
        hashKey: rasterHash,
        rasterImage: raster.image,
        logicalW: raster.logicalWidth,
        logicalH: raster.logicalHeight,
      );

      if (slot == null) {
        // 图集空间不足 — 回退到直接 drawImageRect
        _diagAtlasFullItems++; // [ATLAS-DIAG-BUG2]
        _drawFallbackImage(canvas, raster, drawX, drawY, canvasRect,
            content.isMe, size);
        continue;
      }

      // ── 边缘裁剪判断 ──
      final dstRect = ui.Rect.fromLTWH(
          drawX, drawY, raster.logicalWidth, raster.logicalHeight);
      final clippedDst = dstRect.intersect(canvasRect);

      if (clippedDst.isEmpty) continue;

      final bool needsEdgeClip = clippedDst != dstRect;

      if (needsEdgeClip) {
        // 部分裁剪 — 回退到 drawImageRect（仅边缘弹幕，2-3 条，开销可忽略）
        _diagEdgeClipItems++; // [ATLAS-DIAG-BUG2]
        _edgeClipSprites.add(_EdgeClipSprite(
          raster: raster,
          drawX: drawX,
          drawY: drawY,
          dstRect: dstRect,
          clippedDst: clippedDst,
          isMe: content.isMe,
        ));
        continue;
      }

      // ── 自发弹幕边框（在 drawRawAtlas 之外绘制） ──
      if (content.isMe) {
        _edgeClipSprites.add(_EdgeClipSprite(
          raster: raster,
          drawX: drawX,
          drawY: drawY,
          dstRect: dstRect,
          clippedDst: dstRect, // 无裁剪
          isMe: true,
        ));
        // 注意：自发弹幕仍添加到 atlas 批量提交，边框单独绘制
      }

      // ── 填充预分配缓冲区 — RSTransform + Rect + Color ──
      if (_spriteCount >= _bufferCapacity) {
        _diagBufferFullItems++; // [ATLAS-DIAG-BUG2]
        continue; // 缓冲区满
      }

      final scale = 1.0 / devicePixelRatio;
      final scos = scale; // rotation=0 → cos(0)=1
      // ssin = 0 (rotation=0)

      // RSTransform 编码：
      // anchorX/Y = 源矩形中心（图集像素坐标）
      // translateX/Y = 目标中心（canvas 逻辑坐标）
      final anchorX = slot.srcRect.left + slot.srcRect.width / 2;
      final anchorY = slot.srcRect.top + slot.srcRect.height / 2;
      final translateX = drawX + raster.logicalWidth / 2;
      final translateY = drawY + raster.logicalHeight / 2;

      // tx = translateX - scos * anchorX - ssin * anchorY
      // ty = translateY - ssin * anchorX - scos * anchorY
      //   (参见 RSTransform.fromComponents: ty = translateY - ssin*anchorX - scos*anchorY)
      final tx = translateX - scos * anchorX;
      final ty = translateY - scos * anchorY;

      final idx4 = _spriteCount * 4;

      _atlasTransforms![idx4 + 0] = scos;
      _atlasTransforms![idx4 + 1] = 0.0; // ssin
      _atlasTransforms![idx4 + 2] = tx;
      _atlasTransforms![idx4 + 3] = ty;

      // drawRawAtlas rects 格式: (left, top, right, bottom)
      // 注意：不能使用 width/height，否则 top > 0 时 bottom < top → 无效矩形
      _atlasRects![idx4 + 0] = slot.srcRect.left;
      _atlasRects![idx4 + 1] = slot.srcRect.top;
      _atlasRects![idx4 + 2] = slot.srcRect.right;
      _atlasRects![idx4 + 3] = slot.srcRect.bottom;

      // 颜色调制 — 默认白色（不修改光栅化图像颜色，颜色已烘焙到 Image 中）
      // [ATLAS-DIAG-BUG1] 模式 1: alpha=0 颜色调制，测试颜色调制是否影响透明区域
      _atlasColors![_spriteCount] = (_diagBug1Mode == 1) ? 0x00FFFFFF : 0xFFFFFFFF;

      // [ATLAS-DIAG-BUG1] 模式 3: 收集 drawImageRect 回退绘制信息
      if (_diagBug1Mode == 3) {
        _diagFallbackItems.add(_DiagFallbackItem(
          image: raster.image,
          drawX: drawX,
          drawY: drawY,
          logicalW: raster.logicalWidth,
          logicalH: raster.logicalHeight,
        ));
      }

      _spriteCount++;
    }

    // ── [ATLAS-DIAG-BUG2] 渲染管线瓶颈诊断输出 ──
    if (!kReleaseMode) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastDiagBottleneckTimeMs >= 2000) {
        _lastDiagBottleneckTimeMs = now;
        debugPrint('[ATLAS-DIAG-BUG2] LAYOUT=$_diagLayoutItems '
            'CULL=$_diagCulledItems ATLAS_FULL=$_diagAtlasFullItems '
            'BUF_FULL=$_diagBufferFullItems EDGE=$_diagEdgeClipItems '
            'RENDERED=$_spriteCount SLOTS=${_spriteAtlas?.slotCount ?? 0}');
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  提交渲染
    // ══════════════════════════════════════════════════════════════

    // ── 确保图集纹理可用 ──
    final atlas = _spriteAtlas!.ensureAtlas();

    // ── 1. 提交渲染（根据 _diagBug1Mode 选择模式） ──
    if (_diagBug1Mode == 3) {
      // [ATLAS-DIAG-BUG1] 模式 3: 回退到逐条 drawImageRect
      //    如果白色背景在此模式下消失 → drawRawAtlas 实现有问题
      for (final item in _diagFallbackItems) {
        canvas.drawImageRect(
          item.image,
          ui.Rect.fromLTWH(0, 0, item.image.width.toDouble(), item.image.height.toDouble()),
          ui.Rect.fromLTWH(item.drawX, item.drawY, item.logicalW, item.logicalH),
          _imagePaint,
        );
      }
    } else if (atlas != null && _spriteCount > 0) {
      // [ATLAS-DIAG-BUG1] 模式 0/1/2/4: drawRawAtlas 批量提交
      const diagBlendMode = (_diagBug1Mode == 2) ? ui.BlendMode.src : ui.BlendMode.srcOver;
      final diagPaint = (_diagBug1Mode == 4)
          ? (Paint()..filterQuality = ui.FilterQuality.none..blendMode = ui.BlendMode.src)
          : _atlasPaint;
      canvas.drawRawAtlas(
        atlas,
        _atlasTransforms!,
        _atlasRects!,
        _atlasColors!,
        diagBlendMode,
        canvasRect, // cullRect — 自动剔除完全不可见的 sprite
        diagPaint,
      );
    }

    // ── 2. 边缘裁剪回退 + 自发弹幕边框 ──
    for (final edge in _edgeClipSprites) {
      // 自发弹幕边框
      if (edge.isMe) {
        canvas.drawRect(
          ui.Rect.fromLTWH(edge.drawX - 2, edge.drawY - 2,
              edge.raster.logicalWidth + 4, edge.raster.logicalHeight + 4),
          _selfSendPaint,
        );
      }

      // 边缘裁剪 — 仅在需要时用 drawImageRect
      if (edge.clippedDst != edge.dstRect) {
        final scaleX =
            edge.raster.image.width.toDouble() / edge.raster.logicalWidth;
        final scaleY =
            edge.raster.image.height.toDouble() / edge.raster.logicalHeight;
        final srcRect = ui.Rect.fromLTWH(
          (edge.clippedDst.left - edge.dstRect.left) * scaleX,
          (edge.clippedDst.top - edge.dstRect.top) * scaleY,
          edge.clippedDst.width * scaleX,
          edge.clippedDst.height * scaleY,
        );
        canvas.drawImageRect(
            edge.raster.image, srcRect, edge.clippedDst, _imagePaint);
      }
    }

    // ── 3. [ATLAS-DIAG-BUG3] 模式 1: Emoji 直接 drawParagraph 渲染 ──
    if (_diagBug3Mode == 1 && _diagEmojiParagraphItems.isNotEmpty) {
      for (final emoji in _diagEmojiParagraphItems) {
        if (emoji.strokeParagraph != null) {
          canvas.drawParagraph(emoji.strokeParagraph!,
              ui.Offset(emoji.drawX, emoji.drawY));
        }
        canvas.drawParagraph(emoji.fillParagraph,
            ui.Offset(emoji.drawX, emoji.drawY));
      }
      if (!kReleaseMode) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastDiagEmojiTimeMs >= 3000) {
          _lastDiagEmojiTimeMs = now;
          debugPrint('[ATLAS-DIAG-BUG3] BYPASS: emojiCount=$_diagBug3EmojiBypassCount '
              '(drawParagraph direct, skipped toImageSync)');
        }
      }
    }

    // [ATLAS-DIAG]
    diagPaintSw?.stop();
    if (diagPaintSw != null && diagPaintSw.elapsedMicroseconds > 2000) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastDiagPaintTimeMs >= 2000) {
        _lastDiagPaintTimeMs = now;
        debugPrint(
            '[ATLAS-DIAG] SLOW PAINT: ${diagPaintSw.elapsedMicroseconds}μs '
            'items=${items.length} sprites=$_spriteCount '
            'edgeClips=${_edgeClipSprites.length} '
            'atlasSlots=${_spriteAtlas!.slotCount}');
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  预分配缓冲区初始化
  // ════════════════════════════════════════════════════════════════

  void _ensureBuffers() {
    if (_atlasTransforms == null || _atlasTransforms!.length < _bufferCapacity * 4) {
      _atlasTransforms = Float32List(_bufferCapacity * 4);
      _atlasRects = Float32List(_bufferCapacity * 4);
      _atlasColors = Int32List(_bufferCapacity);
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  回退绘制 — 图集空间不足或初始化前
  // ════════════════════════════════════════════════════════════════

  void _drawFallbackImage(
    Canvas canvas,
    _RasterEntry raster,
    double drawX,
    double drawY,
    ui.Rect canvasRect,
    bool isMe,
    Size size,
  ) {
    final dstRect = ui.Rect.fromLTWH(
        drawX, drawY, raster.logicalWidth, raster.logicalHeight);
    final clippedDst = dstRect.intersect(canvasRect);
    if (clippedDst.isEmpty) return;

    if (isMe) {
      canvas.drawRect(
        ui.Rect.fromLTWH(drawX - 2, drawY - 2,
            raster.logicalWidth + 4, raster.logicalHeight + 4),
        _selfSendPaint,
      );
    }

    if (clippedDst != dstRect) {
      final scaleX = raster.image.width.toDouble() / raster.logicalWidth;
      final scaleY = raster.image.height.toDouble() / raster.logicalHeight;
      final srcRect = ui.Rect.fromLTWH(
        (clippedDst.left - dstRect.left) * scaleX,
        (clippedDst.top - dstRect.top) * scaleY,
        clippedDst.width * scaleX,
        clippedDst.height * scaleY,
      );
      canvas.drawImageRect(raster.image, srcRect, clippedDst, _imagePaint);
    } else {
      canvas.drawImageRect(raster.image,
          ui.Rect.fromLTWH(0, 0,
              raster.image.width.toDouble(),
              raster.image.height.toDouble()),
          dstRect, _imagePaint);
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Paragraph 光栅化 — 与旧版逻辑一致
  // ════════════════════════════════════════════════════════════════

  _RasterEntry _getOrRasterize(
    int hashKey,
    ui.Paragraph fillP,
    ui.Paragraph? strokeP,
  ) {
    final cached = _rasterCache[hashKey];
    if (cached != null) {
      return cached; // FIFO: 不重排
    }

    final logicalW = strokeP != null
        ? math.max(fillP.maxIntrinsicWidth, strokeP.maxIntrinsicWidth)
        : fillP.maxIntrinsicWidth;
    final logicalH = strokeP != null
        ? math.max(fillP.height, strokeP.height)
        : fillP.height;

    final rRecorder = ui.PictureRecorder();
    final rCanvas = Canvas(rRecorder);

    // ── 透明背景清除（Impeller toImageSync 纹理未初始化修复） ──
    // ⚠️ [ATLAS-DIAG-BUG1] 根因诊断：
    // 之前的修复使用 BlendMode.src + Color(0x00000000)，但 Impeller 可能将
    // "写入 alpha=0 的像素"优化为 no-op（对最终画面无贡献），导致 toImageSync
    // 生成的纹理中未被 drawParagraph 覆盖的区域仍包含未初始化的白色 GPU 内存。
    // 现改用 BlendMode.clear — 其语义是"丢弃目标颜色，写入全透明"，
    // 在 GPU 上对应 glClear/vkClearAttachment，不会被 no-op 优化掉。
    final pixelW = (logicalW * devicePixelRatio).ceil().clamp(1, 4096);
    final pixelH = (logicalH * devicePixelRatio).ceil().clamp(1, 4096);
    rCanvas.drawRect(
      ui.Rect.fromLTWH(0, 0, pixelW.toDouble(), pixelH.toDouble()),
      ui.Paint()..blendMode = ui.BlendMode.clear,
    );

    if (strokeP != null) {
      rCanvas.drawParagraph(strokeP, ui.Offset.zero);
    }
    rCanvas.drawParagraph(fillP, ui.Offset.zero);

    final picture = rRecorder.endRecording();

    final image = picture.toImageSync(pixelW, pixelH);

    // ── 诊断日志：验证 raster image 透明背景 + Bug 1/3 诊断 ──
    if (!kReleaseMode) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastDiagRasterTimeMs >= 5000) {
        _lastDiagRasterTimeMs = now;
        debugPrint('[ATLAS-DIAG-BUG1] RASTERIZE: pixelW=$pixelW pixelH=$pixelH '
            'imgW=${image.width} imgH=${image.height} '
            'logicalW=${logicalW.toStringAsFixed(1)} logicalH=${logicalH.toStringAsFixed(1)} '
            'hasStroke=${strokeP != null} '
            'clearMode=BlendMode.clear (was BlendMode.src+transparent)');
      }
    }


    final entry = _RasterEntry(
      image: image,
      logicalWidth: logicalW,
      logicalHeight: logicalH,
    );

    // FIFO 淘汰
    if (_rasterCache.length >= _rasterCacheLimit &&
        _rasterCacheOrder.isNotEmpty) {
      final oldestKey = _rasterCacheOrder.removeAt(0);
      final oldest = _rasterCache.remove(oldestKey);
      oldest?.image.dispose();
      // 同步标记图集槽位为可复用
      _spriteAtlas?.markReusable(oldestKey);
    }
    _rasterCache[hashKey] = entry;
    _rasterCacheOrder.add(hashKey);
    return entry;
  }

  /// DPR 变更时清除所有光栅化缓存
  static void _clearRasterCache() {
    for (final entry in _rasterCache.values) {
      entry.image.dispose();
    }
    _rasterCache.clear();
    _rasterCacheOrder.clear();
  }

  // ════════════════════════════════════════════════════════════════
  //  Paragraph 构建 — 与旧版完全一致
  // ════════════════════════════════════════════════════════════════

  ui.ParagraphStyle _baseStyle(double fontSize) {
    return ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontWeight: FontWeight.normal,
      textDirection: TextDirection.ltr,
      fontFamily: fontFamily,
      locale: locale,
    );
  }

  ui.Paragraph _buildFillParagraph(
      DanmakuContentItem content, double fontSize, Color color) {
    final builder = ui.ParagraphBuilder(_baseStyle(fontSize))
      ..pushStyle(ui.TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ));
    _appendText(builder, content, false);
    final p = builder.build();
    p.layout(const ui.ParagraphConstraints(width: double.infinity));
    return p;
  }

  ui.Paragraph _buildStrokeParagraph(
    DanmakuContentItem content,
    double fontSize,
    Color strokeColor,
    double strokeWidth,
    _ShadowParams? shadow,
  ) {
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = strokeColor;

    final shadows = shadow != null
        ? <Shadow>[
            Shadow(
              color: Color.fromRGBO(0, 0, 0, shadow.opacity),
              blurRadius: shadow.blurSigma,
              offset: ui.Offset(shadow.dx, shadow.dy),
            )
          ]
        : null;

    final builder = ui.ParagraphBuilder(_baseStyle(fontSize))
      ..pushStyle(ui.TextStyle(
        foreground: strokePaint,
        shadows: shadows,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ));
    _appendText(builder, content, true);
    final p = builder.build();
    p.layout(const ui.ParagraphConstraints(width: double.infinity));
    return p;
  }

  ui.Paragraph _buildUniformOutlineParagraph(
    DanmakuContentItem content,
    double fontSize,
    Color fillColor,
    Color outlineColor,
    double radius,
    _ShadowParams? shadow,
  ) {
    final shadows = <Shadow>[];

    if (shadow != null) {
      shadows.add(Shadow(
        color: Color.fromRGBO(0, 0, 0, shadow.opacity),
        blurRadius: shadow.blurSigma,
        offset: ui.Offset(shadow.dx, shadow.dy),
      ));
    }

    for (final (dx, dy) in _uniformOutlineDirs) {
      shadows.add(Shadow(
        color: outlineColor,
        offset: ui.Offset(dx * radius, dy * radius),
        blurRadius: 0.0,
      ));
    }

    final builder = ui.ParagraphBuilder(_baseStyle(fontSize))
      ..pushStyle(ui.TextStyle(
        color: fillColor,
        shadows: shadows,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ));
    _appendText(builder, content, false);
    final p = builder.build();
    p.layout(const ui.ParagraphConstraints(width: double.infinity));
    return p;
  }

  ui.Paragraph _buildFillWithShadowParagraph(
    DanmakuContentItem content,
    double fontSize,
    Color color,
    _ShadowParams shadow,
  ) {
    final builder = ui.ParagraphBuilder(_baseStyle(fontSize))
      ..pushStyle(ui.TextStyle(
        color: color,
        shadows: <Shadow>[
          Shadow(
            color: Color.fromRGBO(0, 0, 0, shadow.opacity),
            blurRadius: shadow.blurSigma,
            offset: ui.Offset(shadow.dx, shadow.dy),
          )
        ],
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ));
    _appendText(builder, content, false);
    final p = builder.build();
    p.layout(const ui.ParagraphConstraints(width: double.infinity));
    return p;
  }

  void _appendText(
      ui.ParagraphBuilder builder, DanmakuContentItem content, bool isStroke) {
    final countText = content.countText;
    if (countText != null && countText.isNotEmpty) {
      builder.addText(content.text);
      builder.pushStyle(ui.TextStyle(
        fontSize: 25.0,
        fontWeight: FontWeight.bold,
        color: isStroke ? null : Colors.white,
      ));
      builder.addText(countText);
    } else {
      builder.addText(content.text);
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  缓存 — int 键 FIFO
  // ════════════════════════════════════════════════════════════════

  ui.Paragraph _getOrBuild(int hashKey, ui.Paragraph Function() builder) {
    final cached = _pCache[hashKey];
    if (cached != null) {
      return cached; // FIFO: 不重排，O(1) 命中
    }
    final p = builder();
    // FIFO 淘汰：满时淘汰最旧条目
    if (_pCache.length >= _pCacheLimit && _pCacheOrder.isNotEmpty) {
      final oldestKey = _pCacheOrder.removeAt(0);
      _pCache.remove(oldestKey);
    }
    _pCache[hashKey] = p;
    _pCacheOrder.add(hashKey);
    return p;
  }

  // ════════════════════════════════════════════════════════════════
  //  样式计算 — 与旧版完全一致
  // ════════════════════════════════════════════════════════════════

  _ShadowParams? _resolveShadowParams(double targetFontSize) {
    final double unit = _resolveUniformOutlineRadius(targetFontSize);
    switch (shadowStyle) {
      case DanmakuShadowStyle.none:
        return null;
      case DanmakuShadowStyle.soft:
        return _ShadowParams(
            dx: unit * 0.8, dy: unit * 0.8, blurSigma: unit * 0.9, opacity: 0.34);
      case DanmakuShadowStyle.medium:
        return _ShadowParams(
            dx: unit, dy: unit, blurSigma: unit * 1.2, opacity: 0.44);
      case DanmakuShadowStyle.strong:
        return _ShadowParams(
            dx: unit * 1.2, dy: unit * 1.2, blurSigma: unit * 1.5, opacity: 0.55);
    }
  }

  double _resolveStrokeWidth(double targetFontSize) {
    return (targetFontSize * 0.06).clamp(1.0, 2.6);
  }

  double _resolveUniformOutlineRadius(double targetFontSize) {
    return math.max(0.8, (targetFontSize * 0.045).clamp(0.8, 2.0));
  }

  Color _getStrokeColor({required Color textColor}) {
    if (_isPureBlack(textColor)) return Colors.white;
    return Colors.black;
  }

  bool _isPureBlack(Color color) {
    const double epsilon = 1e-6;
    return color.r <= epsilon && color.g <= epsilon && color.b <= epsilon;
  }

  @override
  bool shouldRepaint(covariant DanmakuAtlasPainter oldDelegate) {
    return oldDelegate._layoutVersion != _layoutVersion ||
        oldDelegate.engine != engine ||
        oldDelegate.playbackRate != playbackRate ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.timeOffsetSeconds != timeOffsetSeconds ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.fontFamily != fontFamily ||
        oldDelegate.outlineStyle != outlineStyle ||
        oldDelegate.shadowStyle != shadowStyle ||
        oldDelegate.locale != locale ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        !_listEquals(oldDelegate.fontFamilyFallback, fontFamilyFallback);
  }
}

// ════════════════════════════════════════════════════════════════
//  辅助类
// ════════════════════════════════════════════════════════════════

/// Paragraph 光栅化结果
class _RasterEntry {
  final ui.Image image;
  final double logicalWidth;
  final double logicalHeight;

  const _RasterEntry({
    required this.image,
    required this.logicalWidth,
    required this.logicalHeight,
  });
}

/// 阴影参数
class _ShadowParams {
  const _ShadowParams({
    required this.dx,
    required this.dy,
    required this.blurSigma,
    required this.opacity,
  });
  final double dx;
  final double dy;
  final double blurSigma;
  final double opacity;
}

/// 边缘裁剪/自发弹幕回退绘制信息
class _EdgeClipSprite {
  final _RasterEntry raster;
  final double drawX;
  final double drawY;
  final ui.Rect dstRect;
  final ui.Rect clippedDst;
  final bool isMe;

  _EdgeClipSprite({
    required this.raster,
    required this.drawX,
    required this.drawY,
    required this.dstRect,
    required this.clippedDst,
    required this.isMe,
  });
}

/// [ATLAS-DIAG-BUG3] 模式 1: Emoji 直接 drawParagraph 绘制信息
class _DiagEmojiParagraphItem {
  final ui.Paragraph fillParagraph;
  final ui.Paragraph? strokeParagraph;
  final double drawX;
  final double drawY;

  _DiagEmojiParagraphItem({
    required this.fillParagraph,
    this.strokeParagraph,
    required this.drawX,
    required this.drawY,
  });
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [ATLAS-DIAG-BUG1] 模式 3: drawImageRect 回退绘制信息
class _DiagFallbackItem {
  final ui.Image image;
  final double drawX;
  final double drawY;
  final double logicalW;
  final double logicalH;

  _DiagFallbackItem({
    required this.image,
    required this.drawX,
    required this.drawY,
    required this.logicalW,
    required this.logicalH,
  });
}
