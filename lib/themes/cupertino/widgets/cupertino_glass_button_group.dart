import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoGlassButtonGroupItem {
  const CupertinoGlassButtonGroupItem({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

class CupertinoGlassButtonGroup extends StatelessWidget {
  const CupertinoGlassButtonGroup({
    super.key,
    required this.items,
    this.buttonSize = 40,
  });

  final List<CupertinoGlassButtonGroupItem> items;
  final double buttonSize;

  // UIKit's iOS 26 glass chrome paints a few points beyond the platform
  // view's logical bounds. The Flutter fallback stays strictly inside its
  // bounds, so give its shell a little more room to preserve the same visual
  // size while keeping the icon size unchanged.
  static const double _fallbackHeightExpansion = 4;
  static const double _fallbackItemWidthExpansion = 6;
  static const double _iconSize = 19;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final iconColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );

    if (PlatformInfo.isIOS26OrHigher()) {
      return IOS26ButtonGroup(
        height: buttonSize,
        itemWidth: buttonSize,
        items: [
          for (final item in items)
            IOS26ButtonGroupItem(
              label: item.label,
              sfSymbol: _sfSymbolForIcon(item.icon),
              enabled: item.onPressed != null,
            ),
        ],
        onPressed: (index) => items[index].onPressed?.call(),
      );
    }

    final fallbackHeight = buttonSize + _fallbackHeightExpansion;
    final fallbackItemWidth = buttonSize + _fallbackItemWidthExpansion;

    return GlassButtonGroup.icons(
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: isLight
          ? const LiquidGlassSettings(
              glassColor: Color(0x38FFFFFF),
              blur: 8,
              lightIntensity: 0.72,
              ambientStrength: 0.28,
              ambientRim: 0.14,
              saturation: 1.2,
              glowIntensity: 0.9,
              whitenStrength: 0.3,
              whitenGated: false,
              backerColor: Color(0x14FFFFFF),
            )
          : null,
      borderRadius: fallbackHeight / 2,
      iconSize: _iconSize,
      itemPadding: EdgeInsets.symmetric(
        horizontal: (fallbackItemWidth - _iconSize) / 2,
        vertical: (fallbackHeight - _iconSize) / 2,
      ),
      items: [
        for (final item in items)
          GlassButtonGroupItem(
            label: item.label,
            icon: Icon(item.icon, color: iconColor),
            enabled: item.onPressed != null,
            onTap: item.onPressed ?? _noop,
          ),
      ],
    );
  }

  String _sfSymbolForIcon(IconData icon) {
    if (icon == CupertinoIcons.ellipsis) return 'ellipsis';
    if (icon == CupertinoIcons.sun_max_fill) return 'sun.max.fill';
    if (icon == CupertinoIcons.moon_fill) return 'moon.fill';
    if (icon == CupertinoIcons.gear_alt_fill) return 'gearshape.fill';
    if (icon == CupertinoIcons.add) return 'plus';
    if (icon == CupertinoIcons.search) return 'magnifyingglass';
    if (icon == CupertinoIcons.list_bullet) return 'list.bullet';
    if (icon == CupertinoIcons.square_grid_2x2) return 'square.grid.2x2';
    return 'circle';
  }

  static void _noop() {}
}
