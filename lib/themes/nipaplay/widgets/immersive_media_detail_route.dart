import 'package:flutter/material.dart';

/// Streaming-style full-page transition used by the immersive media detail UI.
///
/// The detail surface unfolds from the poster side, keeping both routes fully
/// opaque. The Hero flies above this reveal in stable final-layout coordinates;
/// exit reverses the same motion instead of fading the whole poster away.
class ImmersiveMediaDetailPageRoute<T> extends PageRouteBuilder<T> {
  ImmersiveMediaDetailPageRoute({
    required WidgetBuilder builder,
    required bool enableAnimation,
    bool animatePoster = false,
    super.settings,
  }) : super(
          opaque: true,
          transitionDuration: enableAnimation
              ? Duration(milliseconds: animatePoster ? 460 : 360)
              : Duration.zero,
          reverseTransitionDuration: enableAnimation
              ? Duration(milliseconds: animatePoster ? 360 : 280)
              : Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (!enableAnimation) return child;
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.fastOutSlowIn,
              reverseCurve: Curves.fastOutSlowIn.flipped,
            );
            return AnimatedBuilder(
              animation: curved,
              child: child,
              builder: (context, child) => ClipPath(
                clipBehavior: Clip.antiAlias,
                clipper: _MediaDetailRevealClipper(curved.value),
                child: child,
              ),
            );
          },
        );
}

class _MediaDetailRevealClipper extends CustomClipper<Path> {
  const _MediaDetailRevealClipper(this.progress);
  final double progress;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width * progress, size.height),
      Radius.circular(24 * (1 - progress)),
    ));

  @override
  bool shouldReclip(_MediaDetailRevealClipper oldClipper) =>
      progress != oldClipper.progress;
}
