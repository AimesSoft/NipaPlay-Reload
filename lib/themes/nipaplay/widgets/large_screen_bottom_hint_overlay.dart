import 'dart:ui';

import 'package:flutter/material.dart';

const double kNipaplayLargeScreenBottomHintHeight = 40;

class NipaplayLargeScreenBottomHintOverlay extends StatelessWidget {
  const NipaplayLargeScreenBottomHintOverlay({
    super.key,
    required this.isDarkMode,
    required this.onToggleMenu,
    this.onOpenSettings,
    this.menuLabel = '菜单',
    this.settingsLabel = '设置',
  });

  final bool isDarkMode;
  final VoidCallback onToggleMenu;
  final VoidCallback? onOpenSettings;
  final String menuLabel;
  final String settingsLabel;

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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
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
                            menuLabel,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onOpenSettings != null)
                      InkWell(
                        onTap: onOpenSettings,
                        borderRadius: BorderRadius.zero,
                        splashFactory: NoSplash.splashFactory,
                        overlayColor:
                            WidgetStateProperty.all(Colors.transparent),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.settings_rounded,
                              size: 22,
                              color: iconColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              settingsLabel,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ),
    );
  }
}
