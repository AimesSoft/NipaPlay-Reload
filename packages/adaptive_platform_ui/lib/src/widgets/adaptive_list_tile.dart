import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';

/// An adaptive list tile that renders platform-specific styles
///
/// On iOS: Uses CupertinoListTile-like styling
/// On Android: Uses Material ListTile
class AdaptiveListTile extends StatelessWidget {
  /// Creates an adaptive list tile
  const AdaptiveListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.selected = false,
    this.backgroundColor,
    this.padding,
  });

  /// A widget to display before the title.
  final Widget? leading;

  /// The primary content of the list tile.
  final Widget? title;

  /// Additional content displayed below the title.
  final Widget? subtitle;

  /// A widget to display after the title.
  final Widget? trailing;

  /// Called when the user taps this list tile.
  final VoidCallback? onTap;

  /// Called when the user long-presses on this list tile.
  final VoidCallback? onLongPress;

  /// Whether this list tile is interactive.
  final bool enabled;

  /// Whether this list tile is selected.
  final bool selected;

  /// The background color of the tile.
  final Color? backgroundColor;

  /// The tile's internal padding.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isIOS) {
      return _buildCupertinoListTile(context);
    }

    // Android - Use Material ListTile
    return _buildMaterialListTile(context);
  }

  Widget _buildCupertinoListTile(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    Widget child = Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            (selected
                ? (isDark
                      ? CupertinoColors.systemGrey5.darkColor
                      : CupertinoColors.systemGrey6.color)
                : (isDark
                      ? CupertinoColors.darkBackgroundGray
                      : CupertinoColors.white)),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? CupertinoColors.systemGrey4
                : CupertinoColors.separator,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                      color: enabled
                          ? (isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black)
                          : (isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.systemGrey2),
                    ),
                    child: title!,
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.systemGrey2,
                    ),
                    child: subtitle!,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );

    if (enabled && (onTap != null || onLongPress != null)) {
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }

    return child;
  }

  Widget _buildMaterialListTile(BuildContext context) {
    return ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      enabled: enabled,
      selected: selected,
      tileColor: backgroundColor,
      contentPadding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
