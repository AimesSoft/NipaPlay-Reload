import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../interactive/liquid_glass_scope.dart';

/// Edge effect style matching iOS 26's `.scrollEdgeEffectStyle`.
///
/// Controls how scroll content fades at the edges when it meets a glass
/// surface (navigation bar, bottom bar, etc.).
enum GlassScrollEdgeStyle {
  /// A rounded, diffused fade — content dissolves smoothly into the bar area.
  ///
  /// Matches iOS 26's `.soft` edge effect style. This is the default and is
  /// ideal for most list/scroll views with transparent navigation bars.
  soft,

  /// A crisp boundary — content has a sharper cutoff at the bar edge.
  ///
  /// Matches iOS 26's `.hard` edge effect style. Useful when you want a
  /// clear visual separation between the bar and content.
  hard,
}

/// A widget that fades scroll content at the top and/or bottom edges.
///
/// Matches iOS 26's `.scrollEdgeEffectStyle(_:for:)` modifier. Places gradient
/// overlays at the specified edges, creating the effect of content dissolving
/// into navigation bars or bottom bars rather than clipping sharply.
///
/// ## How it works
///
/// **Inside [GlassPage]** (recommended): Automatically captures the page's
/// background texture and paints it over the scroll edges with a gradient
/// alpha mask. This produces a pixel-perfect fade for ANY background —
/// images, patterns, mesh gradients, anything. No configuration needed.
///
/// **Outside [GlassPage]**: Falls back to a solid-colour gradient overlay
/// using [fadeColor] (or the scaffold background colour from the theme).
/// Works perfectly for solid-colour and simple gradient backgrounds.
///
/// ## Why not ShaderMask?
///
/// `ShaderMask(blendMode: BlendMode.dstIn)` creates a `saveLayer` that
/// breaks `BackdropFilterLayer` (premium glass) on Impeller — glass widgets
/// inside it render as opaque black because `BackdropFilterLayer` samples an
/// empty backdrop within the `saveLayer` boundary. This widget avoids that
/// by placing overlays ON TOP of the content rather than wrapping it.
///
/// ## Usage
///
/// ```dart
/// GlassScrollEdgeEffect(
///   topFadeHeight: 100,
///   bottomFadeHeight: 80,
///   child: ListView.builder(
///     itemBuilder: (_, i) => ListTile(title: Text('Item $i')),
///   ),
/// )
/// ```
///
/// ## With GlassAppBar
///
/// ```dart
/// Scaffold(
///   extendBodyBehindAppBar: true,
///   appBar: GlassAppBar(title: Text('Messages')),
///   body: GlassScrollEdgeEffect(
///     topFadeHeight: MediaQuery.paddingOf(context).top + 44 + 50,
///     bottomFadeHeight: 60 + MediaQuery.paddingOf(context).bottom,
///     child: ListView(...),
///   ),
/// )
/// ```
///
/// The [topFadeHeight] should typically cover the safe area + app bar height
/// + a buffer zone so content fades before reaching the navigation buttons.
class GlassScrollEdgeEffect extends StatefulWidget {
  /// Creates a scroll edge effect that fades content at the edges.
  ///
  /// When used inside a [GlassPage] with a background widget, the fade
  /// automatically uses the page's background texture for a pixel-perfect
  /// effect. No [fadeColor] is needed.
  ///
  /// When used outside [GlassPage], provide [fadeColor] to match your
  /// background, or let it default to the scaffold background colour.
  const GlassScrollEdgeEffect({
    super.key,
    required this.child,
    this.topFadeHeight = 100.0,
    this.bottomFadeHeight = 60.0,
    this.fadeTop = true,
    this.fadeBottom = true,
    this.style = GlassScrollEdgeStyle.soft,
    this.fadeColor,
  });

  /// The scrollable content to apply edge fading to.
  final Widget child;

  /// The height of the top fade zone in logical pixels.
  ///
  /// Content within this zone fades from fully transparent (at the top edge)
  /// to fully visible. Should cover the safe area + navigation bar height +
  /// a buffer zone.
  ///
  /// Defaults to 100.0.
  final double topFadeHeight;

  /// The height of the bottom fade zone in logical pixels.
  ///
  /// Content within this zone fades from fully visible to fully transparent
  /// (at the bottom edge). Should cover the bottom bar height + safe area.
  ///
  /// Defaults to 60.0.
  final double bottomFadeHeight;

  /// Whether to fade content at the top edge.
  ///
  /// Defaults to true.
  final bool fadeTop;

  /// Whether to fade content at the bottom edge.
  ///
  /// Defaults to true.
  final bool fadeBottom;

  /// The edge effect style.
  ///
  /// [GlassScrollEdgeStyle.soft] produces a gradual, diffused fade (default).
  /// [GlassScrollEdgeStyle.hard] produces a sharper cutoff.
  ///
  /// Matches iOS 26's `.scrollEdgeEffectStyle(.soft/.hard, for: .top)`.
  final GlassScrollEdgeStyle style;

  /// Fallback colour used when no background texture is available.
  ///
  /// This is only used outside [GlassPage] (i.e. when there is no
  /// [LiquidGlassScope] ancestor providing a background texture).
  ///
  /// When `null`, falls back to the scaffold background colour from the
  /// current theme.
  final Color? fadeColor;

  @override
  State<GlassScrollEdgeEffect> createState() => _GlassScrollEdgeEffectState();
}

class _GlassScrollEdgeEffectState extends State<GlassScrollEdgeEffect> {
  GlobalKey? _backgroundKey;
  ui.Image? _backgroundImage;
  bool _hasAttemptedCapture = false;
  bool _capturePending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backgroundKey = LiquidGlassScope.of(context);

    // Defer capture to after paint. On first mount, toImage() requires a
    // composited OffsetLayer which isn't assigned until paint completes.
    // On subsequent calls (theme toggle, route change), the new background
    // won't paint until end-of-frame either. Both cases need deferral.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captureBackground();
    });
  }

  void _captureBackground() {
    if (_backgroundKey == null) {
      _hasAttemptedCapture = true;
      return;
    }

    final boundary = _backgroundKey!.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;

    if (boundary == null || !boundary.hasSize || boundary.size.isEmpty) {
      // Boundary not ready yet — retry after the first frame.
      if (!_hasAttemptedCapture) {
        _hasAttemptedCapture = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _captureBackground();
        });
      }
      return;
    }

    _hasAttemptedCapture = true;

    // In debug mode, toImageSync asserts if the boundary is marked as needing paint.
    // If it needs paint, wait for the next frame.
    bool needsPaint = false;
    assert(() {
      needsPaint = boundary.debugNeedsPaint;
      return true;
    }());

    if (needsPaint) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _captureBackground();
      });
      return;
    }

    if (_capturePending) return; // Already in-flight — don't stack captures.
    _capturePending = true;
    try {
      boundary.toImage(pixelRatio: 1.0).then((image) {
        _capturePending = false;
        if (!mounted) {
          image.dispose();
          return;
        }
        _backgroundImage?.dispose();
        _backgroundImage = image;
        setState(() {});
      }).catchError((_) {
        _capturePending = false;
      });
    } on Object {
      // toImage() can throw synchronously if `layer` is still null
      // (paint has not completed). Reset the flag and fall back to
      // the solid-colour gradient overlay.
      _capturePending = false;
    }
  }

  @override
  void dispose() {
    _backgroundImage?.dispose();
    _backgroundImage = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No fading needed — return child directly.
    if (!widget.fadeTop && !widget.fadeBottom) return widget.child;

    final screenSize = MediaQuery.sizeOf(context);
    final hasTexture = _backgroundImage != null;

    return Stack(
      children: [
        // 1. Scroll content — no compositing layer wrapping it.
        widget.child,

        // 2. Top fade overlay.
        if (widget.fadeTop)
          _buildOverlay(
            isTop: true,
            height: _effectiveHeight(widget.topFadeHeight, screenSize.height),
            screenSize: screenSize,
            hasTexture: hasTexture,
          ),

        // 3. Bottom fade overlay.
        if (widget.fadeBottom)
          _buildOverlay(
            isTop: false,
            height:
                _effectiveHeight(widget.bottomFadeHeight, screenSize.height),
            screenSize: screenSize,
            hasTexture: hasTexture,
          ),
      ],
    );
  }

  Widget _buildOverlay({
    required bool isTop,
    required double height,
    required Size screenSize,
    required bool hasTexture,
  }) {
    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: hasTexture
            ? CustomPaint(
                size: Size(screenSize.width, height),
                painter: _TextureFadePainter(
                  image: _backgroundImage!,
                  isTop: isTop,
                  screenHeight: screenSize.height,
                  style: widget.style,
                ),
              )
            : _buildColorOverlay(isTop: isTop),
      ),
    );
  }

  /// Fallback: solid-colour gradient overlay for use outside [GlassPage].
  Widget _buildColorOverlay({required bool isTop}) {
    final color =
        widget.fadeColor ?? CupertinoTheme.of(context).scaffoldBackgroundColor;
    final curve = _kFadeCurves[widget.style]!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
          end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
          colors: curve.alphas
              .map((a) => color.withValues(alpha: color.a * a))
              .toList(),
          stops: curve.stops,
        ),
      ),
    );
  }

  double _effectiveHeight(double height, double boundsHeight) {
    // Hard style uses a tighter transition zone (half of soft) combined with
    // a steeper gradient curve — so it's a different *shape*, not just a
    // compressed version of soft.
    final adjusted =
        widget.style == GlassScrollEdgeStyle.hard ? height * 0.5 : height;
    // Clamp to 40% of available height to avoid overlapping zones.
    return adjusted.clamp(0.0, boundsHeight * 0.4);
  }
}

/// Pre-computed gradient curves for each [GlassScrollEdgeStyle].
///
/// Each curve defines the alpha values and corresponding stops for a
/// multi-stop gradient that produces a perceptually smooth fade. A simple
/// 2-stop linear ramp (the previous implementation) appears non-uniform to
/// the human eye — denser in the middle — and terminates with a visible seam.
///
/// These curves are modelled after iOS 26's scroll edge effect:
/// - **Soft**: gentle ease-in dissolve with a long transparent tail, producing
///   a diffused fade that dissolves content smoothly into the bar area.
/// - **Hard**: holds opacity longer then drops sharply, but still includes a
///   feathered tail to avoid the hard cutoff seam.
class _FadeCurve {
  const _FadeCurve(this.alphas, this.stops);

  /// Alpha multipliers from edge (1.0 = fully opaque) to content (0.0).
  final List<double> alphas;

  /// Corresponding gradient stop positions in [0, 1].
  final List<double> stops;
}

const Map<GlassScrollEdgeStyle, _FadeCurve> _kFadeCurves = {
  // Soft: gentle ease-in dissolve. Holds opacity briefly at the edge, then
  // accelerates through the mid-range, and includes a long low-alpha tail
  // that reaches fully transparent well before the overlay boundary —
  // eliminating the visible seam.
  GlassScrollEdgeStyle.soft: _FadeCurve(
    [1.0, 0.70, 0.30, 0.04, 0.0],
    [0.0, 0.15, 0.45, 0.75, 0.92],
  ),
  // Hard: crisp but feathered. Stays opaque for longer (the "hard" feel),
  // then drops more steeply, but still includes a tail to prevent seaming.
  // Combined with the 0.5× height multiplier in _effectiveHeight, this
  // produces a noticeably crisper boundary than soft without a sharp line.
  GlassScrollEdgeStyle.hard: _FadeCurve(
    [1.0, 0.90, 0.50, 0.04, 0.0],
    [0.0, 0.30, 0.60, 0.85, 0.95],
  ),
};

/// Paints a slice of the background texture with a gradient alpha mask.
///
/// This is the core of the texture overlay approach: it takes the background
/// image captured by [GlassBackgroundSource], extracts the top or bottom
/// strip, and paints it with a gradient from fully opaque (at the edge) to
/// fully transparent (towards the content). Visually, this is identical to
/// fading the content to transparent and revealing the background.
///
/// Uses [BlendMode.dstIn] inside a [Canvas.saveLayer] to apply the gradient
/// mask. Since this painter only draws a static image (no [BackdropFilterLayer]),
/// the `saveLayer` is safe and does not interfere with glass rendering.
class _TextureFadePainter extends CustomPainter {
  _TextureFadePainter({
    required this.image,
    required this.isTop,
    required this.screenHeight,
    required this.style,
  });

  final ui.Image image;
  final bool isTop;
  final double screenHeight;
  final GlassScrollEdgeStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // The image is captured at pixelRatio: 1.0, so its pixel dimensions
    // match logical dimensions. Calculate the source strip from the
    // corresponding edge of the background.
    final double scaleY = image.height / screenHeight;

    final Rect srcRect = isTop
        ? Rect.fromLTWH(0, 0, image.width.toDouble(), size.height * scaleY)
        : Rect.fromLTWH(
            0,
            image.height - size.height * scaleY,
            image.width.toDouble(),
            size.height * scaleY,
          );

    final Rect dstRect = Offset.zero & size;

    // Paint the background strip with gradient alpha.
    // saveLayer is safe here — no BackdropFilterLayer inside.
    canvas.saveLayer(dstRect, Paint());

    // Draw the background texture slice.
    canvas.drawImageRect(image, srcRect, dstRect, Paint());

    // Apply gradient alpha mask: opaque at the edge, transparent towards
    // the content. Uses a multi-stop eased gradient to produce a
    // perceptually smooth fade without a visible seam at the boundary.
    final curve = _kFadeCurves[style]!;
    final gradientPaint = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = LinearGradient(
        begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
        end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
        colors: curve.alphas
            .map((a) => Color.fromARGB((a * 255).round(), 0, 0, 0))
            .toList(),
        stops: curve.stops,
      ).createShader(dstRect);

    canvas.drawRect(dstRect, gradientPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TextureFadePainter oldDelegate) =>
      image != oldDelegate.image ||
      isTop != oldDelegate.isTop ||
      screenHeight != oldDelegate.screenHeight ||
      style != oldDelegate.style;
}
