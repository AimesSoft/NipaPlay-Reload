import 'package:flutter/material.dart';
import 'package:nipaplay/models/background_image_render_mode.dart';

class BackgroundImageCompositor extends StatelessWidget {
  const BackgroundImageCompositor({
    super.key,
    required this.image,
    required this.overlayColor,
    required this.renderMode,
    required this.overlayOpacity,
    required this.duration,
    required this.curve,
  });

  final Widget image;
  final Color overlayColor;
  final BackgroundImageRenderMode renderMode;
  final double overlayOpacity;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final double clampedOpacity = overlayOpacity.clamp(0.0, 1.0);
    final Color targetColor = overlayColor.withValues(alpha: clampedOpacity);

    return TweenAnimationBuilder<Color?>(
      duration: duration,
      curve: curve,
      tween: ColorTween(end: targetColor),
      builder: (context, color, child) {
        final effectiveColor = color ?? targetColor;
        return ColorFiltered(
          colorFilter: ColorFilter.mode(
            effectiveColor,
            _resolveBlendMode(renderMode),
          ),
          child: child,
        );
      },
      child: image,
    );
  }

  BlendMode _resolveBlendMode(BackgroundImageRenderMode mode) {
    switch (mode) {
      case BackgroundImageRenderMode.softLight:
        return BlendMode.softLight;
      case BackgroundImageRenderMode.opacity:
      default:
        return BlendMode.srcOver;
    }
  }
}
