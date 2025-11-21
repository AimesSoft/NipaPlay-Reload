import 'package:flutter/cupertino.dart';

import 'package:nipaplay/utils/cupertino_settings_colors.dart';

/// Cupertino-styled settings row with optional subtitle and chevron.
class CupertinoSettingsTile extends StatelessWidget {
  const CupertinoSettingsTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.backgroundColor,
    this.showChevron = false,
    this.selected = false,
    this.contentPadding,
  });

  /// Optional leading widget, typically an icon.
  final Widget? leading;

  /// Tile title widget; uses Cupertino settings typography by default.
  final Widget title;

  /// Optional subtitle widget displayed below the title.
  final Widget? subtitle;

  /// Optional trailing widget. Overrides [showChevron] and [selected].
  final Widget? trailing;

  /// Tap handler for the tile.
  final VoidCallback? onTap;

  /// Background color override for the tile container.
  final Color? backgroundColor;

  /// Displays a chevron when no custom trailing is provided.
  final bool showChevron;

  /// Displays a checkmark trailing when no custom trailing is provided.
  final bool selected;

  /// Custom content padding for the tile.
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final Color resolvedBackground =
        backgroundColor ?? resolveSettingsTileBackground(context);

    return CupertinoListTile(
      onTap: onTap,
      padding: contentPadding ??
          const EdgeInsetsDirectional.fromSTEB(20, 12, 16, 12),
      backgroundColor: resolvedBackground,
      leading: leading,
      title: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 17,
          color: resolveSettingsPrimaryTextColor(context),
        ),
        child: title,
      ),
      subtitle: subtitle == null
          ? null
          : DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 13,
                color: resolveSettingsSecondaryTextColor(context),
              ),
              child: subtitle!,
            ),
      trailing: _buildTrailing(context),
    );
  }

  Widget? _buildTrailing(BuildContext context) {
    if (trailing != null) {
      return trailing;
    }
    if (selected) {
      return Icon(
        CupertinoIcons.check_mark,
        size: 18,
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.activeBlue,
          context,
        ),
      );
    }
    if (showChevron) {
      return Icon(
        CupertinoIcons.chevron_forward,
        size: 18,
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGrey2,
          context,
        ),
      );
    }
    return null;
  }
}
