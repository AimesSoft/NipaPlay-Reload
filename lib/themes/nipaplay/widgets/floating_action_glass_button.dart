import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_tooltip_bubble.dart';

class FloatingActionGlassButton extends StatelessWidget {
  final IconData iconData;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? description; // 新增：悬浮气泡描述
  final double size;
  final double iconSize;

  const FloatingActionGlassButton({
    super.key,
    required this.iconData,
    required this.onPressed,
    this.tooltip,
    this.description, // 新增：悬浮气泡描述
    this.size = 64,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFFFF2E55);
    final double buttonSize = size;
    final Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            color: accentColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              iconData,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        ),
      ),
    );

    // 如果有描述信息，则用HoverTooltipBubble包装
    if (description != null && description!.isNotEmpty) {
      return HoverTooltipBubble(
        text: description!,
        showDelay: const Duration(milliseconds: 500),
        hideDelay: const Duration(milliseconds: 100),
        child: button,
      );
    } else {
      return button;
    }
  }
} 
