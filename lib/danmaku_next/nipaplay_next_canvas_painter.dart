import 'dart:collection';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import 'nipaplay_next_engine.dart';

/// [NEXT-DIAG] paint 日志节流
int _lastDiagPaintTimeMs = 0;

/// [NEXT-DIAG] 诊断日志节流
int _lastDiagSnapTimeMs = 0;
int _lastDiagDriftTimeMs = 0;

/// playbackRate 变化追踪（用于倍速切换时同步 displayX）
double _lastDiagPlaybackRate = -1.0;

/// 高性能弹幕画师 — vsync 驱动 + Paragraph 预光栅化 + 增量定位
///
/// ┌──────────────────────┬──────────────────────────┬──────────────────────────┐
/// │ 环节                 │ v4 实现                  │ v5 实现                 │
/// ├──────────────────────┼──────────────────────────┼──────────────────────────┤
/// │ 重绘驱动             │ playbackTimeMs ValueNotifier│ AnimationController vsync│
/// │ 帧间隔(dt)           │ Stopwatch 原始           │ Stopwatch + EMA 平滑    │
/// │ 文本渲染             │ drawParagraph(逐字形quad)│ toImageSync+drawImageRect│
/// │ 描边(uniform)        │ 8方向Shadow烘入单Para    │ 同上 + 光栅化合图       │
/// │ 描边(stroke)         │ stroke Para + fill Para  │ 光栅化合成单张 Image    │
/// │ 阴影                 │ TextStyle.shadows 烘入   │ 同上 + 光栅化           │
/// │ GPU 命令             │ O(n×glyphs) drawParagraph│ O(n) drawImageRect blit │
/// │ 倍速滚动             │ 增量定位(墙钟dt×rate)    │ 同上 + EMA dt 平滑     │
/// │ 批量绘制             │ 始终PictureRecorder      │ 同上                    │
/// │ 视口剔除             │ 无                       │ drawX+width<0 → skip   │
/// │ Opacity              │ 始终 Opacity widget      │ opacity<1 才包裹        │
/// │ Paragraph缓存        │ LRU (O(n) hit)           │ FIFO (O(1) hit)        │
/// └──────────────────────┴──────────────────────────┴──────────────────────────┘
///
/// GPU 渲染路径对比：
/// - drawParagraph: GPU 逐字形查找字形纹理 → 逐字形 quad → n×glyphs 次 GPU op
/// - drawImageRect: GPU 单次纹理采样 + 单 quad → 1 次 GPU op/弹幕
/// - stroke+fill 光栅化合成: 2 drawParagraph → 1 drawImageRect (GPU op 减半)
class NipaPlayNextCanvasPainter extends CustomPainter {
  NipaPlayNextCanvasPainter({
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

  /// vsync 动画控制器 — 以屏幕刷新率驱动 paint()
  final Animation<double> vsyncNotifier;

  final NipaPlayNextEngine engine;
  final ValueListenable<double> playbackTimeMs;
  final double playbackRate;

  /// 视频是否正在播放 — 暂停时强制 dtSeconds=0，阻止 displayX 推进。
  ///
  /// 根因修复：暂停状态下，Consumer rebuild 仍可能触发 paint()（因为
  /// Flutter 框架在新旧 painter 对象引用不同时调用 markNeedsPaint），
  /// 而墙钟 Stopwatch 始终运行，导致 dtSeconds > 0，displayX 被推进，
  /// 与冻结的 item.x 产生 drift → 渐进式校正拉回 → 下次 rebuild 又推进
  /// → 振荡/鬼畜。将 isPlaying 纳入 dt 计算，暂停时 dt=0 彻底消除此问题。
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

  /// fontFamilyFallback 紧凑键（构造时计算一次）
  late final String _ffbKey = fontFamilyFallback?.join('\u0000') ?? '';

  /// 缓存 key 的不变前缀（构造时计算一次），避免每帧每项重复字符串插值
  /// 格式: "{fontFamily}|{ffbKey}|"
  late final String _keyPrefix = '${fontFamily ?? ''}|$_ffbKey|';

  /// Paragraph 全局缓存（fill / stroke / uniform-outline 共用）
  /// 使用 FIFO 而非 LRU：cache hit 时不执行 remove+reinsert（O(n)），
  /// 仅在 miss 时淘汰最旧条目。对 6000 条缓存、每帧数百次命中，
  /// 省去 O(n×hits) 的 LinkedHashMap 重排开销。
  static final LinkedHashMap<String, ui.Paragraph> _pCache =
      LinkedHashMap<String, ui.Paragraph>();
  static const int _pCacheLimit = 6000;

  /// 光栅化图像缓存 — Paragraph 预渲染为 ui.Image 后以 drawImageRect 绘制。
  /// drawImageRect 是单次 GPU 纹理 blit，比 drawParagraph（逐字形 quad）
  /// 快一个数量级。Image 按 devicePixelRatio 光栅化，确保原生分辨率清晰。
  static final LinkedHashMap<String, _RasterEntry> _rasterCache =
      LinkedHashMap<String, _RasterEntry>();
  static const int _rasterCacheLimit = 2000;
  static double _cacheDpr = 0.0;

  /// drawImageRect 共享 Paint
  static final Paint _imagePaint = Paint()
    ..filterQuality = ui.FilterQuality.low;

  /// 自发弹幕边框
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;

  /// 墙钟 Stopwatch — 测量真实帧间隔，消除平滑时钟漂移
  static final Stopwatch _wallClock = Stopwatch()..start();
  static int _lastWallUs = 0;

  /// dt 指数移动平均（EMA）— 消除帧间隔微抖导致的视觉速度不均。
  ///
  /// 60Hz vsync 帧间隔交替 ~16.5/16.8ms，原始 dt 直接用于
  /// `displayX -= speed * dt * rate` 会使滚动速度微抖（视觉"呼吸感"）。
  /// EMA 平滑后帧间速度差异 < 0.5%，人眼不可感知。
  /// alpha=0.3 约等效3帧平滑窗口：足够消除微抖，又足够快以追踪真实变化。
  static double _smoothedDtSeconds = 0.0;
  static const double _dtEmaAlpha = 0.3;

  /// uniform 描边8方向偏移（与旧版 _paintUniformOutline 一致）
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
  //  主绘制循环 — vsync 驱动 + 墙钟增量定位 + Paragraph 光栅化
  // ════════════════════════════════════════════════════════════════

  @override
  void paint(Canvas canvas, Size size) {
    final diagPaintSw = kDebugMode ? Stopwatch() : null;
    diagPaintSw?.start();

    // ── 墙钟 dt：真实帧间隔，不受平滑时钟漂移/seek保护影响 ──
    final currentWallUs = _wallClock.elapsedMicroseconds;
    final double rawDtSeconds;
    if (_lastWallUs == 0 || currentWallUs < _lastWallUs) {
      rawDtSeconds = 0.0; // 首帧或 Stopwatch 重置
    } else {
      final deltaUs = currentWallUs - _lastWallUs;
      // 过大间隔（>100ms，暂停恢复/后台切换）→ 不推进，避免跳帧
      rawDtSeconds = (deltaUs < 100000) ? deltaUs / 1000000.0 : 0.0;
    }
    _lastWallUs = currentWallUs;

    // ── EMA 平滑 dt — 消除帧间隔微抖导致的视觉滚动速度不均 ──
    // 大跳变（暂停恢复/后台切换：rawDt=0 → 恢复后首帧 rawDt 正常）
    // 时重置平滑器，避免滞后拖尾
    // ── 暂停状态感知：暂停时强制 dt=0，阻止 displayX 推进 ──
    // 根因修复：暂停时 vsyncController.stop()，但 Consumer rebuild 仍可能
    // 触发 paint()（Flutter 框架因 painter 对象引用变化调用 markNeedsPaint），
    // 墙钟 Stopwatch 始终运行 → dtSeconds > 0 → displayX 被推进 →
    // 与冻结的 item.x 产生 drift → 渐进式校正拉回 → 振荡/鬼畜。
    // 暂停时 dt=0 彻底消除 displayX 的任何增量推进。
    final double dtSeconds;
    if (!isPlaying) {
      // 暂停状态：dt 强制为 0，displayX 不会被推进
      dtSeconds = 0.0;
      // 不更新 _smoothedDtSeconds，保留历史值供恢复后平滑过渡
    } else if (rawDtSeconds == 0.0) {
      dtSeconds = 0.0; // 跳变帧不推进
      // 不更新 _smoothedDtSeconds，保留历史值供恢复后平滑过渡
    } else if (_smoothedDtSeconds == 0.0) {
      // 首帧或恢复后首帧：直接采用原始值
      dtSeconds = rawDtSeconds;
      _smoothedDtSeconds = rawDtSeconds;
    } else {
      // 正常帧：EMA 平滑
      _smoothedDtSeconds = _dtEmaAlpha * rawDtSeconds +
          (1.0 - _dtEmaAlpha) * _smoothedDtSeconds;
      dtSeconds = _smoothedDtSeconds;
    }

    final items =
        engine.layout(playbackTimeMs.value / 1000.0 + timeOffsetSeconds);
    if (items.isEmpty) {
      diagPaintSw?.stop();
      return;
    }

    // ── 始终使用 PictureRecorder ──
    // Impeller/Skia 均受益于单 Picture 提交：
    // 减少 render pass 切换，允许 GPU 命令缓冲整体优化
    final recorder = ui.PictureRecorder();
    final dc = Canvas(recorder);

    // 预计算阴影参数（所有弹幕共享，只算一次）
    final shadowParams = _resolveShadowParams(fontSize);

    // ── DPR 变更检测：窗口跨显示器移动时 DPR 可能变化 ──
    // 清除所有光栅化缓存（旧 DPR 下的 Image 尺寸不匹配）
    if (devicePixelRatio != _cacheDpr) {
      _clearRasterCache();
      _cacheDpr = devicePixelRatio;
    }

    // ── playbackRate 变化检测：倍速切换时重置所有 displayX → item.x ──
    // 防止倍速切换后 displayX 与 item.x 产生大偏差导致鬼畜回弹。
    // 原因：displayX 按墙钟dt×rate推进，item.x按视频时间推进，
    // 倍速切换时两个时间源短暂不同步，偏差可超50px触发硬snap。
    // 重置后所有弹幕从引擎绝对位置重新开始增量推进，消除偏差。
    if (playbackRate != _lastDiagPlaybackRate) {
      if (!kReleaseMode) {
        debugPrint('[NEXT-DIAG] RATE CHANGE: $_lastDiagPlaybackRate → $playbackRate');
      }
      _lastDiagPlaybackRate = playbackRate;
      // 倍速切换：将所有可见滚动弹幕的 displayX 强制同步到 item.x
      for (final item in items) {
        if (item.scrollSpeed > 0.0) {
          item.displayX = item.x;
        }
      }
    }

    // [NEXT-DIAG] 偏差采样计数器（每100个滚动弹幕采样1个）
    int diagScrollItemCount = 0;

    for (final item in items) {
      final content = item.content;

      // ── 增量定位：滚动弹幕用 displayX + 墙钟dt × playbackRate 推进 ──
      // 渐进式校正策略：
      //   - 首次出现(NaN) / seek大跳变(>200px)：硬snap（无视觉干扰）
      //   - 偏差 50~200px：渐进式校正 lerp(displayX→item.x, 0.15/帧)
      //     每帧缩减偏差15%，~10帧(≈40ms@240Hz)收敛到<5px不可感知
      //   - 偏差 <50px：不校正，保持增量定位的视觉流畅性
      // 这消除了旧版硬snap 50px阈值导致的鬼畜/回弹，
      // 同时保持增量定位在倍速/暂停恢复时的视觉平滑。
      final double drawX;
      if (item.scrollSpeed > 0.0) {
        if (item.displayX.isNaN) {
          // 首次出现：从引擎绝对位置初始化
          item.displayX = item.x;
        } else {
          // 正常播放：墙钟增量 × playbackRate = 真实视觉推进量
          item.displayX -= item.scrollSpeed * dtSeconds * playbackRate;

          // 渐进式校正：将 displayX 逐渐拉向 item.x
          final drift = item.displayX - item.x;
          final absDrift = drift.abs();
          if (absDrift > 200.0) {
            // seek级大跳变：硬snap（用户预期跳变，无视觉干扰）
            item.displayX = item.x;
            if (!kReleaseMode) {
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - _lastDiagSnapTimeMs >= 1000) {
                debugPrint('[NEXT-DIAG] HARD SNAP: drift=${drift.toStringAsFixed(1)}px → 0');
                _lastDiagSnapTimeMs = now;
              }
            }
          } else if (absDrift > 50.0) {
            // 中等偏差：渐进式校正（每帧缩减15%，约10帧≈40ms收敛）
            // 使用固定lerp因子而非dt相关因子，确保收敛速度
            // 与帧率无关（高帧率=更快收敛，低帧率=更慢但单步更大）
            item.displayX = item.displayX + (item.x - item.displayX) * 0.15;
            if (!kReleaseMode) {
              diagScrollItemCount++;
              if (diagScrollItemCount % 200 == 0) {
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - _lastDiagDriftTimeMs >= 2000) {
                  debugPrint('[NEXT-DIAG] SOFT CORRECT: drift=${drift.toStringAsFixed(1)}px '
                      'rate=$playbackRate');
                  _lastDiagDriftTimeMs = now;
                }
              }
            }
          }
          // absDrift <= 50px：不校正，保持增量定位视觉流畅性
        }
        drawX = item.displayX;
      } else {
        drawX = item.x;
      }
      final drawY = item.y;

      // ── 视口剔除：跳过完全不可见的弹幕 ──
      // drawX + width < 0 → 已滚出左侧；drawX > size.width → 尚未进入右侧
      // 剔除后无需 Paragraph 查找/绘制，对密集弹幕场景可减少 30-50% 绘制量
      final itemWidth = item.width;
      if (itemWidth > 0.0) {
        if (drawX + itemWidth < 0.0 || drawX > size.width) {
          continue;
        }
      }

      final adjFontSize = fontSize * content.fontSizeMultiplier;
      final itemStrokeColor = _getStrokeColor(textColor: content.color);
      final int colorVal = content.color.toARGB32();
      final int strokeColorVal = itemStrokeColor.toARGB32();

      // ── 获取或构建 Paragraph ──
      final ui.Paragraph fillP;
      final ui.Paragraph? strokeP;
      String rasterKey; // 光栅化缓存键

      if (outlineStyle == DanmakuOutlineStyle.uniform) {
        // uniform 描边：8方向零模糊 Shadow 烘入 fill Paragraph
        final radius = _resolveUniformOutlineRadius(adjFontSize);
        // ⚠️ 缓存键必须包含 colorVal（填充色），否则不同颜色的同文本弹幕
        // 会命中同一缓存条目，导致颜色被"染"成先缓存弹幕的颜色。
        // strokeColorVal 仅有黑/白两种，无法区分不同填充色。
        final uKey = _key(content, adjFontSize, colorVal,
            'u${radius.toStringAsFixed(1)}|$strokeColorVal');
        fillP = _getOrBuild(uKey, () => _buildUniformOutlineParagraph(
              content, adjFontSize, content.color, itemStrokeColor,
              radius, shadowParams,
            ));
        strokeP = null;
        rasterKey = uKey;
      } else if (outlineStyle == DanmakuOutlineStyle.stroke) {
        // thin stroke 描边：独立 stroke Paragraph + fill Paragraph
        // 光栅化时两者合成单张 Image，只需1次 drawImageRect
        final strokeWidth = _resolveStrokeWidth(adjFontSize);
        final sKey = _key(content, adjFontSize, strokeColorVal,
            's${strokeWidth.toStringAsFixed(1)}');
        strokeP = _getOrBuild(sKey, () => _buildStrokeParagraph(
              content, adjFontSize, itemStrokeColor, strokeWidth, shadowParams,
            ));

        final fKey = _key(content, adjFontSize, colorVal, 'f');
        fillP = _getOrBuild(fKey,
            () => _buildFillParagraph(content, adjFontSize, content.color));
        // 光栅化键：组合 stroke+fill 的唯一键
        rasterKey = 'R|$sKey|$fKey';
      } else if (shadowParams != null) {
        // 无描边有阴影：阴影烘入填充
        final fsKey = _key(content, adjFontSize, colorVal, 'fs');
        fillP = _getOrBuild(fsKey, () => _buildFillWithShadowParagraph(
              content, adjFontSize, content.color, shadowParams,
            ));
        strokeP = null;
        rasterKey = fsKey;
      } else {
        // 纯填充
        final fKey = _key(content, adjFontSize, colorVal, 'f');
        fillP = _getOrBuild(fKey,
            () => _buildFillParagraph(content, adjFontSize, content.color));
        strokeP = null;
        rasterKey = fKey;
      }

      // ── 光栅化：Paragraph → ui.Image → drawImageRect ──
      // drawParagraph: GPU 逐字形 quad ≈ 10 ops/弹幕
      // drawImageRect: GPU 单次纹理 blit = 1 op/弹幕
      // stroke+fill 2个 Paragraph 合成1张 Image：2 drawParagraph → 1 drawImageRect
      final raster = _getOrRasterize(rasterKey, fillP, strokeP);

      // 自发弹幕边框
      if (content.isMe) {
        dc.drawRect(
          Rect.fromLTWH(drawX - 2, drawY - 2,
              raster.logicalWidth + 4, raster.logicalHeight + 4),
          _selfSendPaint,
        );
      }

      // 单次 GPU 纹理 blit — 替代 drawParagraph 的逐字形 quad
      // ── 边缘裁剪：手动将 dstRect 裁剪到 canvas 可见范围内 ──
      // Impeller 渲染器在 dstRect 部分超出 canvas clip rect 时，
      // 可能整个丢弃 drawImageRect（GPU whole-quad rejection），
      // 导致弹幕到边界时整个消失而非逐渐滑出。
      // 手动裁剪 src/dst rect 可确保目标矩形完全在 canvas 内，
      // 弹幕滑出边界时只有超出部分不可见，实现平滑的边缘过渡。
      final dstRect = Rect.fromLTWH(
          drawX, drawY, raster.logicalWidth, raster.logicalHeight);
      final canvasRect = Rect.fromLTWH(0, 0, size.width, size.height);
      final clippedDst = dstRect.intersect(canvasRect);
      if (clippedDst.isEmpty) continue; // 双重保险

      // 按比例裁剪 srcRect，确保纹理采样与可见区域对应
      final scaleX =
          raster.image.width.toDouble() / raster.logicalWidth;
      final scaleY =
          raster.image.height.toDouble() / raster.logicalHeight;
      final srcRect = Rect.fromLTWH(
        (clippedDst.left - dstRect.left) * scaleX,
        (clippedDst.top - dstRect.top) * scaleY,
        clippedDst.width * scaleX,
        clippedDst.height * scaleY,
      );

      dc.drawImageRect(raster.image, srcRect, clippedDst, _imagePaint);
    }

    // 单次 drawPicture 提交全部绘制命令 — GPU 命令缓冲整体优化
    final picture = recorder.endRecording();
    canvas.drawPicture(picture);

    // [NEXT-DIAG] paint 完成后检查耗时
    diagPaintSw?.stop();
    if (diagPaintSw != null && diagPaintSw.elapsedMicroseconds > 2000) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastDiagPaintTimeMs >= 2000) {
        _lastDiagPaintTimeMs = now;
        debugPrint(
            '[NEXT-DIAG] SLOW PAINT: ${diagPaintSw.elapsedMicroseconds}μs items=${items.length}');
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Paragraph 光栅化 — 一次 toImageSync，逐帧 drawImageRect
  // ════════════════════════════════════════════════════════════════

  /// 查找或创建光栅化 Image。
  /// 若缓存命中则直接返回；若 miss 则将 Paragraph(s) 渲染到
  /// PictureRecorder 后以 `toImageSync(pixelRatio)` 光栅化为 ui.Image。
  _RasterEntry _getOrRasterize(
    String key,
    ui.Paragraph fillP,
    ui.Paragraph? strokeP,
  ) {
    final cached = _rasterCache[key];
    if (cached != null) {
      return cached; // FIFO: 不重排
    }

    // 光栅化：在临时 Canvas 上绘制 Paragraph(s)，合成单张 Image
    // ⚠️ 必须使用 maxIntrinsicWidth 而非 width：
    //   Paragraph.layout(ParagraphConstraints(width: double.infinity)) 后，
    //   Paragraph.width 返回约束宽度 infinity，而非文本实际宽度；
    //   maxIntrinsicWidth 才是文本在无约束下的真实像素宽度。
    //   用 infinity 会产生无效 Image 尺寸和 drawImageRect 目标矩形，
    //   导致弹幕完全不可见。
    final logicalW = strokeP != null
        ? math.max(fillP.maxIntrinsicWidth, strokeP.maxIntrinsicWidth)
        : fillP.maxIntrinsicWidth;
    final logicalH = strokeP != null
        ? math.max(fillP.height, strokeP.height)
        : fillP.height;

    final rRecorder = ui.PictureRecorder();
    final rCanvas = Canvas(rRecorder);

    // stroke 先画（底层），fill 后画（顶层）
    if (strokeP != null) {
      rCanvas.drawParagraph(strokeP, Offset.zero);
    }
    rCanvas.drawParagraph(fillP, Offset.zero);

    final picture = rRecorder.endRecording();

    final image = picture.toImageSync(
      (logicalW * devicePixelRatio).ceil().clamp(1, 4096),
      (logicalH * devicePixelRatio).ceil().clamp(1, 4096),
    );

    final entry = _RasterEntry(
      image: image,
      logicalWidth: logicalW,
      logicalHeight: logicalH,
    );

    // FIFO 淘汰
    if (_rasterCache.length >= _rasterCacheLimit && _rasterCache.isNotEmpty) {
      final oldest = _rasterCache.remove(_rasterCache.keys.first);
      oldest?.image.dispose();
    }
    _rasterCache[key] = entry;
    return entry;
  }

  /// DPR 变更时清除所有光栅化缓存
  static void _clearRasterCache() {
    for (final entry in _rasterCache.values) {
      entry.image.dispose();
    }
    _rasterCache.clear();
  }

  // ════════════════════════════════════════════════════════════════
  //  Paragraph 构建 — 一次构建，逐帧复用
  // ════════════════════════════════════════════════════════════════

  /// 基础 ParagraphStyle
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

  /// 填充 Paragraph（无阴影）
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

  /// 描边 Paragraph（含可选阴影烘入）— 用于 DanmakuOutlineStyle.stroke
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
              offset: Offset(shadow.dx, shadow.dy),
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

  /// uniform 描边 Paragraph — 8方向零模糊 Shadow 几何膨胀
  ///
  /// 在 TextStyle.shadows 中放入 8 个 Shadow(offset=方向×R, blurRadius=0)，
  /// 视觉效果等价于旧版 _paintUniformOutline 的8次偏移绘制（几何膨胀），
  /// 但全部烘入单个 Paragraph，光栅化后只需1次 drawImageRect。
  ui.Paragraph _buildUniformOutlineParagraph(
    DanmakuContentItem content,
    double fontSize,
    Color fillColor,
    Color outlineColor,
    double radius,
    _ShadowParams? shadow,
  ) {
    final shadows = <Shadow>[];

    // drop shadow 放在最底层（Skia 按列表顺序先渲染）
    if (shadow != null) {
      shadows.add(Shadow(
        color: Color.fromRGBO(0, 0, 0, shadow.opacity),
        blurRadius: shadow.blurSigma,
        offset: Offset(shadow.dx, shadow.dy),
      ));
    }

    // 8方向零模糊 outline — 几何膨胀
    for (final (dx, dy) in _uniformOutlineDirs) {
      shadows.add(Shadow(
        color: outlineColor,
        offset: Offset(dx * radius, dy * radius),
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

  /// 填充+阴影 Paragraph（无描边时使用，阴影烘入填充）
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
            offset: Offset(shadow.dx, shadow.dy),
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

  /// 向 ParagraphBuilder 追加文本（含 countText 分段处理）
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
  //  缓存 — 紧凑 String 键 + FIFO 淘汰
  // ════════════════════════════════════════════════════════════════

  /// 生成 Paragraph 缓存键。
  /// 使用预计算的 [_keyPrefix] 避免每帧每项重复拼接 fontFamily/ffbKey。
  String _key(DanmakuContentItem content, double fontSize, int colorValue,
      String variant) {
    final suffix = content.countText != null
        ? '${content.text}|${content.countText}'
        : content.text;
    return '$variant|${fontSize.toStringAsFixed(1)}|$colorValue|$_keyPrefix$suffix';
  }

  /// FIFO 缓存查找：命中时仅返回，不执行 remove+reinsert。
  /// LRU 的 remove+reinsert 在 6000 条缓存上每帧数百次命中时产生
  /// O(n×hits) 的 LinkedHashMap 重排开销；FIFO 省去此开销，
  /// 且弹幕场景中"最近使用=即将淘汰"的反局部性使 FIFO 更优。
  ui.Paragraph _getOrBuild(String key, ui.Paragraph Function() builder) {
    final cached = _pCache[key];
    if (cached != null) {
      return cached; // FIFO: 不重排，O(1) 命中
    }
    final p = builder();
    if (_pCache.length >= _pCacheLimit && _pCache.isNotEmpty) {
      _pCache.remove(_pCache.keys.first); // 淘汰最旧
    }
    _pCache[key] = p;
    return p;
  }

  // ════════════════════════════════════════════════════════════════
  //  样式计算
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
  bool shouldRepaint(covariant NipaPlayNextCanvasPainter oldDelegate) {
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
//  辅助
// ════════════════════════════════════════════════════════════════

/// Paragraph 光栅化结果 — 预渲染为 GPU 纹理后的缓存条目
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

bool _listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
