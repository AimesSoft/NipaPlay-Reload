import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_menu_theme.dart';

class PlayerOverlaySurface extends StatelessWidget {
  const PlayerOverlaySurface({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 8,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = PlayerMenuTheme.colorsOf(context);
    final radius = BorderRadius.circular(borderRadius);

    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: radius,
        border: Border.all(color: colors.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: colors.foreground),
        child: IconTheme.merge(
          data: IconThemeData(color: colors.foreground),
          child: child,
        ),
      ),
    );
  }
}
