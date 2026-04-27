import 'dart:ui';

import 'package:flutter/material.dart';

const double kNipaplayLargeScreenBottomHintHeight = 40;

class NipaplayLargeScreenBottomHintOverlay extends StatelessWidget {
  const NipaplayLargeScreenBottomHintOverlay({
    super.key,
    required this.isDarkMode,
    required this.onToggleMenu,
  });

  final bool isDarkMode;
  final VoidCallback onToggleMenu;

  @override
  Widget build(BuildContext context) {
    final Color iconColor = isDarkMode ? Colors.white : Colors.black87;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color backgroundTint = isDarkMode
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.14);

    return SizedBox(
      height: kNipaplayLargeScreenBottomHintHeight,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: ColoredBox(
            color: backgroundTint,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: onToggleMenu,
                  borderRadius: BorderRadius.zero,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.menu_rounded,
                        size: 22,
                        color: iconColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '菜单',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
