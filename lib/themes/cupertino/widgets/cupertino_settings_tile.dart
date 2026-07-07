import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

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
    final Widget? trailingWidget = _buildTrailing(context);

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ColoredBox(
          color: resolvedBackground,
          child: Padding(
            padding: contentPadding ??
                const EdgeInsetsDirectional.fromSTEB(20, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(child: leading),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: _buildResponsiveContent(context, trailingWidget),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveContent(BuildContext context, Widget? trailingWidget) {
    final textColumn = _buildTextColumn(context);
    if (trailingWidget == null) {
      return textColumn;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final trailingMaxWidth = constraints.maxWidth * 0.48;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: textColumn),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: trailingMaxWidth),
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                widthFactor: 1,
                child: trailingWidget,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextColumn(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefaultTextStyle(
          style: DefaultTextStyle.of(context).style.merge(
                TextStyle(
                  fontSize: 17,
                  color: resolveSettingsPrimaryTextColor(context),
                ),
              ),
          softWrap: true,
          overflow: TextOverflow.visible,
          maxLines: null,
          child: title,
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: DefaultTextStyle(
              style: DefaultTextStyle.of(context).style.merge(
                    TextStyle(
                      fontSize: 13,
                      color: resolveSettingsSecondaryTextColor(context),
                    ),
                  ),
              softWrap: true,
              overflow: TextOverflow.visible,
              maxLines: null,
              child: subtitle!,
            ),
          ),
      ],
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
        color: CupertinoTheme.of(context).primaryColor,
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
