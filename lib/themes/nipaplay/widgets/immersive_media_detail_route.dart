import 'package:flutter/material.dart';

/// Streaming-style full-page transition used by the immersive media detail UI.
///
/// The new page gently expands and fades over the library. Flutter drives the
/// same animation backwards when the page is popped, so entry and exit stay
/// visually paired.
class ImmersiveMediaDetailPageRoute<T> extends PageRouteBuilder<T> {
  ImmersiveMediaDetailPageRoute({
    required WidgetBuilder builder,
    required bool enableAnimation,
    super.settings,
  }) : super(
          opaque: true,
          transitionDuration: enableAnimation
              ? const Duration(milliseconds: 360)
              : Duration.zero,
          reverseTransitionDuration: enableAnimation
              ? const Duration(milliseconds: 280)
              : Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (!enableAnimation) return child;
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                alignment: Alignment.center,
                scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.018),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              ),
            );
          },
        );
}
