import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import 'next2_layout_bridge.dart';
import 'next2_texture_bridge.dart';

const Locale _danmakuLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hans',
  countryCode: 'CN',
);

class NipaPlayNext2Overlay extends StatefulWidget {
  const NipaPlayNext2Overlay({
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
    required this.outlineWidth,
    required this.shadowStyle,
    this.onLayoutCalculated,
  });

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
  final double outlineWidth;
  final DanmakuShadowStyle shadowStyle;
  final ValueChanged<List<PositionedDanmakuItem>>? onLayoutCalculated;

  @override
  State<NipaPlayNext2Overlay> createState() => _NipaPlayNext2OverlayState();
}

class _NipaPlayNext2OverlayState extends State<NipaPlayNext2Overlay> {
  final Next2LayoutBridge _bridge = Next2LayoutBridge();
  final Next2TextureBridge _textureBridge = Next2TextureBridge();

  Size _layoutSize = Size.zero;
  List<PositionedDanmakuItem> _frameItems = const [];
  String? _fontFamily;
  List<String>? _fontFamilyFallback;

  bool _updateScheduled = false;
  bool _updateInFlight = false;
  bool _updateQueued = false;

  int? _textureId;
  bool _textureReady = false;
  String _surfaceId = 'next2-default';
  double _lastDevicePixelRatio = 1.0;

  @override
  void initState() {
    super.initState();
    _surfaceId = 'next2-${identityHashCode(this)}';
  }

  @override
  void dispose() {
    _textureBridge.disposeSurface(_surfaceId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.isEmpty) {
          return const SizedBox.expand();
        }

        final textStyle = DefaultTextStyle.of(context).style;
        final theme = Theme.of(context);
        final themeFontFamily = theme.textTheme.bodyMedium?.fontFamily ??
            theme.textTheme.bodyLarge?.fontFamily;
        final customFontFamily = widget.customFontFamily.trim();
        _fontFamily = customFontFamily.isNotEmpty
            ? customFontFamily
            : (textStyle.fontFamily ?? themeFontFamily);
        _fontFamilyFallback = textStyle.fontFamilyFallback;

        if (_layoutSize != size) {
          _layoutSize = size;
          _queueUpdate();
        }

        final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ??
            View.of(context).devicePixelRatio;
        if ((_lastDevicePixelRatio - dpr).abs() > 0.001) {
          _lastDevicePixelRatio = dpr;
          _queueUpdate();
        }

        return ValueListenableBuilder<double>(
          valueListenable: widget.playbackTimeMs,
          builder: (context, _, __) {
            _queueUpdate();

            Widget content;
            if (_textureReady &&
                _textureId != null &&
                Next2TextureBridge.isSupported) {
              content = Texture(
                textureId: _textureId!,
                filterQuality: FilterQuality.none,
              );
            } else {
              content = CustomPaint(
                painter: _Next2CanvasPainter(
                  items: _frameItems,
                  fontSize: widget.fontSize,
                  fontFamily: _fontFamily,
                  fontFamilyFallback: _fontFamilyFallback,
                  outlineWidth: widget.outlineWidth.clamp(0.0, 4.0).toDouble(),
                  shadowStyle: widget.shadowStyle,
                ),
                size: _layoutSize,
              );
            }

            return Opacity(
              opacity: widget.opacity.clamp(0.0, 1.0).toDouble(),
              child: SizedBox.expand(child: content),
            );
          },
        );
      },
    );
  }

  void _queueUpdate() {
    _updateQueued = true;
    if (_updateScheduled || _updateInFlight) {
      return;
    }
    _updateScheduled = true;
    Future.microtask(_runUpdateLoop);
  }

  Future<void> _runUpdateLoop() async {
    _updateScheduled = false;
    if (_updateInFlight) {
      return;
    }

    _updateInFlight = true;
    try {
      while (mounted && _updateQueued) {
        _updateQueued = false;

        if (_layoutSize.isEmpty) {
          continue;
        }

        await _bridge.configure(
          danmakuList: widget.danmakuList,
          size: _layoutSize,
          fontSize: widget.fontSize,
          displayArea: widget.displayArea,
          scrollDurationSeconds: widget.scrollDurationSeconds,
          allowStacking: widget.allowStacking,
          mergeDanmaku: widget.mergeDanmaku,
        );

        final frame = await _bridge.layout(
          widget.playbackTimeMs.value / 1000.0 + widget.timeOffset,
        );

        final renderedByTexture = await _tryUpdateTexture(frame);

        if (!mounted) {
          return;
        }

        if (!renderedByTexture) {
          setState(() {
            _frameItems = frame;
          });
        }
        widget.onLayoutCalculated?.call(frame);
      }
    } catch (_) {
      // Keep overlay alive and allow fallback on next frame.
    } finally {
      _updateInFlight = false;
    }
  }

  Future<bool> _tryUpdateTexture(List<PositionedDanmakuItem> frame) async {
    if (!Next2TextureBridge.isSupported || _layoutSize.isEmpty) {
      return false;
    }

    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr =
        views.isNotEmpty ? views.first.devicePixelRatio : _lastDevicePixelRatio;
    final double pixelRatio =
        dpr.isFinite ? dpr.clamp(1.0, 4.0).toDouble() : 1.0;
    final int pixelWidth =
        (_layoutSize.width * pixelRatio).round().clamp(1, 16384).toInt();
    final int pixelHeight =
        (_layoutSize.height * pixelRatio).round().clamp(1, 16384).toInt();

    final info = await _textureBridge.ensureTexture(
      surfaceId: _surfaceId,
      width: pixelWidth,
      height: pixelHeight,
    );

    if (info == null) {
      return false;
    }

    if (!mounted) {
      return false;
    }

    if (_textureId != info.textureId || !_textureReady) {
      setState(() {
        _textureId = info.textureId;
        _textureReady = true;
      });
    }

    if (info.isNewEngine) {
      await _textureBridge.resetScene();
    }

    final widthScale = info.width > 0 ? info.width / _layoutSize.width : 1.0;
    final heightScale =
        info.height > 0 ? info.height / _layoutSize.height : 1.0;
    final fontScale =
        ((widthScale + heightScale) * 0.5).clamp(0.25, 8.0).toDouble();

    final pushed = await _textureBridge.setFrame(
      items: frame,
      fontSize: widget.fontSize,
      outlineWidth: widget.outlineWidth,
      shadowStyle: widget.shadowStyle,
      // Overall opacity is applied by the outer Flutter Opacity widget.
      // Keep Rust-side glyph compositing at full alpha to avoid edge fringe.
      opacity: 1.0,
      scaleX: widthScale,
      scaleY: heightScale,
      fontScale: fontScale,
    );

    return pushed;
  }
}

class _Next2CanvasPainter extends CustomPainter {
  _Next2CanvasPainter({
    required this.items,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.outlineWidth,
    required this.shadowStyle,
  });

  final List<PositionedDanmakuItem> items;
  final double fontSize;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final double outlineWidth;
  final DanmakuShadowStyle shadowStyle;

  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;

    for (final item in items) {
      final content = item.content;
      final targetFontSize = fontSize * content.fontSizeMultiplier;
      final shadowConfig = _resolveShadowStyle(targetFontSize);
      final text = content.countText == null
          ? content.text
          : '${content.text} ${content.countText}';

      if (shadowConfig != null) {
        _paintText(
          canvas,
          text: text,
          offset: Offset(item.x, item.y) + shadowConfig.offset,
          fontSize: targetFontSize,
          color: Color.fromRGBO(0, 0, 0, shadowConfig.opacity),
        );
      }

      final outlineColor = _strokeColorFor(content.color);
      final outlineRadius = _resolveStrokeWidth(targetFontSize);

      if (outlineWidth > 0) {
        _paintOutline(
          canvas,
          text: text,
          baseOffset: Offset(item.x, item.y),
          fontSize: targetFontSize,
          color: outlineColor,
          radius: outlineRadius * outlineWidth,
          fullRing: true,
        );
      }

      _paintText(
        canvas,
        text: text,
        offset: Offset(item.x, item.y),
        fontSize: targetFontSize,
        color: content.color,
      );

      if (content.isMe) {
        final tp = _buildPainter(
          text: text,
          fontSize: targetFontSize,
          color: content.color,
        );
        final rect = Rect.fromLTWH(
          item.x - 2,
          item.y - 2,
          tp.width + 4,
          tp.height + 4,
        );
        canvas.drawRect(rect, _selfSendPaint);
      }
    }
  }

  void _paintText(
    Canvas canvas, {
    required String text,
    required Offset offset,
    required double fontSize,
    required Color color,
  }) {
    final tp = _buildPainter(
      text: text,
      fontSize: fontSize,
      color: color,
    );
    tp.paint(canvas, offset);
  }

  TextPainter _buildPainter({
    required String text,
    required double fontSize,
    required Color color,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.normal,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
      ),
      textDirection: TextDirection.ltr,
      locale: _danmakuLocale,
    )..layout(minWidth: 0, maxWidth: double.infinity);
  }

  void _paintOutline(
    Canvas canvas, {
    required String text,
    required Offset baseOffset,
    required double fontSize,
    required Color color,
    required double radius,
    required bool fullRing,
  }) {
    final offsets = <Offset>[];

    if (fullRing) {
      for (int i = 0; i < 8; i++) {
        final angle = (math.pi * 2 / 8) * i;
        offsets.add(Offset(math.cos(angle) * radius, math.sin(angle) * radius));
      }
    } else {
      offsets.addAll(<Offset>[
        Offset(-radius, 0),
        Offset(radius, 0),
        Offset(0, -radius),
        Offset(0, radius),
      ]);
    }

    for (final delta in offsets) {
      _paintText(
        canvas,
        text: text,
        offset: baseOffset + delta,
        fontSize: fontSize,
        color: color,
      );
    }
  }

  Color _strokeColorFor(Color textColor) {
    final luminance = textColor.computeLuminance();
    return luminance < 0.45 ? Colors.white : Colors.black;
  }

  _ShadowConfig? _resolveShadowStyle(double targetFontSize) {
    final unit = _resolveShadowUnit(targetFontSize);
    switch (shadowStyle) {
      case DanmakuShadowStyle.none:
        return null;
      case DanmakuShadowStyle.soft:
        return _ShadowConfig(
          offset: Offset(unit * 0.8, unit * 0.8),
          opacity: 0.34,
        );
      case DanmakuShadowStyle.medium:
        return _ShadowConfig(
          offset: Offset(unit, unit),
          opacity: 0.44,
        );
      case DanmakuShadowStyle.strong:
        return _ShadowConfig(
          offset: Offset(unit * 1.2, unit * 1.2),
          opacity: 0.55,
        );
    }
  }

  double _resolveStrokeWidth(double targetFontSize) {
    final width = targetFontSize * 0.06;
    return width.clamp(1.0, 2.6).toDouble();
  }

  double _resolveShadowUnit(double targetFontSize) {
    final radius = targetFontSize * 0.045;
    return math.max(0.8, radius.clamp(0.8, 2.0).toDouble());
  }

  @override
  bool shouldRepaint(covariant _Next2CanvasPainter oldDelegate) {
    return !listEquals(oldDelegate.items, items) ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.fontFamily != fontFamily ||
        !listEquals(oldDelegate.fontFamilyFallback, fontFamilyFallback) ||
        oldDelegate.outlineWidth != outlineWidth ||
        oldDelegate.shadowStyle != shadowStyle;
  }
}

class _ShadowConfig {
  const _ShadowConfig({required this.offset, required this.opacity});

  final Offset offset;
  final double opacity;
}
