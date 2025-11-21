import 'package:flutter/cupertino.dart';

import 'package:nipaplay/utils/cupertino_settings_colors.dart';

/// Reusable Cupertino-styled settings group card with rounded corners.
class CupertinoSettingsGroupCard extends StatelessWidget {
  const CupertinoSettingsGroupCard({
    super.key,
    required this.children,
    this.margin,
    this.backgroundColor,
    this.addDividers = false,
    this.dividerIndent = 20,
  });

  /// Children within the card, typically Cupertino-styled list tiles.
  final List<Widget> children;

  /// Optional margin; defaults to symmetric horizontal 20 padding.
  final EdgeInsetsGeometry? margin;

  /// Optional background color override.
  final Color? backgroundColor;

  /// Whether to automatically insert separators between children.
  final bool addDividers;

  /// Left-side indent for the auto-inserted separator line.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final Color resolvedBackground =
        backgroundColor ?? resolveSettingsSectionBackground(context);
    final BorderRadius borderRadius = BorderRadius.circular(24);

    final List<Widget> content = addDividers && children.length > 1
        ? _withDividers(context)
        : children;

    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: resolvedBackground,
          borderRadius: borderRadius,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: content,
          ),
        ),
      ),
    );
  }

  List<Widget> _withDividers(BuildContext context) {
    final List<Widget> result = [];
    final Color dividerColor = resolveSettingsSeparatorColor(context);

    for (var i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(
          Container(
            height: 0.5,
            margin: EdgeInsetsDirectional.only(start: dividerIndent),
            color: dividerColor,
          ),
        );
      }
    }
    return result;
  }
}
