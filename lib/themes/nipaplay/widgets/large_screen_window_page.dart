import 'package:flutter/material.dart';

class NipaplayLargeScreenWindowPageRoute<T> extends PageRoute<T> {
  NipaplayLargeScreenWindowPageRoute({
    required this.builder,
    this.enableAnimation = true,
    this.dismissible = true,
    super.settings,
  });

  final WidgetBuilder builder;
  final bool enableAnimation;
  final bool dismissible;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => 'Close';

  @override
  bool get barrierDismissible => dismissible;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!enableAnimation) {
      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ),
        child: child,
      );
    }

    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
    );
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
}
