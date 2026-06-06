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

/// [PAUSE-RESUME] 上次 isPlaying 状态 — 追踪暂停恢复过渡
bool _lastIsPlaying = true;

/// [PAUSE-RESUME] 暂停恢复诊断 — 追踪恢复首帧 drift 分布
int _diagResumeMaxDriftBeforePx = 0;  // 恢复首帧强制同步前的最大drift(px)
int _diagResumeDriftOver50Count = 0;   // 恢复首帧drift>50px的弹幕数
int _diagResumeDriftOver200Count = 0;  // 恢复首帧drift>200px的弹幕数

/// 渲染管线瓶颈计数器
int _lastDiagBottleneckTimeMs = 0;
int _diagLayoutItems = 0;
int _diagCulledItems = 0;
int _diagAtlasFullItems = 0;
int _diagEdgeClipItems = 0;

/// [EDGE-BUG] 边缘裁剪诊断 — 验证假设1: atlas路径drawImageRect缺少clip保护
int _lastDiagEdgeBugTimeMs = 0;
int _diagEdgeNearRightCount = 0;  // dstRect.right 接近 canvasRect.right 的弹幕数
int _diagEdgeNearLeftCount = 0;   // dstRect.left 接近 0 的弹幕数
int _diagAtlasDstOutOfBoundsCount = 0; // atlas路径dstRect实际超出画布的弹幕数
int _diagEdgeClipRenderedCount = 0;   // 边缘裁剪路径渲染的弹幕数

/// [DRIFT-BUG] 漂移校正诊断 — 验证假设2: 增量定位漂移校正导致鬼畜
int _diagDriftCorrectionCount = 0;    // 本帧触发漂移校正的弹幕数
int _diagHardSnapCount = 0;           // 本帧触发硬snap的弹幕数
double _diagMaxDrift = 0.0;           // 本帧最大漂移值

/// ════════════════════════════════════════════════════════════════
///  [DIAG-V6] V6.0 四大问题诊断计数器
/// ════════════════════════════════════════════════════════════════

/// [TIME-ALIGN] 问题1: 弹幕时间对齐/回弹 — playbackTimeMs更新频率追踪
double _lastDiagPlaybackTimeMsValue = -1e9;
int _lastDiagPlaybackTimeUpdateMs = 0;  // 上次playbackTimeMs变化的墙钟时间
int _diagPlaybackTimeUpdates = 0;       // 诊断窗口内playbackTimeMs更新次数
int _diagPlaybackTimeMaxIntervalMs = 0;  // 最大更新间隔
int _diagPlaybackTimeMinIntervalMs = 0x7FFFFFFF; // 最小更新间隔
int _diagDrift50to200Count = 0;          // drift在50-200px范围的弹幕数
int _diagDriftOver200Count = 0;          // drift超过200px的弹幕数
double _diagDriftUnder50Max = 0.0;       // drift<50px时的最大值（记录轻微漂移）

/// [MEM-GC] 问题2: 内存回收 — GC压力追踪
int _diagSpriteAllocCount = 0;           // 本帧_SpriteDrawInfo分配数
int _diagRasterCacheMissCount = 0;       // 本帧rasterCache miss数
int _diagRasterCacheHitCount = 0;        // 本帧rasterCache hit数
int _diagAtlasRebuildAccum = 0;          // 累计atlas重建次数（诊断窗口）
int _diagRasterEvictAccum = 0;           // 累计rasterCache淘汰次数（诊断窗口）

/// [P1] 未提交slot fallback渲染计数 — 追踪atlas节流期间的fallback路径
int _diagUncommittedFallbackCount = 0;

/// [ATLAS-REBUILD-DETAIL] 每帧新增slot计数 vs 已有slot命中计数
int _diagSlotNewCount = 0;               // 本帧新增slot数（addSprite调用）
int _diagSlotHitCount = 0;               // 本帧已有slot命中数（getSlot命中）
int _diagParagraphNewCount = 0;          // 本帧Paragraph新构建数（pCache miss）
int _diagEnsureAtlasUs = 0;              // 本帧ensureAtlas耗时(μs)
int _diagDrawUs = 0;                     // 本帧draw阶段耗时(μs)

/// [FIRST-FRAME] 问题3: 首帧卡顿 — 首帧各阶段计时
bool _diagFirstFrameDone = false;
int _diagFirstFramePaintUs = 0;          // 首帧paint总耗时
int _diagFirstFrameLayoutUs = 0;         // 首帧layout耗时
int _diagFirstFrameRasterizeUs = 0;     // 首帧toImageSync耗时
int _diagFirstFrameEnsureAtlasUs = 0;    // 首帧ensureAtlas耗时
int _diagFirstFrameDrawUs = 0;           // 首帧draw阶段耗时
int _diagFirstFrameParagraphBuildUs = 0; // 首帧Paragraph构建耗时

/// [SEEK-PERF] 问题4: 进度条拖拽 — seek期间性能追踪
int _diagSeekPaintOver2msCount = 0;      // paint耗时>2ms的帧数
int _diagSeekAtlasRebuildCount = 0;      // seek期间atlas重建次数
double _diagLastPlaybackTimeMsJump = 0.0; // 上次playbackTimeMs跳变量(ms)

/// [DRIFT-DETAIL] HARD_SNAP 瞬间的 dt 值追踪
double _diagHardSnapDtSeconds = 0.0;     // 最近HARD_SNAP帧的dt值
int _diagHardSnapDtAnomalyCount = 0;     // dt异常(>20ms)导致HARD_SNAP的次数

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

  /// shadowStyle 预计算哈希 — 不同阴影风格产生不同缓存键，
  /// 避免切换 shadowStyle 后命中旧 Paragraph/Raster 缓存
  late final int _shadowStyleHash = shadowStyle.index.hashCode;

  /// 不变前缀组合哈希 = fontFamily + ffb + locale + shadowStyle
  late final int _keyPrefixHash =
      _combineHashes([_fontFamilyHash, _ffbHash, _localeHash, _shadowStyleHash]);

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

  /// [P0] 首帧分帧构建 — 每帧允许的缓存miss上限（Paragraph新构建 + rasterize miss）
  /// 首帧150，后续帧递增150，连续3帧无miss后取消限制(=0)
  /// 统一描边(uniform)下150≈75条弹幕/帧，递增后约10帧(@80Hz≈125ms)补全全部弹幕
  static int _frameBuildBudget = 150;

  /// [P0] 连续无缓存miss帧计数 — 连续3帧无miss后取消预算限制
  static int _consecutiveNoMissFrames = 0;

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

    // ── [TIME-ALIGN] 问题1诊断: 追踪 playbackTimeMs 更新频率 ──
    // vsync以60-240Hz调用paint()，但playbackTimeMs可能仅8-30Hz更新。
    // 记录更新间隔，验证双时间源drift假设。
    final currentPlaybackTimeMs = playbackTimeMs.value;
    if (!kReleaseMode && currentPlaybackTimeMs != _lastDiagPlaybackTimeMsValue) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastDiagPlaybackTimeUpdateMs > 0) {
        final intervalMs = now - _lastDiagPlaybackTimeUpdateMs;
        if (intervalMs > _diagPlaybackTimeMaxIntervalMs) {
          _diagPlaybackTimeMaxIntervalMs = intervalMs;
        }
        if (intervalMs < _diagPlaybackTimeMinIntervalMs) {
          _diagPlaybackTimeMinIntervalMs = intervalMs;
        }
        // [SEEK-PERF] 问题4诊断: 追踪 playbackTimeMs 跳变量
        final jumpMs = (currentPlaybackTimeMs - _lastDiagPlaybackTimeMsValue).abs();
        if (jumpMs > _diagLastPlaybackTimeMsJump) {
          _diagLastPlaybackTimeMsJump = jumpMs;
        }
      }
      _lastDiagPlaybackTimeUpdateMs = now;
      _diagPlaybackTimeUpdates++;
      _lastDiagPlaybackTimeMsValue = currentPlaybackTimeMs;
    }

    // ── [FIRST-FRAME] 问题3诊断: layout计时 ──
    final diagLayoutSw = (kDebugMode && !_diagFirstFrameDone) ? Stopwatch() : null;
    diagLayoutSw?.start();

    final items =
        engine.layout(playbackTimeMs.value / 1000.0 + timeOffsetSeconds);

    diagLayoutSw?.stop();
    if (diagLayoutSw != null) {
      _diagFirstFrameLayoutUs = diagLayoutSw.elapsedMicroseconds;
    }

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
      // [P0] DPR变更导致缓存清空，重置构建预算
      _frameBuildBudget = 150;
      _consecutiveNoMissFrames = 0;
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

    // ── [PAUSE-RESUME] isPlaying 变化检测 ──
    // 诊断假设: 暂停恢复后 playbackTimeMs 大跳变 → item.x 突变 → displayX 未同步
    // → drift 瞬间超 200px → HARD_SNAP → 弹幕跳位
    // 验证方法: 记录恢复首帧所有可见滚动弹幕的 drift 分布
    if (isPlaying != _lastIsPlaying) {
      if (!kReleaseMode) {
        final deltaPtm = (playbackTimeMs.value - _lastDiagPlaybackTimeMsValue).abs();
        debugPrint('[PAUSE-RESUME] isPlaying: $_lastIsPlaying → $isPlaying '
            'ptm=${playbackTimeMs.value.toStringAsFixed(0)}ms '
            'deltaPtm=${deltaPtm.toStringAsFixed(0)}ms');
      }

      if (isPlaying) {
        // ── 恢复播放：诊断漂移 + 重置墙钟 ──
        // 重置 _lastWallUs 防止恢复首帧 dt 包含暂停间隔
        _lastWallUs = _wallClock.elapsedMicroseconds;
        _smoothedDtSeconds = 0.0; // EMA 从零开始收敛

        // 诊断：恢复首帧强制同步前的 drift 分布
        _diagResumeMaxDriftBeforePx = 0;
        _diagResumeDriftOver50Count = 0;
        _diagResumeDriftOver200Count = 0;
        for (final item in items) {
          if (item.scrollSpeed > 0.0) {
            if (item.displayX.isNaN) continue;
            final driftBefore = (item.displayX - item.x).abs();
            if (driftBefore > _diagResumeMaxDriftBeforePx) {
              _diagResumeMaxDriftBeforePx = driftBefore.round();
            }
            if (driftBefore > 50.0) _diagResumeDriftOver50Count++;
            if (driftBefore > 200.0) _diagResumeDriftOver200Count++;
            // ✅ P1-NEW 修复：恢复播放时强制同步 displayX → item.x
            // 根因：暂停恢复后 playbackTimeMs 跳变 → item.x 突变 → displayX 未同步
            // → drift 瞬间超 200px → HARD_SNAP → 弹幕跳位
            item.displayX = item.x;
          }
        }
        if (!kReleaseMode) {
          debugPrint('[PAUSE-RESUME] DRIFT-BEFORE-SYNC: '
              'maxDrift=$_diagResumeMaxDriftBeforePx px '
              'drift>50=$_diagResumeDriftOver50Count '
              'drift>200=$_diagResumeDriftOver200Count '
              'scrollItems=${items.where((i) => i.scrollSpeed > 0.0).length}');
        }
      }

      _lastIsPlaying = isPlaying;
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

    // ── [EDGE-BUG] 边缘裁剪诊断计数器重置 ──
    _diagEdgeNearRightCount = 0;
    _diagEdgeNearLeftCount = 0;
    _diagAtlasDstOutOfBoundsCount = 0;
    _diagEdgeClipRenderedCount = 0;

    // ── [DRIFT-BUG] 漂移校正诊断计数器重置 ──
    _diagDriftCorrectionCount = 0;
    _diagHardSnapCount = 0;
    _diagMaxDrift = 0.0;

    // ── [DIAG-V6] V6.0 四大问题诊断计数器重置 ──
    _diagDrift50to200Count = 0;
    _diagDriftOver200Count = 0;
    _diagDriftUnder50Max = 0;
    _diagSpriteAllocCount = 0;
    _diagRasterCacheMissCount = 0;
    _diagRasterCacheHitCount = 0;
    _diagSlotNewCount = 0;
    _diagSlotHitCount = 0;
    _diagParagraphNewCount = 0;
    _diagEnsureAtlasUs = 0;
    _diagDrawUs = 0;
    _diagUncommittedFallbackCount = 0; // [P1] 未提交fallback计数重置

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
          // [DRIFT-BUG] 漂移诊断：追踪最大漂移和校正频率
          // [TIME-ALIGN] 问题1诊断: 追踪drift分布
          if (absDrift > _diagMaxDrift) _diagMaxDrift = absDrift;
          // ✅ 修复问题2：漂移校正阈值从 50px 降至 15px + 连续渐进校正
          // 根因：playbackTimeMs 低频更新（最长444ms）+ 墙钟高频推进 →
          // playbackTimeMs 冻结期 displayX 推进但 item.x 不变 → drift 累积负方向
          // playbackTimeMs 更新时 item.x 跳变 → drift 瞬间反转正方向 → 弹幕左右微颤
          // 旧阈值 50px 太高，47px 的振荡不被修正 → 视觉可见的回跳
          if (absDrift > 200.0) {
            // 硬snap：drift > 200px（极端异常，seek/循环）
            item.displayX = item.x;
            _diagHardSnapCount++; // [DRIFT-BUG]
            _diagDriftOver200Count++; // [TIME-ALIGN]
            // [DRIFT-DETAIL] 记录 HARD_SNAP 瞬间的 dt 值
            _diagHardSnapDtSeconds = dtSeconds;
            if (rawDtSeconds > 0.020) _diagHardSnapDtAnomalyCount++;
            if (!kReleaseMode) {
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - _lastDiagSnapTimeMs >= 1000) {
                debugPrint('[ATLAS-DIAG] HARD SNAP: drift=${drift.toStringAsFixed(1)}px '
                    'dt=${dtSeconds.toStringAsFixed(4)}s rawDt=${rawDtSeconds.toStringAsFixed(4)}s '
                    'dtAnomaly=$_diagHardSnapDtAnomalyCount');
                _lastDiagSnapTimeMs = now;
              }
            }
          } else if (absDrift > 15.0) {
            // ✅ 渐进校正：drift > 15px（原阈值 50px → 15px）
            // 修正系数随 drift 大小自适应：15px 时 ≈8%，100px 时 ≈30%
            // 公式：correction = 0.05 + 0.25 * (absDrift - 15) / 185
            // 15px → 5%, 50px → 9.7%, 100px → 16.4%, 200px → 30%
            final correctionRate = 0.05 + 0.25 * (absDrift - 15.0) / 185.0;
            item.displayX = item.displayX + (item.x - item.displayX) * correctionRate;
            _diagDriftCorrectionCount++; // [DRIFT-BUG]
            if (absDrift > 50.0) {
              _diagDrift50to200Count++; // [TIME-ALIGN]
            }
          } else if (absDrift > _diagDriftUnder50Max) {
            _diagDriftUnder50Max = absDrift; // [TIME-ALIGN] 追踪轻微漂移峰值
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
      // Bug 5/6 修复: 左侧剔除阈值放宽 12px（描边/阴影最大额外宽度），
      // 防止描边/阴影部分仍可见的弹幕被过早剔除（item.width 不含描边/阴影）。
      // 右侧 drawX > size.width 条件不受影响（弹幕左边缘在画布右侧外）。
      // 光栅化后使用 raster.logicalWidth 进行精确剔除。
      final itemWidth = item.width;
      if (itemWidth > 0.0) {
        if (drawX + itemWidth < -12.0 || drawX > size.width) {
          _diagCulledItems++; // [ATLAS-DIAG-BUG2]
          continue;
        }
      }

      final adjFontSize = fontSize * content.fontSizeMultiplier;
      final itemStrokeColor = _getStrokeColor(textColor: content.color);
      final int colorVal = content.color.toARGB32();
      final int strokeColorVal = itemStrokeColor.toARGB32();

      // ── [P0] 首帧分帧构建: 预算耗尽时跳过构建 ──
      // 预算限制缓存miss总数（Paragraph新构建 + rasterize miss），
      // 缓存命中不消耗预算，确保已缓存弹幕正常渲染。
      if (_frameBuildBudget > 0 &&
          _diagParagraphNewCount + _diagRasterCacheMissCount >= _frameBuildBudget) {
        continue; // 预算耗尽，本帧跳过此弹幕的Paragraph/toImageSync构建
      }

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
      // [MEM-GC] 问题2诊断: 追踪rasterCache hit/miss
      final raster = _getOrRasterize(rasterHash, fillP, strokeP);

      // ── 精灵图集槽位查找/分配 ──
      var slot = _spriteAtlas!.getSlot(rasterHash);
      if (slot != null) {
        _diagSlotHitCount++; // [ATLAS-REBUILD-DETAIL] slot命中计数
      } else {
        // 缓存未命中：分配新槽位
        slot = _spriteAtlas!.addSprite(
          hashKey: rasterHash,
          rasterImage: raster.image,
          logicalW: raster.logicalWidth,
          logicalH: raster.logicalHeight,
        );
        if (slot != null) {
          _diagSlotNewCount++; // [ATLAS-REBUILD-DETAIL] 新增slot计数
        }
      }

      if (slot == null) {
        // 图集空间不足 — 回退到直接 drawImageRect
        _diagAtlasFullItems++; // [ATLAS-DIAG-BUG2]
        _drawFallbackImage(canvas, raster, drawX, drawY, canvasRect,
            content.isMe, size);
        continue;
      }

      // ── [P1] Atlas节流: 未提交slot走fallback渲染 ──
      // Atlas重建被节流(100ms间隔)时，新分配/复用的slot图像尚未写入
      // atlas纹理(committed=false)，直接从atlas采样会得到错误内容。
      // 此时用 _drawFallbackImage 从独立 raster.image 绘制（与 atlas-full 路径一致，
      // 使用 canvas.clipRect 保护，避免 Bug 5/6 Impeller 独立纹理裁剪缺陷）。
      if (!slot.committed) {
        _diagUncommittedFallbackCount++;
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
        // Bug 5/6 修复: 边缘弹幕改用 atlas 共享纹理 + canvas.clipRect 裁剪。
        // 旧方案使用独立 raster.image + 手动 srcRect 裁剪，Impeller 下
        // 该路径渲染为全透明/被丢弃，导致左右边缘 5-10% 非渲染带。
        // 新方案使用与 atlas 主路径相同的纹理和绘制方式，
        // 仅在 drawImageRect 前后加 canvas.clipRect 保护，
        // 确保 Impeller 能正确渲染边缘部分。
        _diagEdgeClipItems++; // [ATLAS-DIAG-BUG2]
        _diagEdgeClipRenderedCount++; // [EDGE-BUG] 边缘裁剪路径计数
        _edgeClipSprites.add(_EdgeClipSprite(
          slot: slot,
          drawX: drawX,
          drawY: drawY,
          dstRect: dstRect,
          clippedDst: clippedDst,
          isMe: content.isMe,
        ));
        // [EDGE-BUG] 详细日志：边缘弹幕的裁剪细节（节流输出）
        if (!kReleaseMode) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastDiagEdgeBugTimeMs >= 1000) {
            _lastDiagEdgeBugTimeMs = now;
            debugPrint('[EDGE-BUG] CLIP: drawX=${drawX.toStringAsFixed(1)} '
                'rasterW=${raster.logicalWidth.toStringAsFixed(1)} '
                'itemW=${item.width.toStringAsFixed(1)} '
                'dstRect=$dstRect clippedDst=$clippedDst '
                'canvasW=${size.width.toStringAsFixed(1)}');
          }
        }
        continue;
      }

      // [EDGE-BUG] 检测：atlas路径弹幕的dstRect是否实际超出画布
      // 理论上 needsEdgeClip=false 意味着 dstRect 完全在画布内，
      // 但由于 float 精度或 item.width vs raster.logicalWidth 差异，
      // atlas 渲染路径的 dstRect 可能实际超出画布边界。
      {
        final atlasDstRight = drawX + raster.logicalWidth;
        final atlasDstLeft = drawX;
        if (atlasDstRight > size.width + 0.01) {
          _diagAtlasDstOutOfBoundsCount++; // [EDGE-BUG] atlas路径越界计数
          _diagEdgeNearRightCount++;
        }
        if (atlasDstLeft < -0.01) {
          _diagAtlasDstOutOfBoundsCount++;
          _diagEdgeNearLeftCount++;
        }
        // [EDGE-BUG] 宽度差异诊断：item.width vs raster.logicalWidth
        if (!kReleaseMode && (raster.logicalWidth - item.width).abs() > 1.0) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastDiagEdgeBugTimeMs >= 2000) {
            _lastDiagEdgeBugTimeMs = now;
            debugPrint('[EDGE-BUG] WIDTH MISMATCH: itemW=${item.width.toStringAsFixed(1)} '
                'rasterW=${raster.logicalWidth.toStringAsFixed(1)} '
                'diff=${(raster.logicalWidth - item.width).toStringAsFixed(1)}px '
                'text="${content.text.substring(0, content.text.length > 10 ? 10 : content.text.length)}"');
          }
        }
      }

      // ── 自发弹幕边框（在 drawRawAtlas 之外绘制） ──
      if (content.isMe) {
        _edgeClipSprites.add(_EdgeClipSprite(
          slot: slot,
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
      _diagSpriteAllocCount++; // [MEM-GC] 问题2诊断: 追踪_SpriteDrawInfo分配数

      _spriteCount++;
    }

    // ── [P0] 首帧分帧构建: 预算更新 ──
    {
      final missCount = _diagParagraphNewCount + _diagRasterCacheMissCount;
      if (missCount == 0) {
        _consecutiveNoMissFrames++;
        if (_consecutiveNoMissFrames >= 3) {
          _frameBuildBudget = 0; // 连续3帧无miss，取消预算限制
        }
      } else {
        _consecutiveNoMissFrames = 0;
        if (_frameBuildBudget > 0 && _frameBuildBudget < 5000) {
          _frameBuildBudget += 150; // 每帧递增预算，加速补全
        }
      }
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

        // [EDGE-BUG] 边缘裁剪诊断输出
        debugPrint('[EDGE-BUG] ATLAS_OOB=$_diagAtlasDstOutOfBoundsCount '
            'NEAR_R=$_diagEdgeNearRightCount NEAR_L=$_diagEdgeNearLeftCount '
            'CLIP_RENDERED=$_diagEdgeClipRenderedCount '
            'CANVAS_W=${size.width.toStringAsFixed(1)}');

        // [DRIFT-BUG] 漂移校正诊断输出
        debugPrint('[DRIFT-BUG] CORRECTIONS=$_diagDriftCorrectionCount '
            'HARD_SNAPS=$_diagHardSnapCount '
            'MAX_DRIFT=${_diagMaxDrift.toStringAsFixed(1)}px '
            'RATE=$playbackRate dt=${dtSeconds.toStringAsFixed(4)}s '
            'lastHardSnapDt=${_diagHardSnapDtSeconds.toStringAsFixed(4)}s '
            'dtAnomaly=$_diagHardSnapDtAnomalyCount');
        _diagHardSnapDtAnomalyCount = 0; // 重置dt异常计数

        // ══════════════════════════════════════════════════════════
        //  [DIAG-V6] V6.0 四大问题诊断输出
        // ══════════════════════════════════════════════════════════

        // [TIME-ALIGN] 问题1: 弹幕时间对齐/回弹 — 双时间源drift分布
        debugPrint('[TIME-ALIGN] PTM_UPDATES=$_diagPlaybackTimeUpdates/2s '
            'PTM_INTERVAL=${_diagPlaybackTimeMinIntervalMs == 0x7FFFFFFF ? "N/A" : "${_diagPlaybackTimeMinIntervalMs}~${_diagPlaybackTimeMaxIntervalMs}ms"} '
            'DRIFT_50_200=$_diagDrift50to200Count DRIFT_200+=$_diagDriftOver200Count '
            'DRIFT_PEAK_UNDER50=${_diagDriftUnder50Max.toStringAsFixed(1)}px');
        // 重置playbackTimeMs诊断计数器
        _diagPlaybackTimeUpdates = 0;
        _diagPlaybackTimeMaxIntervalMs = 0;
        _diagPlaybackTimeMinIntervalMs = 0x7FFFFFFF;
        _diagLastPlaybackTimeMsJump = 0.0;

        // [MEM-GC] 问题2: 内存回收 — GC压力追踪
        // 读取全局atlas重建计数器
        final atlasRebuilds = globalAtlasRebuildCount;
        _diagAtlasRebuildAccum = atlasRebuilds - _diagAtlasRebuildAccum;
        debugPrint('[MEM-GC] SPRITE_ALLOC=$_diagSpriteAllocCount/帧 '
            'RASTER_HIT=$_diagRasterCacheHitCount MISS=$_diagRasterCacheMissCount '
            'RASTER_CACHE_SIZE=${_rasterCache.length}/${_rasterCacheLimit} '
            'PCACHE_SIZE=${_pCache.length}/${_pCacheLimit} '
            'ATLAS_REBUILD=$_diagAtlasRebuildAccum/2s EVICT=$_diagRasterEvictAccum/2s\n'
            '  [ATLAS-DETAIL] SLOT_NEW=$_diagSlotNewCount/帧 SLOT_HIT=$_diagSlotHitCount/帧 '
            'P_NEW=$_diagParagraphNewCount/帧 '
            'ENSURE_ATLAS=${_diagEnsureAtlasUs}μs DRAW=${_diagDrawUs}μs '
            'UNCOMMITTED_FB=$_diagUncommittedFallbackCount/帧 ' // [P1] 节流fallback计数
            'LAST_REBUILD=${globalAtlasLastRebuildUs}μs($globalAtlasLastDirtySource)');

        // [SEEK-PERF] 问题4: 进度条拖拽 — seek性能追踪
        _diagSeekAtlasRebuildCount = atlasRebuilds - _diagSeekAtlasRebuildCount;
        debugPrint('[SEEK-PERF] SLOW_PAINT_FRAMES=$_diagSeekPaintOver2msCount/2s '
            'ATLAS_REBUILD=$_diagSeekAtlasRebuildCount/2s '
            'MAX_PTM_JUMP=${_diagLastPlaybackTimeMsJump.toStringAsFixed(0)}ms\n'
            '  [SEEK-DETAIL] ATLAS_TOTAL_REBUILD_US=${globalAtlasRebuildTotalUs}μs '
            'LAST_REBUILD=${globalAtlasLastRebuildUs}μs($globalAtlasLastDirtySource)');
        _diagSeekPaintOver2msCount = 0;
        _diagSeekAtlasRebuildCount = atlasRebuilds; // 记住当前累计值，下次差分
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  提交渲染
    // ══════════════════════════════════════════════════════════════

    // ── 确保图集纹理可用 ──
    // [ATLAS-REBUILD-DETAIL] ensureAtlas 计时
    final ensureAtlasSw = (kDebugMode && !_diagFirstFrameDone) ? Stopwatch() : null;
    ensureAtlasSw?.start();
    final atlas = _spriteAtlas!.ensureAtlas();
    ensureAtlasSw?.stop();
    if (ensureAtlasSw != null) {
      _diagEnsureAtlasUs = ensureAtlasSw.elapsedMicroseconds;
      _diagFirstFrameEnsureAtlasUs = _diagEnsureAtlasUs;
    }

    // [ATLAS-REBUILD-DETAIL] draw阶段计时
    final diagDrawSw = (kDebugMode && !_diagFirstFrameDone) ? Stopwatch() : null;
    diagDrawSw?.start();

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
    // Bug 5/6 修复: 弃用独立 raster.image + 手动 srcRect 裁剪
    // （Impeller 下该路径渲染为全透明/被丢弃），改用 atlas 共享纹理
    // + canvas.clipRect 保护，与 atlas 主路径一致。GPU 开销仅增加
    // save/restore + clipRect（边缘弹幕通常 2-3 条，压测最多 ~100 条）。
    if (_edgeClipSprites.isNotEmpty && atlas != null) {
      for (final edge in _edgeClipSprites) {
        // 自发弹幕边框
        if (edge.isMe) {
          canvas.drawRect(
            ui.Rect.fromLTWH(edge.drawX - 2, edge.drawY - 2,
                edge.slot.logicalW + 4, edge.slot.logicalH + 4),
            _selfSendPaint,
          );
        }

        // 边缘裁剪 — 用 canvas.clipRect 裁剪 + atlas drawImageRect 绘制
        if (edge.clippedDst != edge.dstRect) {
          canvas.save();
          canvas.clipRect(edge.clippedDst);
          canvas.drawImageRect(
              atlas, edge.slot.srcRect, edge.dstRect, _imagePaint);
          canvas.restore();
        }
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

    // [ATLAS-REBUILD-DETAIL] draw阶段计时结束
    diagDrawSw?.stop();
    if (diagDrawSw != null) {
      _diagDrawUs = diagDrawSw.elapsedMicroseconds;
      _diagFirstFrameDrawUs = _diagDrawUs;
    }

    // [ATLAS-DIAG]
    diagPaintSw?.stop();

    // ── [FIRST-FRAME] 问题3诊断: 首帧paint各阶段耗时汇总 ──
    if (!kReleaseMode && !_diagFirstFrameDone && diagPaintSw != null) {
      _diagFirstFramePaintUs = diagPaintSw.elapsedMicroseconds;
      _diagFirstFrameDone = true;
      debugPrint('[FIRST-FRAME] 首帧paint总耗时: ${_diagFirstFramePaintUs}μs\n'
          '  layout: ${_diagFirstFrameLayoutUs}μs\n'
          '  paragraphBuild(估算): ${_diagFirstFrameParagraphBuildUs}μs\n'
          '  toImageSync累计: ${_diagFirstFrameRasterizeUs}μs\n'
          '  ensureAtlas: ${_diagFirstFrameEnsureAtlasUs}μs\n'
          '  draw: ${_diagFirstFrameDrawUs}μs\n'
          '  rasterCache大小: ${_rasterCache.length}\n'
          '  pCache大小: ${_pCache.length}\n'
          '  atlasSlots: ${_spriteAtlas?.slotCount ?? 0}\n'
          '  slotNew=$_diagSlotNewCount slotHit=$_diagSlotHitCount\n'
          '  pNew=$_diagParagraphNewCount rasterMiss=$_diagRasterCacheMissCount\n'
          '  可见弹幕数: ${items.length} → rendered=$_spriteCount\n' // [P2] 修复: ${items.length} 替代 $items.length
          '  budget=$_frameBuildBudget missUsed=${_diagParagraphNewCount + _diagRasterCacheMissCount}\n'
          '  ═══════════════════════════════════════════════\n'
          '  如果首帧>16ms(60Hz)或>8ms(120Hz)，说明需要:\n'
          '   - 预热缓存（播放前预构建Paragraph+toImageSync）\n'
          '   - 分帧构建（首帧只构建部分弹幕）\n'
          '   - 异步configure（C++轨道分配不在build中同步）');
    }

    // ── [SEEK-PERF] 问题4诊断: 追踪paint耗时>2ms的帧数 ──
    if (!kReleaseMode && diagPaintSw != null) {
      if (diagPaintSw.elapsedMicroseconds > 2000) {
        _diagSeekPaintOver2msCount++;
      }
    }

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

    // Bug 5/6 修复: 弃用手动 srcRect 裁剪（Impeller 下独立纹理 + 部分
    // srcRect 渲染为全透明/被丢弃），改用 canvas.clipRect + 全量
    // drawImageRect，与边缘裁剪路径一致。
    if (clippedDst != dstRect) {
      canvas.save();
      canvas.clipRect(clippedDst);
      canvas.drawImageRect(raster.image,
          ui.Rect.fromLTWH(0, 0,
              raster.image.width.toDouble(),
              raster.image.height.toDouble()),
          dstRect, _imagePaint);
      canvas.restore();
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
      _diagRasterCacheHitCount++; // [MEM-GC] 问题2诊断: rasterCache hit
      return cached; // FIFO: 不重排
    }
    _diagRasterCacheMissCount++; // [MEM-GC] 问题2诊断: rasterCache miss

    // [FIRST-FRAME] 问题3诊断: toImageSync计时
    final diagRasterSw = (kDebugMode && !_diagFirstFrameDone) ? Stopwatch() : null;
    diagRasterSw?.start();

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

    // [FIRST-FRAME] 问题3诊断: 累计toImageSync耗时
    diagRasterSw?.stop();
    if (diagRasterSw != null) {
      _diagFirstFrameRasterizeUs += diagRasterSw.elapsedMicroseconds;
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
      _diagRasterEvictAccum++; // [MEM-GC] 问题2诊断: 淘汰计数
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
    // [ATLAS-REBUILD-DETAIL] Paragraph新构建计数
    _diagParagraphNewCount++;
    final diagParagraphSw = (kDebugMode && !_diagFirstFrameDone) ? Stopwatch() : null;
    diagParagraphSw?.start();

    final p = builder();

    diagParagraphSw?.stop();
    if (diagParagraphSw != null) {
      _diagFirstFrameParagraphBuildUs += diagParagraphSw.elapsedMicroseconds;
    }

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
/// Bug 5/6 修复: 使用 SpriteSlot 替代 _RasterEntry — 边缘弹幕也从
/// atlas 共享纹理绘制（canvas.clipRect 保护），不再使用独立 raster.image
/// （Impeller 下独立纹理 + 部分 srcRect 裁剪渲染为全透明/被丢弃）。
class _EdgeClipSprite {
  final SpriteSlot slot;
  final double drawX;
  final double drawY;
  final ui.Rect dstRect;
  final ui.Rect clippedDst;
  final bool isMe;

  _EdgeClipSprite({
    required this.slot,
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
