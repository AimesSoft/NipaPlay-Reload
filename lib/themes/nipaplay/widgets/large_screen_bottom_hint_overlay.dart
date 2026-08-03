import 'dart:ui';

import 'package:flutter/material.dart';

const double kNipaplayLargeScreenBottomHintHeight = 56;

class NipaplayLargeScreenBottomHintOverlay extends StatelessWidget {
  const NipaplayLargeScreenBottomHintOverlay({
    super.key,
    required this.isDarkMode,
    required this.onToggleMenu,
    this.onOpenContext,
    this.menuLabel = '菜单',
    this.contextLabel = '设置',
    this.contextIcon = Icons.settings_rounded,
    this.contextKey,
    this.useVideoBackground = false,
  });

  final bool isDarkMode;
  final VoidCallback onToggleMenu;
  final VoidCallback? onOpenContext;
  final String menuLabel;
  final String contextLabel;
  final IconData contextIcon;
  final Key? contextKey;
  final bool useVideoBackground;

  @override
  Widget build(BuildContext context) {
    final Color iconColor = isDarkMode ? Colors.white : Colors.black87;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color backgroundTint = useVideoBackground
        ? (isDarkMode ? Colors.black : Colors.white).withValues(alpha: 0.5)
        : isDarkMode
            ? Colors.black.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.14);
    final Color dividerColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.12);

    Widget buildAction({
      required Widget icon,
      required String label,
      required VoidCallback onTap,
      Key? key,
    }) {
      return InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused) ||
              states.contains(WidgetState.hovered)) {
            return textColor.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: kNipaplayLargeScreenBottomHintHeight,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundTint,
              border: Border(
                top: BorderSide(color: dividerColor, width: 1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  buildAction(
                    onTap: onToggleMenu,
                    label: menuLabel,
                    icon: Icon(
                      Icons.menu_rounded,
                      size: 24,
                      color: iconColor,
                    ),
                  ),
                  if (onOpenContext != null)
                    buildAction(
                      key: contextKey,
                      onTap: onOpenContext!,
                      label: contextLabel,
                      icon: Icon(
                        contextIcon,
                        size: 24,
                        color: iconColor,
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
