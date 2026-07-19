import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';
import '../../utils/glass_spring.dart';

/// {@template glass_glow}
/// If placed as a descendant of a [GlassGlowLayer], this widget will
/// send touch updates to that layer to create a glow effect.
/// {@endtemplate}
class GlassGlow extends StatefulWidget {
  /// {@macro glass_glow}
  const GlassGlow({
    required this.child,
    this.glowColor = Colors.white24,
    this.glowRadius = 1,
    this.glowBlurRadius = 0,
    this.glowSpreadRadius = 0,
    this.glowOpacity = 1,
    this.pulse = 0,
    this.clipper,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.enabled = true,
    this.glowOnTapOnly = false,
    super.key,
  });

  /// The radius of the glow effect relative to the layer's shortest side.
  ///
  /// A value of 0.8 means the glow radius will be 80% of the shortest
  /// dimension (width or height) of the [GlassGlowLayer].
  ///
  /// Defaults to 1.
  final double glowRadius;

  /// The color of the glow effect.
  ///
  /// The glow will have this colors opacity at the center, and will fade out
  /// to fully transparent at the edge of the glow.
  final Color glowColor;

  /// Additional blur sigma applied to the glow circle via a [MaskFilter].
  ///
  /// A value of 0 (the default) produces a sharp-edged radial gradient with no
  /// additional blur. Higher values soften the glow, creating a wider diffuse
  /// halo. The blur is applied *on top of* the radial gradient fade-out, so
  /// even moderate values (4–12) are clearly visible.
  ///
  /// Corresponds to [GlassGlowColors.glowBlurRadius].
  final double glowBlurRadius;

  /// Extra radius added to the drawn circle beyond the physics radius.
  ///
  /// A value of 0 (the default) draws the circle at the physics radius. A
  /// positive value (e.g. 0.2) expands it by that fraction of the layer's
  /// shortest side — useful for making the glow bleed slightly further from
  /// the touch point without inflating the radius spring.
  ///
  /// Corresponds to [GlassGlowColors.glowSpreadRadius].
  final double glowSpreadRadius;

  /// Master opacity multiplier applied on top of [glowColor]'s own alpha.
  ///
  /// Range 0–1. Defaults to 1 (no change). A value of 0.5 halves the effective
  /// glow opacity without changing the color itself, making it easy to dial
  /// the intensity down from the theme without adjusting the raw color.
  ///
  /// Corresponds to [GlassGlowColors.glowOpacity].
  final double glowOpacity;

  /// Global pulse intensity (0.0 to 1.0) for a full-window saturation/brightness
  /// highlight. Used by [GlassModalSheet] to synchronise a whole-surface pulse
  /// during high-velocity drag interactions.
  ///
  /// Defaults to 0 (no pulse).
  final double pulse;

  /// The hit test behavior of this gesture listener.
  ///
  /// Defaults to [HitTestBehavior.opaque].
  final HitTestBehavior hitTestBehavior;

  /// The child that will be painted above the glow effect.
  final Widget child;

  /// The shape to clip the glow to.
  /// Only clips the additive glow effect, not the child widget.
  final CustomClipper<Path>? clipper;

  /// Whether the glow is active at all.
  ///
  /// When false, the widget renders as a plain passthrough to [child] with
  /// zero overhead. Useful for disabling glow in specific states without
  /// restructuring the widget tree.
  ///
  /// Defaults to true.
  final bool enabled;

  /// When true, the glow fires on touch-down but is suppressed after the
  /// finger travels more than 10 logical pixels (i.e. a drag or scroll).
  ///
  /// This prevents the "stuck glow" artefact during scrollable menus or
  /// lists where a drag gesture should not leave a persistent glare behind.
  /// The glow is re-enabled automatically on the next touch-down.
  ///
  /// Defaults to false (glow always follows the pointer).
  final bool glowOnTapOnly;

  @override
  State<GlassGlow> createState() => _GlassGlowState();
}

class _GlassGlowState extends State<GlassGlow> {
  Offset? _initialPointerDown;
  bool _glowSuppressed = false;

  // BUG 3 FIX: Reset suppression flag when glowOnTapOnly is toggled off at
  // runtime (e.g. animation-driven state changes). Without this, the glow
  // remains permanently muted until the next pointer-down.
  @override
  void didUpdateWidget(GlassGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.glowOnTapOnly && !widget.glowOnTapOnly) {
      _glowSuppressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fast-path: no overhead if glow is disabled entirely.
    if (!widget.enabled) return widget.child;

    return GlassGlowLayer(
      clipper: widget.clipper,
      pulse: widget.pulse,
      child: Builder(
        builder: (innerContext) => Listener(
          behavior: widget.hitTestBehavior,
          onPointerDown: (event) {
            _initialPointerDown = event.localPosition;
            _glowSuppressed = false;
            _handlePointer(innerContext, event);
          },
          onPointerMove: (event) {
            if (widget.glowOnTapOnly && !_glowSuppressed) {
              final delta =
                  event.localPosition - (_initialPointerDown ?? Offset.zero);
              if (delta.distance > 10.0) {
                _glowSuppressed = true;
                _removeTouch(innerContext);
                return;
              }
            }
            if (!_glowSuppressed) _handlePointer(innerContext, event);
          },
          onPointerUp: (event) => _removeTouch(innerContext),
          onPointerCancel: (event) => _removeTouch(innerContext),
          child: widget.child,
        ),
      ),
    );
  }

  void _handlePointer(BuildContext context, PointerEvent event) {
    final layerState = GlassGlowLayer.maybeOf(context);
    if (layerState == null) return;

    // GlassGlowLayer may be at a different level than GlassGlow — e.g. a
    // toolbar GlassGlowLayer wrapping three buttons, each with their own
    // GlassGlow. event.localPosition is relative to this GlassGlow widget,
    // not relative to the GlassGlowLayer. We must convert via global space.
    final myBox = context.findRenderObject() as RenderBox?;
    final layerBox = layerState.context.findRenderObject() as RenderBox?;

    final Offset pos;
    if (myBox != null &&
        layerBox != null &&
        myBox.attached &&
        layerBox.attached) {
      // local-in-GlassGlow → global screen → local-in-GlassGlowLayer
      pos = layerBox.globalToLocal(myBox.localToGlobal(event.localPosition));
    } else {
      // Fallback for tests or during layout (same-level case is also correct).
      pos = event.localPosition;
    }

    layerState.updateTouch(
      pos,
      radius: widget.glowRadius,
      color: widget.glowColor,
      blurRadius: widget.glowBlurRadius,
      spreadRadius: widget.glowSpreadRadius,
      opacity: widget.glowOpacity,
    );
  }

  void _removeTouch(BuildContext context) {
    GlassGlowLayer.maybeOf(context)?.removeTouch();
  }
}

/// {@template glass_glow}
/// Represents a layer that can paint a glowing effect below its child.
///
/// Any child [GlassGlow] will send touch updates to this layer to
/// update the glow effect.
///
/// This is similar to how an `InkWell` works with a `Material` widget.
/// {@endtemplate}
class GlassGlowLayer extends StatefulWidget {
  /// {@macro glass_glow}
  const GlassGlowLayer({
    required this.child,
    this.clipper,
    this.pulse = 0,
    super.key,
  });

  /// The child that will be painted above the glow effect.
  final Widget child;

  /// The shape to clip the glow to.
  final CustomClipper<Path>? clipper;

  /// Global pulse intensity (0.0 to 1.0) for a full-window glow effect.
  final double pulse;

  @override
  State<GlassGlowLayer> createState() => GlassGlowLayerState();

  @internal
  // ignore: public_member_api_docs
  static GlassGlowLayerState? maybeOf(BuildContext context) {
    if (!context.mounted) return null;
    return context.findAncestorStateOfType<GlassGlowLayerState>();
  }
}

@internal
class GlassGlowLayerState extends State<GlassGlowLayer>
    with TickerProviderStateMixin {
  late final _offsetController = OffsetSpringController(
    vsync: this,
    spring: GlassSpring.smooth(duration: const Duration(seconds: 1)),
    initialValue: Offset.zero,
  );

  late final _alphaController = SingleSpringController(
    vsync: this,
    spring: GlassSpring.smooth(),
    initialValue: 0,
    lowerBound: 0,
    upperBound: 1,
  );

  late final _radiusController = SingleSpringController(
    vsync: this,
    spring: GlassSpring.smooth(),
    initialValue: 1.2,
  );

  bool _dragging = false;

  /// Whether a touch is currently active.
  ///
  /// Exposed for testing to verify the spring-switching behaviour introduced
  /// in the glow-follow-speed fix.
  @visibleForTesting
  bool get dragging => _dragging;

  double _baseRadius = 0;
  Color _baseColor = const Color.fromARGB(0, 0, 0, 0);
  double _baseBlurRadius = 0;
  double _baseSpreadRadius = 0;
  double _baseOpacity = 1;

  @override
  void dispose() {
    _offsetController.dispose();
    _alphaController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void updateTouch(
    Offset offset, {
    required double radius,
    required Color color,
    double blurRadius = 0,
    double spreadRadius = 0,
    double opacity = 1,
  }) {
    setState(() {
      _baseRadius = radius;
      _baseColor = color;
      _baseBlurRadius = blurRadius;
      _baseSpreadRadius = spreadRadius;
      _baseOpacity = opacity.clamp(0.0, 1.0);
    });

    if (!_dragging) {
      _dragging = true;
      // Snap to the exact touch point immediately so the glow appears right
      // where the finger lands — not at Offset.zero drifting over. Alpha then
      // fades in at the correct position instead of mid-spring.
      _offsetController.value = offset;
      _alphaController.spring = GlassSpring.interactive();
      _radiusController.spring = GlassSpring.interactive();
      // Switch position tracking to interactive spring so the glow follows
      // the finger at the same responsive speed as alpha/radius.
      _offsetController.spring = GlassSpring.interactive();
      _alphaController.animateTo(1, fromVelocity: 0);
      _radiusController.animateTo(1, fromVelocity: 0);
    }

    _offsetController.animateTo(offset);
  }

  void removeTouch() {
    if (!_dragging) return;
    _alphaController.spring = GlassSpring.smooth();
    _radiusController.spring = GlassSpring.smooth();
    // Restore smooth spring for the position fade-out drift.
    _offsetController.spring = GlassSpring.smooth(
      duration: const Duration(seconds: 1),
    );
    _dragging = false;
    _radiusController.animateTo(1.2);
    _alphaController.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _offsetController,
        _alphaController,
        _radiusController,
      ]),
      builder: (context, child) {
        final animatedAlpha = _baseColor.a * _alphaController.value;
        return _RenderGlassGlowLayerWidget(
          clipper: widget.clipper,
          pulse: widget.pulse,
          glowRadius: _baseRadius * _radiusController.value,
          glowColor: _baseColor.withValues(
            alpha: animatedAlpha * _baseOpacity,
          ),
          glowOffset: _offsetController.value,
          glowBlurRadius: _baseBlurRadius,
          glowSpreadRadius: _baseSpreadRadius,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _RenderGlassGlowLayerWidget extends SingleChildRenderObjectWidget {
  const _RenderGlassGlowLayerWidget({
    required this.clipper,
    required this.pulse,
    required this.glowRadius,
    required this.glowColor,
    required this.glowOffset,
    required this.glowBlurRadius,
    required this.glowSpreadRadius,
    required super.child,
  });

  final CustomClipper<Path>? clipper;
  final double pulse;
  final double glowRadius;
  final Color glowColor;
  final Offset glowOffset;
  final double glowBlurRadius;
  final double glowSpreadRadius;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGlassGlowLayer(
      clipper: clipper,
      pulse: pulse,
      glowRadius: glowRadius,
      glowColor: glowColor,
      glowOffset: glowOffset,
      glowBlurRadius: glowBlurRadius,
      glowSpreadRadius: glowSpreadRadius,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlassGlowLayer renderObject,
  ) {
    renderObject
      ..clipper = clipper
      ..pulse = pulse
      ..glowRadius = glowRadius
      ..glowColor = glowColor
      ..glowOffset = glowOffset
      ..glowBlurRadius = glowBlurRadius
      ..glowSpreadRadius = glowSpreadRadius;
  }
}

class _RenderGlassGlowLayer extends RenderProxyBox {
  _RenderGlassGlowLayer({
    required double glowRadius,
    required Color glowColor,
    required Offset glowOffset,
    required double glowBlurRadius,
    required double glowSpreadRadius,
    required double pulse,
    CustomClipper<Path>? clipper,
  })  : _glowRadius = glowRadius,
        _glowColor = glowColor,
        _glowOffset = glowOffset,
        _glowBlurRadius = glowBlurRadius,
        _glowSpreadRadius = glowSpreadRadius,
        _pulse = pulse,
        _clipper = clipper;

  CustomClipper<Path>? _clipper;
  CustomClipper<Path>? get clipper => _clipper;
  set clipper(CustomClipper<Path>? value) {
    if (_clipper == value) return;
    _clipper = value;
    markNeedsPaint();
  }

  double _pulse;
  double get pulse => _pulse;
  set pulse(double value) {
    if (_pulse == value) return;
    _pulse = value;
    markNeedsPaint();
  }

  double _glowRadius;
  double get glowRadius => _glowRadius;
  set glowRadius(double value) {
    if (_glowRadius == value) return;
    _glowRadius = value;
    markNeedsPaint();
  }

  Color _glowColor;
  Color get glowColor => _glowColor;
  set glowColor(Color value) {
    if (_glowColor == value) return;
    _glowColor = value;
    markNeedsPaint();
  }

  Offset _glowOffset;
  Offset get glowOffset => _glowOffset;
  set glowOffset(Offset value) {
    if (_glowOffset == value) return;
    _glowOffset = value;
    markNeedsPaint();
  }

  double _glowBlurRadius;
  double get glowBlurRadius => _glowBlurRadius;
  set glowBlurRadius(double value) {
    if (_glowBlurRadius == value) return;
    _glowBlurRadius = value;
    markNeedsPaint();
  }

  double _glowSpreadRadius;
  double get glowSpreadRadius => _glowSpreadRadius;
  set glowSpreadRadius(double value) {
    if (_glowSpreadRadius == value) return;
    _glowSpreadRadius = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // 1. Paint the children (which includes AdaptiveGlass taking its backdrop snapshot)
    super.paint(context, offset);

    final canvas = context.canvas;

    // 2. Global Specular Pulse (full-window additive highlight, driven by GlassModalSheet
    //    saturation controller during high-velocity drag interactions).
    if (_pulse > 0) {
      final pulsePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.08 * _pulse)
        ..blendMode = BlendMode.plus;

      if (_clipper != null) {
        canvas.save();
        canvas.clipPath(_clipper!.getClip(size).shift(offset));
        canvas.drawRect(offset & size, pulsePaint);
        canvas.restore();
      } else {
        canvas.drawRect(offset & size, pulsePaint);
      }
    }

    // 3. Local Interactive Glow (finger glare — radial gradient following the touch point)
    if (_glowColor.a > 0 && _glowRadius > 0) {
      final glowPosition = offset + _glowOffset;
      // Use the shortest side so that wide pills don't generate massive glow
      // spilling vertically off the surface.
      final shortSide = math.min(size.width, size.height);
      final radius = _glowRadius * shortSide + _glowSpreadRadius * shortSide;

      // RadialGradient.createShader() bakes the center position into the shader
      // via the Rect passed to it — caching across position changes is incorrect.
      // Per-frame creation is cheap for a simple radial gradient (uniform-only).
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [_glowColor, _glowColor.withValues(alpha: 0)],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: glowPosition, radius: radius))
        ..blendMode = BlendMode.plus;

      // Optional Gaussian blur to soften the glow halo. Only create the
      // MaskFilter when non-zero to avoid a no-op allocation every frame.
      if (_glowBlurRadius > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, _glowBlurRadius);
      }

      // 2. Additive light over geometry boundary only
      if (_clipper != null) {
        canvas.save();
        canvas.clipPath(_clipper!.getClip(size).shift(offset));
        canvas.drawCircle(glowPosition, radius, paint);
        canvas.restore();
      } else {
        canvas.drawCircle(glowPosition, radius, paint);
      }
    }
  }
}
