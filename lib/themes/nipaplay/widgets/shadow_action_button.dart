import 'package:flutter/material.dart';
import 'tooltip_bubble.dart';
import 'control_shadow.dart';

class ShadowActionButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;

  const ShadowActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 26,
  });

  @override
  State<ShadowActionButton> createState() => _ShadowActionButtonState();
}

class _ShadowActionButtonState extends State<ShadowActionButton> {
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
          child: Padding(
            padding: const EdgeInsets.all(8.0), // 增加一些点击区域
            child: AnimatedScale(
              duration: const Duration(milliseconds: 100),
              scale: _isPressed ? 0.9 : (_isHovered ? 1.1 : 1.0),
              child: ControlIconShadow(
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
