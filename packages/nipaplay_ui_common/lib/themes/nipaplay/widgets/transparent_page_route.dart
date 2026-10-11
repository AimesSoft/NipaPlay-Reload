import 'package:flutter/material.dart';

// Helper class for the custom page route (to make it non-opaque)
class TransparentPageRoute<T> extends PageRoute<T> {
  TransparentPageRoute({
    required this.builder,
    super.settings,
  });

  final WidgetBuilder builder;

  @override
  bool get opaque => false; // THIS IS THE KEY!

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return builder(context);
  }

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300); // Adjust as needed

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // You can add a fade transition or similar here if desired
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }
} 