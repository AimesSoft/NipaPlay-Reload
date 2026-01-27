import 'dart:ui';
import 'package:flutter/cupertino.dart';
import '../adaptive_scaffold.dart';

/// iOS 26 styled tab bar with Liquid Glass effect
class IOS26TabBar extends StatelessWidget implements PreferredSizeWidget {
  const IOS26TabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoColors.black.withValues(alpha: 0.8)
            : CupertinoColors.white.withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(
            color: isDark
                ? CupertinoColors.white.withValues(alpha: 0.1)
                : CupertinoColors.black.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            height: 50,
            padding: const EdgeInsets.only(bottom: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                destinations.length,
                (index) => Expanded(
                  child: _TabBarItem(
                    destination: destinations[index],
                    isSelected: index == selectedIndex,
                    onTap: () => onTap(index),
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

class _TabBarItem extends StatelessWidget {
  const _TabBarItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final AdaptiveNavigationDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    final iconColor = isSelected
        ? CupertinoColors.activeBlue
        : (isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2);

    final textColor = isSelected
        ? CupertinoColors.activeBlue
        : (isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_getIcon(), color: iconColor, size: 24),
          const SizedBox(height: 2),
          Text(
            destination.label,
            style: TextStyle(
              fontSize: 10,
              color: textColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIcon() {
    final icon = isSelected && destination.selectedIcon != null
        ? destination.selectedIcon
        : destination.icon;

    if (icon is IconData) {
      return icon;
    } else if (icon is String) {
      return _sfSymbolToCupertinoIcon(icon);
    }
    return CupertinoIcons.circle;
  }

  IconData _sfSymbolToCupertinoIcon(String sfSymbol) {
    const iconMap = {
      'house': CupertinoIcons.house,
      'house.fill': CupertinoIcons.house_fill,
      'magnifyingglass': CupertinoIcons.search,
      'heart': CupertinoIcons.heart,
      'heart.fill': CupertinoIcons.heart_fill,
      'person': CupertinoIcons.person,
      'person.fill': CupertinoIcons.person_fill,
      'gear': CupertinoIcons.settings,
      'star': CupertinoIcons.star,
      'star.fill': CupertinoIcons.star_fill,
    };
    return iconMap[sfSymbol] ?? CupertinoIcons.circle;
  }
}
