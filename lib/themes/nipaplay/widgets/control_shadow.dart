import 'package:flutter/material.dart';

class ControlShadow extends StatelessWidget {
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow> shadows;

  const ControlShadow({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.padding = EdgeInsets.zero,
    this.shadows = const [
      BoxShadow(
        color: Color(0xC0000000),
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
      BoxShadow(
        color: Color(0x80000000),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ],
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: borderRadius,
        boxShadow: shadows,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class ControlIconShadow extends StatelessWidget {
  final Widget child;
  final List<Shadow> shadows;

  const ControlIconShadow({
    super.key,
    required this.child,
    this.shadows = const [
      Shadow(
        color: Color(0xCC000000),
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
      Shadow(
        color: Color(0x99000000),
        blurRadius: 18,
        offset: Offset(0, 4),
      ),
    ],
  });

  @override
  Widget build(BuildContext context) {
    return IconTheme.merge(
      data: IconThemeData(shadows: shadows),
      child: child,
    );
  }
}

class ControlTextShadow extends StatelessWidget {
  final Widget child;
  final List<Shadow> shadows;

  const ControlTextShadow({
    super.key,
    required this.child,
    this.shadows = const [
      Shadow(
        color: Color(0xCC000000),
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
      Shadow(
        color: Color(0x99000000),
        blurRadius: 18,
        offset: Offset(0, 4),
      ),
    ],
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: TextStyle(shadows: shadows),
      child: child,
    );
  }
}
