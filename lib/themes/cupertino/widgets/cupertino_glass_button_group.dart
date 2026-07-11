import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return GlassButtonGroup.icons(
      useOwnLayer: true,
      quality: GlassQuality.standard,
      borderRadius: buttonSize / 2,
      iconSize: 19,
      itemPadding: EdgeInsets.all((buttonSize - 19) / 2),
      items: [
        for (final item in items)
          GlassButtonGroupItem(
            label: item.label,
            icon: Icon(item.icon),
            enabled: item.onPressed != null,
            onTap: item.onPressed ?? _noop,
          ),
      ],
    );
  }

  static void _noop() {}
}
