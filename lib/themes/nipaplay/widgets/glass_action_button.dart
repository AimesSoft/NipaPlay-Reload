import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'tooltip_bubble.dart';

class GlassActionButton extends StatefulWidget {
  const GlassActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 26,
    this.buttonSize = 48,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final double buttonSize;

  @override
  State<GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<GlassActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: TooltipBubble(
        text: widget.tooltip,
        showOnRight: false,
        verticalOffset: 8,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapCancel: () => setState(() => _isPressed = false),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onPressed();
          },
          child: GlassmorphicContainer(
            width: widget.buttonSize,
            height: widget.buttonSize,
            borderRadius: widget.buttonSize / 2,
            blur: context
                    .watch<AppearanceSettingsProvider>()
                    .enableWidgetBlurEffect
                ? 30
                : 0,
            alignment: Alignment.center,
            border: 1,
            linearGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFffffff).withValues(alpha: 0.2),
                const Color(0xFFFFFFFF).withValues(alpha: 0.2),
              ],
            ),
            borderGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFffffff).withValues(alpha: 0.5),
                const Color((0xFFFFFFFF)).withValues(alpha: 0.5),
              ],
            ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isHovered ? 1.0 : 0.6,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 100),
                scale: _isPressed ? 0.9 : 1.0,
                child: Icon(
                  widget.icon,
                  color: Colors.white,
                  size: widget.iconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
