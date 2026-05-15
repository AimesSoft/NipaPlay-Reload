import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_canvas_painter.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_engine.dart';
import 'package:nipaplay/danmaku_next/danmaku_next_log.dart';
import 'package:nipaplay/utils/video_player_state.dart';

const Locale _danmakuLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hans',
  countryCode: 'CN',
);

class NipaPlayNextOverlay extends StatefulWidget {
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

  const NipaPlayNextOverlay({
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
  });

  @override
  State<NipaPlayNextOverlay> createState() => _NipaPlayNextOverlayState();
}

class _NipaPlayNextOverlayState extends State<NipaPlayNextOverlay> {
  final NipaPlayNextEngine _engine = NipaPlayNextEngine();
  int _listIdentity = 0;
  Size _lastConfiguredSize = Size.zero;
  bool _layoutSnapshotPending = false;

  @override
  void initState() {
    super.initState();
    _listIdentity = identityHashCode(widget.danmakuList);
    _layoutSnapshotPending = true;
    DanmakuNextLog.d(
      'Overlay',
      'init list=${widget.danmakuList.length} font=${widget.fontSize} visible=${widget.isVisible}',
      throttle: Duration.zero,
    );
  }

  @override
  void didUpdateWidget(covariant NipaPlayNextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.fontSize != widget.fontSize) {
      DanmakuNextLog.d(
        'Overlay',
        'font size changed ${oldWidget.fontSize} -> ${widget.fontSize}',
        throttle: Duration.zero,
      );
    }

    final listIdentity = identityHashCode(widget.danmakuList);
    if (listIdentity != _listIdentity) {
      _listIdentity = listIdentity;
      _layoutSnapshotPending = true;
      DanmakuNextLog.d(
        'Overlay',
        'danmaku list changed size=${widget.danmakuList.length}',
        throttle: Duration.zero,
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      DanmakuNextLog.d(
        'Overlay',
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
        final fontFamilyFallback = textStyle.fontFamilyFallback;

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
          fontFamilyFallback: fontFamilyFallback,
          locale: _danmakuLocale,
        );

        if (widget.onLayoutCalculated != null &&
            (_layoutSnapshotPending || previousSize != size)) {
          final snapshot = List<PositionedDanmakuItem>.from(
            _engine.layout(widget.currentTimeSeconds + widget.timeOffset),
          );
          _layoutSnapshotPending = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onLayoutCalculated?.call(snapshot);
          });
        }

        return Opacity(
          opacity: widget.opacity.clamp(0.0, 1.0),
          child: CustomPaint(
            painter: NipaPlayNextCanvasPainter(
              engine: _engine,
              playbackTimeMs: widget.playbackTimeMs,
              timeOffsetSeconds: widget.timeOffset,
              fontSize: widget.fontSize,
              fontFamily: fontFamily,
              fontFamilyFallback: fontFamilyFallback,
              locale: _danmakuLocale,
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
