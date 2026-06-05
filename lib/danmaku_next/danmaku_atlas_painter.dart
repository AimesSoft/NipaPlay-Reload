// ════════════════════════════════════════════════════════════════════
//  V6.0 Phase 1+2: 精灵图集画笔 + FNV-1a 整数哈希缓存键
//
//  替代 NipaPlayNextCanvasPainter:
//  - 精灵图集共享纹理 (1 张 atlas 替代 N 张独立纹理)
//  - drawImageRect 逐精灵绘制 (Impeller drawRawAtlas srcOver 混合缺陷绕过)
//  - String 缓存键 → int 哈希键 (CPU 5-10x↑)
//  - Emoji 弹幕绕过 toImageSync (Impeller 不支持 CBDT/COLRv1 离屏光栅化)
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
//  诊断日志节流 + 瓶颈计数器
// ════════════════════════════════════════════════════════════════

int _lastDiagPaintTimeMs = 0;
int _lastDiagSnapTimeMs = 0;
int _lastDiagDriftTimeMs = 0;
double _lastDiagPlaybackRate = 1.0;

/// 渲染管线瓶颈计数器
int _lastDiagBottleneckTimeMs = 0;
int _diagLayoutItems = 0;
int _diagCulledItems = 0;
int _diagAtlasFullItems = 0;
int _diagEdgeClipItems = 0;

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
  //  Phase 1: 精灵图集 + drawImageRect 渲染
  // ════════════════════════════════════════════════════════════════

  /// 精灵图集 — 所有弹幕预光栅化图像共享一张纹理
  static DanmakuSpriteAtlas? _spriteAtlas;

  /// 精灵绘制列表 — drawImageRect 从共享 atlas 纹理逐精灵绘制
  /// Bug 1 修复: 弃用 drawRawAtlas (Impeller srcOver 对 alpha=0 输出白色)，
  /// 改为 drawImageRect 逐精灵绘制。所有精灵从同一 atlas 纹理采样。
  static final List<_SpriteDrawInfo> _spriteDrawList = [];

  /// 边缘裁剪回退用 — drawImageRect
  static final List<_EdgeClipSprite> _edgeClipSprites = [];

  /// 当前帧精灵数
  static int _spriteCount = 0;

  /// drawImageRect 共享 Paint
  static final Paint _imagePaint = Paint()
    ..filterQuality = ui.FilterQuality.none;

  /// 自发弹幕边框
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;

  /// Emoji 直接 drawParagraph 绘制列表
  /// Bug 3 修复: Impeller toImageSync 不支持 CBDT/COLRv1 彩色 Emoji，
  /// 含 Emoji 弹幕绕过 toImageSync，直接 canvas.drawParagraph() 渲染。
  static final List<_EmojiDrawInfo> _emojiDrawList = [];

  /// Emoji bypass 计数（调试日志用）
  static int _emojiBypassCount = 0;

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

    // ── 重置精灵计数与绘制列表 ──
    _spriteCount = 0;
    _spriteDrawList.clear();
    _edgeClipSprites.clear();
    _emojiDrawList.clear();
    _emojiBypassCount = 0;

    // ── 瓶颈诊断计数器 ──
    _diagLayoutItems = items.length;
    _diagCulledItems = 0;
    _diagAtlasFullItems = 0;
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

      // ── Emoji 弹幕绕过 toImageSync — 直接 drawParagraph 渲染 ──
      // Bug 3 修复: Impeller toImageSync 不支持 CBDT/COLRv1 彩色 Emoji
      // 光栅化，产出全透明像素。含非 BMP 字符 (r > 0xFFFF) 的弹幕
      // 跳过 toImageSync + atlas 路径，直接走 canvas.drawParagraph()。
      // Emoji 占比极低，对整体性能影响可忽略。
      {
        final text = content.text;
        final hasNonBmp = text.runes.any((r) => r > 0xFFFF);
        if (hasNonBmp) {
          _emojiBypassCount++;
          _emojiDrawList.add(_EmojiDrawInfo(
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

      // ── 收集精灵绘制信息 — drawImageRect 从共享 atlas 纹理采样 ──
      // Bug 1 修复: 弃用 drawRawAtlas（Impeller srcOver 混合对源纹理 alpha=0
      // 像素输出白色），改为 drawImageRect 逐精灵绘制。所有精灵从同一张
      // atlas 纹理采样，GPU 可流水线化 draw call，压测 85.7 FPS @ 2150 条验证。
      _spriteDrawList.add(_SpriteDrawInfo(
        slot: slot,
        drawX: drawX,
        drawY: drawY,
        isMe: content.isMe,
      ));

      _spriteCount++;
    }

    // ── [ATLAS-DIAG-BUG2] 渲染管线瓶颈诊断输出 ──
    if (!kReleaseMode) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastDiagBottleneckTimeMs >= 2000) {
        _lastDiagBottleneckTimeMs = now;
        debugPrint('[ATLAS-DIAG] LAYOUT=$_diagLayoutItems '
            'CULL=$_diagCulledItems ATLAS_FULL=$_diagAtlasFullItems '
            'EDGE=$_diagEdgeClipItems EMOJI=$_emojiBypassCount '
            'RENDERED=$_spriteCount SLOTS=${_spriteAtlas?.slotCount ?? 0}');
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  提交渲染
    // ══════════════════════════════════════════════════════════════

    // ── 确保图集纹理可用 ──
    final atlas = _spriteAtlas!.ensureAtlas();

    // ── 1. drawImageRect 逐精灵绘制 — 从共享 atlas 纹理采样 ──
    // Bug 1 修复: 弃用 drawRawAtlas（Impeller srcOver 混合对源纹理
    // alpha=0 像素输出白色调制色），改用 drawImageRect 逐精灵绘制。
    // 所有精灵从同一张 atlas 纹理采样 → 1 次纹理绑定 + N 次 draw call，
    // GPU 可流水线化，压测 85.7 FPS @ 2150 条验证性能无回退。
    if (atlas != null) {
      for (final sprite in _spriteDrawList) {
        final slot = sprite.slot;
        final dstRect = ui.Rect.fromLTWH(
            sprite.drawX, sprite.drawY, slot.logicalW, slot.logicalH);
        canvas.drawImageRect(atlas, slot.srcRect, dstRect, _imagePaint);
      }
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

    // ── 3. Emoji 直接 drawParagraph 渲染 ──
    // Bug 3 修复: Impeller toImageSync 不支持 CBDT/COLRv1 彩色 Emoji
    // 光栅化，产出全透明像素。含 Emoji 弹幕绕过 toImageSync + atlas 路径，
    // 直接使用 canvas.drawParagraph() 渲染。Emoji 占比极低，性能影响可忽略。
    if (_emojiDrawList.isNotEmpty) {
      for (final emoji in _emojiDrawList) {
        if (emoji.strokeParagraph != null) {
          canvas.drawParagraph(emoji.strokeParagraph!,
              ui.Offset(emoji.drawX, emoji.drawY));
        }
        canvas.drawParagraph(emoji.fillParagraph,
            ui.Offset(emoji.drawX, emoji.drawY));
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

/// Emoji 直接 drawParagraph 绘制信息 — 绕过 toImageSync 离屏渲染
/// (Impeller toImageSync 不支持 CBDT/COLRv1 彩色 Emoji 光栅化)
class _EmojiDrawInfo {
  final ui.Paragraph fillParagraph;
  final ui.Paragraph? strokeParagraph;
  final double drawX;
  final double drawY;

  _EmojiDrawInfo({
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

/// 从精灵图集绘制信息 — drawImageRect 从共享 atlas 纹理采样
class _SpriteDrawInfo {
  final SpriteSlot slot;
  final double drawX;
  final double drawY;
  final bool isMe;

  _SpriteDrawInfo({
    required this.slot,
    required this.drawX,
    required this.drawY,
    required this.isMe,
  });
}
