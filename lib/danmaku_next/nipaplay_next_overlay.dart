import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_gpu/lib/dynamic_font_atlas.dart';
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_config.dart';
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_overlay.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_engine.dart';
import 'package:nipaplay/danmaku_next/danmaku_next_log.dart';

class NipaPlayNextOverlay extends StatefulWidget {
  final List<Map<String, dynamic>> danmakuList;
  final double currentTimeSeconds;
  final double fontSize;
  final bool isVisible;
  final double opacity;
  final double displayArea;
  final double timeOffset;
  final double scrollDurationSeconds;
  final bool allowStacking;
  final ValueChanged<List<PositionedDanmakuItem>>? onLayoutCalculated;

  const NipaPlayNextOverlay({
    super.key,
    required this.danmakuList,
    required this.currentTimeSeconds,
    required this.fontSize,
    required this.isVisible,
    required this.opacity,
    required this.displayArea,
    required this.timeOffset,
    required this.scrollDurationSeconds,
    required this.allowStacking,
    this.onLayoutCalculated,
  });

  @override
  State<NipaPlayNextOverlay> createState() => _NipaPlayNextOverlayState();
}

class _NipaPlayNextOverlayState extends State<NipaPlayNextOverlay> {
  final NipaPlayNextEngine _engine = NipaPlayNextEngine();
  int _listIdentity = 0;

  @override
  void initState() {
    super.initState();
    _listIdentity = identityHashCode(widget.danmakuList);
    DanmakuNextLog.d(
      'Overlay',
      'init list=${widget.danmakuList.length} font=${widget.fontSize} visible=${widget.isVisible}',
      throttle: Duration.zero,
    );
    _prebuildAtlas();
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
      _prebuildAtlas();
    }

    final listIdentity = identityHashCode(widget.danmakuList);
    if (listIdentity != _listIdentity) {
      _listIdentity = listIdentity;
      DanmakuNextLog.d(
        'Overlay',
        'danmaku list changed size=${widget.danmakuList.length}',
        throttle: Duration.zero,
      );
      _prebuildAtlas();
    }
  }

  void _prebuildAtlas() {
    const int maxPrebuildChars = 320;
    const int maxPrebuildTexts = 200;

    final Set<String> chars = <String>{};
    int textCount = 0;
    for (final danmaku in widget.danmakuList) {
      final text = danmaku['content']?.toString() ?? '';
      if (text.isEmpty) continue;
      textCount++;
      for (final rune in text.runes) {
        chars.add(String.fromCharCode(rune));
        if (chars.length >= maxPrebuildChars) break;
      }
      if (chars.length >= maxPrebuildChars || textCount >= maxPrebuildTexts) {
        break;
      }
    }

    if (chars.isEmpty) return;

    final seedText = chars.join();
    if (seedText.length < chars.length) {
      DanmakuNextLog.d(
        'Overlay',
        'prebuild chars=${chars.length} (deduped)',
        throttle: Duration.zero,
      );
    } else {
      DanmakuNextLog.d(
        'Overlay',
        'prebuild chars=${chars.length}',
        throttle: Duration.zero,
      );
    }

    FontAtlasManager.prebuildFromTexts(
      fontSize: widget.fontSize,
      texts: [seedText],
    ).then((_) {
      if (mounted) setState(() {});
    });
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
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.isEmpty) {
          return const SizedBox.expand();
        }

        _engine.configure(
          danmakuList: widget.danmakuList,
          size: size,
          fontSize: widget.fontSize,
          displayArea: widget.displayArea,
          scrollDurationSeconds: widget.scrollDurationSeconds,
          allowStacking: widget.allowStacking,
        );

        final effectiveTime = widget.currentTimeSeconds + widget.timeOffset;
        final positioned = _engine.layout(effectiveTime);

        DanmakuNextLog.d(
          'Overlay',
          'build size=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)} '
          'time=${effectiveTime.toStringAsFixed(2)} items=${positioned.length}',
          throttle: const Duration(seconds: 1),
        );

        if (widget.onLayoutCalculated != null) {
          final snapshot = positioned;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onLayoutCalculated?.call(snapshot);
          });
        }

        final config = GPUDanmakuConfig(
          fontSize: widget.fontSize,
          screenUsageRatio: widget.displayArea,
          scrollScreensPerSecond: widget.scrollDurationSeconds > 0
              ? (1.0 / widget.scrollDurationSeconds)
              : 0.1,
        );

        return GPUDanmakuOverlay(
          positionedDanmaku: positioned,
          isPlaying: true,
          config: config,
          isVisible: widget.isVisible,
          opacity: widget.opacity,
          currentTime: effectiveTime,
        );
      },
    );
  }
}
