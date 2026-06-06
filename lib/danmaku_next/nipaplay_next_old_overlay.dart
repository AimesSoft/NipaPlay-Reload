// ════════════════════════════════════════════════════════════════════
//  Next Old Overlay — c4ceacbd 版 playbackTimeMs 驱动重绘
//
//  与 NipaPlayNextOverlay 的区别：
//  - playbackTimeMs 驱动重绘（8-30Hz），无 vsync AnimationController
//  - 始终使用 Opacity widget 包裹（不做 opacity bypass）
//  - 无 Emoji fontFamilyFallback 添加
//  - 使用 NipaPlayNextOldEngine（纯Dart布局）+ NipaPlayNextOldCanvasPainter
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_old_canvas_painter.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_old_engine.dart';
import 'package:nipaplay/danmaku_next/danmaku_next_log.dart';
import 'package:nipaplay/utils/video_player_state.dart';

const Locale _danmakuOldLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hans',
  countryCode: 'CN',
);

class NipaPlayNextOldOverlay extends StatefulWidget {
  final List<Map<String, dynamic>> danmakuList;
  final ValueListenable<double> playbackTimeMs;
  final double currentTimeSeconds;
  final double fontSize;
  final bool isVisible;
  final double opacity;
  final double displayArea;
  final double timeOffset;
  final double scrollDurationSeconds;
  final bool allowStacking;
  final bool mergeDanmaku;
  final String customFontFamily;
  final DanmakuOutlineStyle outlineStyle;
  final DanmakuShadowStyle shadowStyle;
  final ValueChanged<List<PositionedDanmakuItem>>? onLayoutCalculated;
  final bool isPlaying;

  const NipaPlayNextOldOverlay({
    super.key,
    required this.danmakuList,
    required this.playbackTimeMs,
    required this.currentTimeSeconds,
    required this.fontSize,
    required this.isVisible,
    required this.opacity,
    required this.displayArea,
    required this.timeOffset,
    required this.scrollDurationSeconds,
    required this.allowStacking,
    required this.mergeDanmaku,
    required this.customFontFamily,
    required this.outlineStyle,
    required this.shadowStyle,
    this.onLayoutCalculated,
    required this.isPlaying,
  });

  @override
  State<NipaPlayNextOldOverlay> createState() => _NipaPlayNextOldOverlayState();
}

class _NipaPlayNextOldOverlayState extends State<NipaPlayNextOldOverlay> {
  final NipaPlayNextOldEngine _engine = NipaPlayNextOldEngine();
  int _listIdentity = 0;
  Size _lastConfiguredSize = Size.zero;
  bool _layoutSnapshotPending = false;

  /// playbackTimeMs 变化时触发 painter 重绘
  final ValueNotifier<int> _repaintNotifier = ValueNotifier(0);

  /// 最近一次 layout 结果
  List<PositionedDanmakuItem> _lastItems = const [];

  @override
  void initState() {
    super.initState();
    _listIdentity = identityHashCode(widget.danmakuList);
    _layoutSnapshotPending = true;

    // 监听 playbackTimeMs 变化 → 重新 layout + 通知 painter 重绘
    widget.playbackTimeMs.addListener(_onPlaybackTimeChanged);

    DanmakuNextLog.d(
      'OldOverlay',
      'init list=${widget.danmakuList.length} font=${widget.fontSize} visible=${widget.isVisible}',
      throttle: Duration.zero,
    );
  }

  @override
  void didUpdateWidget(covariant NipaPlayNextOldOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.fontSize != widget.fontSize) {
      DanmakuNextLog.d(
        'OldOverlay',
        'font size changed ${oldWidget.fontSize} -> ${widget.fontSize}',
        throttle: Duration.zero,
      );
    }

    final listIdentity = identityHashCode(widget.danmakuList);
    if (listIdentity != _listIdentity) {
      _listIdentity = listIdentity;
      _layoutSnapshotPending = true;
      DanmakuNextLog.d(
        'OldOverlay',
        'danmaku list changed size=${widget.danmakuList.length}',
        throttle: Duration.zero,
      );
    }

    // playbackTimeMs listenable 切换
    if (oldWidget.playbackTimeMs != widget.playbackTimeMs) {
      oldWidget.playbackTimeMs.removeListener(_onPlaybackTimeChanged);
      widget.playbackTimeMs.addListener(_onPlaybackTimeChanged);
    }
  }

  void _onPlaybackTimeChanged() {
    if (!mounted || !widget.isVisible) return;
    _doLayout();
  }

  void _doLayout() {
    final timeSeconds = widget.playbackTimeMs.value / 1000.0 + widget.timeOffset;
    _lastItems = _engine.layout(timeSeconds);
    _repaintNotifier.value++; // 触发 painter 重绘
  }

  @override
  void dispose() {
    widget.playbackTimeMs.removeListener(_onPlaybackTimeChanged);
    _repaintNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      DanmakuNextLog.d(
        'OldOverlay',
        'hidden, skip build',
        throttle: const Duration(seconds: 2),
      );
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = DefaultTextStyle.of(context).style;
        final theme = Theme.of(context);
        final themeFontFamily = theme.textTheme.bodyMedium?.fontFamily ??
            theme.textTheme.bodyLarge?.fontFamily;
        final customFontFamily = widget.customFontFamily.trim();
        final fontFamily = customFontFamily.isNotEmpty
            ? customFontFamily
            : (textStyle.fontFamily ?? themeFontFamily);
        // 旧版不添加 Emoji fontFamilyFallback — TextPainter 自然支持 Emoji 渲染

        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.isEmpty) {
          return const SizedBox.expand();
        }

        final previousSize = _lastConfiguredSize;
        _lastConfiguredSize = size;

        _engine.configure(
          danmakuList: widget.danmakuList,
          size: size,
          fontSize: widget.fontSize,
          displayArea: widget.displayArea,
          scrollDurationSeconds: widget.scrollDurationSeconds,
          allowStacking: widget.allowStacking,
          mergeDanmaku: widget.mergeDanmaku,
          fontFamily: fontFamily,
          fontFamilyFallback: textStyle.fontFamilyFallback,
          locale: _danmakuOldLocale,
        );

        // 首次配置或尺寸变化时，执行一次 layout
        if (_layoutSnapshotPending || previousSize != size || _lastItems.isEmpty) {
          _doLayout();
        }

        if (widget.onLayoutCalculated != null &&
            (_layoutSnapshotPending || previousSize != size)) {
          final snapshot = List<PositionedDanmakuItem>.from(_lastItems);
          _layoutSnapshotPending = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onLayoutCalculated?.call(snapshot);
          });
        }

        // ── 旧版始终使用 Opacity widget 包裹 ──
        // 不做 opacity bypass（c4ceacbd 原始行为）
        final effectiveOpacity = widget.opacity.clamp(0.0, 1.0);
        return Opacity(
          opacity: effectiveOpacity,
          child: CustomPaint(
            painter: NipaPlayNextOldCanvasPainter(
              repaintNotifier: _repaintNotifier,
              engine: _engine,
              items: _lastItems,
              fontSize: widget.fontSize,
              fontFamily: fontFamily,
              fontFamilyFallback: textStyle.fontFamilyFallback,
              locale: _danmakuOldLocale,
              outlineStyle: widget.outlineStyle,
              shadowStyle: widget.shadowStyle,
            ),
            size: size,
          ),
        );
      },
    );
  }
}
