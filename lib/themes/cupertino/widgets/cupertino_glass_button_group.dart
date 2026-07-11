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

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final foreground = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final separator = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
    final radius = BorderRadius.circular(buttonSize / 2);

    return AdaptiveBlurView(
      blurStyle: BlurStyle.systemThinMaterial,
      borderRadius: radius,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              ColoredBox(
                color: separator.withValues(alpha: 0.55),
                child: SizedBox(width: 0.5, height: buttonSize * 0.5),
              ),
            Semantics(
              button: true,
              label: items[index].label,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.square(buttonSize),
                borderRadius: BorderRadius.zero,
                onPressed: items[index].onPressed,
                child: Icon(
                  items[index].icon,
                  size: 19,
                  color: items[index].onPressed == null
                      ? foreground.withValues(alpha: 0.35)
                      : foreground,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
