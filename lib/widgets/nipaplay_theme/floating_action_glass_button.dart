import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/widgets/nipaplay_theme/hover_tooltip_bubble.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

class FloatingActionGlassButton extends StatelessWidget {
  final IconData iconData;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? description; // 新增：悬浮气泡描述

  const FloatingActionGlassButton({
    super.key,
    required this.iconData,
    required this.onPressed,
    this.tooltip,
    this.description, // 新增：悬浮气泡描述
  });

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final Widget button = GlassmorphicContainer(
      width: 56,
      height: 56,
      borderRadius: 28,
      blur: appearanceSettings.enableWidgetBlurEffect ? 25 : 0,
      alignment: Alignment.center,
      border: 1,
      linearGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          appearanceSettings.enableWidgetBlurEffect ?  Color(0xFFffffff).withOpacity(0.1) : Color.fromARGB(255, 193, 193, 193).withOpacity(0.5),
          appearanceSettings.enableWidgetBlurEffect ?  Color(0xFFffffff).withOpacity(0.1):Color.fromARGB(255, 208, 208, 208).withOpacity(0.5)
        ],
      ),
      borderGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFffffff).withOpacity(0.5),
          const Color(0xFFFFFFFF).withOpacity(0.5),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: Center(
            child: Icon(
              iconData,
              color: Colors.white,
              size: 24,
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