import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

/// Width of the vertical liquid-glass tab bar.
const double cupertinoVerticalGlassTabBarWidth = 56.0;

const double _itemExtent = 50.0;
const double _barPadding = 3.0;
const double _iconSize = 24.0;

class CupertinoVerticalGlassTab {
  const CupertinoVerticalGlassTab({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

/// Tab bar for windows where the system places bars vertically on the side
/// (iPhone Duo). Like the system's vertical bars it shows symbols only; the
/// label stays available to assistive technologies.
class CupertinoVerticalGlassTabBar extends StatelessWidget {
  const CupertinoVerticalGlassTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.selectedColor,
    required this.unselectedColor,
    this.settings,
  });

  final List<CupertinoVerticalGlassTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final LiquidGlassSettings? settings;

  static double heightFor(int tabCount) =>
      tabCount * _itemExtent + _barPadding * 2;

  @override
  Widget build(BuildContext context) {
    const width = cupertinoVerticalGlassTabBarWidth;
    const indicatorExtent = width - _barPadding * 2;
    final indicatorColor =
        CupertinoColors.label.resolveFrom(context).withValues(alpha: 0.1);

    return GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: settings,
      shape: const LiquidRoundedSuperellipse(borderRadius: width / 2),
      width: width,
      height: heightFor(tabs.length),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: _barPadding,
            top: _barPadding +
                selectedIndex * _itemExtent +
                (_itemExtent - indicatorExtent) / 2,
            width: indicatorExtent,
            height: indicatorExtent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: indicatorColor,
                borderRadius: BorderRadius.circular(indicatorExtent / 2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(_barPadding),
            child: Column(
              children: [
                for (var index = 0; index < tabs.length; index++)
                  _VerticalGlassTabButton(
                    tab: tabs[index],
                    selected: index == selectedIndex,
                    color: index == selectedIndex
                        ? selectedColor
                        : unselectedColor,
                    onTap: () => onTabSelected(index),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalGlassTabButton extends StatelessWidget {
  const _VerticalGlassTabButton({
    required this.tab,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final CupertinoVerticalGlassTab tab;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: cupertinoVerticalGlassTabBarWidth - _barPadding * 2,
          height: _itemExtent,
          child: Center(
            child: Icon(tab.icon, size: _iconSize, color: color),
          ),
        ),
      ),
    );
  }
}
