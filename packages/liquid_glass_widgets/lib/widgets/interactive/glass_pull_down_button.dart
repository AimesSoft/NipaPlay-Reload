import 'package:flutter/cupertino.dart';

import '../../types/glass_quality.dart';
import '../overlays/glass_menu.dart';
import '../overlays/glass_menu_item.dart';
import 'glass_button.dart';
import '../../theme/glass_theme_helpers.dart';
import '../../src/renderer/liquid_shape.dart';

/// A toolbar button that opens a liquid glass pull-down menu.
///
/// This widget combines [GlassButton] and [GlassMenu] to create a standard
/// "pull-down" interaction pattern commonly used in toolbars and navigation bars.
class GlassPullDownButton extends StatelessWidget {
  /// Creates a glass pull-down button.
  const GlassPullDownButton({
    required this.items,
    Widget? icon,
    this.label,
    super.key,
    this.buttonWidth = 44,
    this.buttonHeight = 44,
    this.buttonShape,
    this.menuWidth = 200,
    this.menuAlignment,
    this.quality,
    this.onSelected,
  }) : icon = icon ?? const Icon(CupertinoIcons.ellipsis_circle);

  /// The shape of the trigger button.
  ///
  /// If null, defaults to [LiquidOval].
  final LiquidShape? buttonShape;

  /// The icon widget to display on the button.
  final Widget icon;

  /// Optional label to display next to the icon.
  final String? label;

  /// The list of items to display in the menu.
  ///
  /// Accepts [GlassMenuItem] and [GlassMenuDivider] widgets, matching the
  /// [GlassMenu.items] contract directly. [GlassMenuDivider] items are passed
  /// through as-is; only [GlassMenuItem] instances are wrapped by [onSelected].
  final List<Widget> items;

  /// Width of the trigger button.
  final double buttonWidth;

  /// Height of the trigger button.
  final double buttonHeight;

  /// Width of the expanded menu.
  final double menuWidth;

  /// Controls where the menu expands relative to the trigger button.
  ///
  /// Defaults to [GlassMenuAlignment.none], which auto-detects the best
  /// alignment based on the trigger's position on screen.
  final GlassMenuAlignment? menuAlignment;

  /// Quality of the glass effect.
  final GlassQuality? quality;

  /// Callback when a menu item is selected.
  ///
  /// This is called in addition to the individual [GlassMenuItem.onTap] callback.
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    // Inherit quality from parent layer if not explicitly set
    final effectiveQuality = GlassThemeHelpers.resolveQuality(
      context,
      widgetQuality: quality,
    );

    final effectiveTextColor =
        CupertinoTheme.of(context).textTheme.textStyle.color ??
            CupertinoColors.label;

    return GlassMenu(
      menuWidth: menuWidth,
      menuAlignment: menuAlignment,
      quality: effectiveQuality,
      triggerBuilder: (context, toggleMenu) {
        if (label != null && label!.isNotEmpty) {
          return GlassButton.custom(
            onTap: toggleMenu,
            width: buttonWidth,
            height: buttonHeight,
            shape: buttonShape ?? const LiquidOval(),
            quality: effectiveQuality,
            useOwnLayer: effectiveQuality == GlassQuality.premium,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(size: 20, color: effectiveTextColor),
                  child: icon,
                ),
                const SizedBox(width: 8),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: effectiveTextColor,
                  ),
                ),
              ],
            ),
          );
        }

        return GlassButton(
          onTap: toggleMenu,
          icon: icon,
          label: label ?? '',
          width: buttonWidth,
          height: buttonHeight,
          shape: buttonShape ?? const LiquidOval(),
          quality: effectiveQuality,
          useOwnLayer: effectiveQuality == GlassQuality.premium,
        );
      },
      items: items.map((item) {
        // Wrap GlassMenuItem taps to fire the onSelected callback.
        // GlassMenuDivider and other non-GlassMenuItem widgets are passed through.
        if (onSelected != null && item is GlassMenuItem) {
          return GlassMenuItem(
            title: item.title,
            icon: item.icon,
            isDestructive: item.isDestructive,
            subtitle: item.subtitle,
            enabled: item.enabled,
            onTap: () {
              item.onTap.call();
              onSelected!(item.title);
            },
            trailing: item.trailing,
          );
        }
        return item;
      }).toList(),
    );
  }
}
