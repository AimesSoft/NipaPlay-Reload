import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/src/platform/platform_info.dart';

/// A platform-adaptive expansion tile widget that provides expandable/collapsible content.
///
/// - On iOS: Creates a custom Cupertino-style expansion tile with chevron icon
/// - On Android: Uses Material [ExpansionTile] widget
///
/// Example:
/// ```dart
/// AdaptiveExpansionTile(
///   title: Text('Section Title'),
///   children: [
///     Text('Item 1'),
///     Text('Item 2'),
///   ],
/// )
/// ```
class AdaptiveExpansionTile extends StatefulWidget {
  const AdaptiveExpansionTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
    this.onExpansionChanged,
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.tilePadding,
    this.childrenPadding,
    this.backgroundColor,
    this.collapsedBackgroundColor,
    this.textColor,
    this.collapsedTextColor,
    this.iconColor,
    this.collapsedIconColor,
    this.shape,
    this.collapsedShape,
    this.enabled = true,
    this.clipBehavior = Clip.none,
    this.expandedAlignment,
    this.expandedCrossAxisAlignment,
  });

  /// A widget to display before the title.
  final Widget? leading;

  /// The primary content of the list item.
  final Widget title;

  /// Additional content displayed below the title.
  final Widget? subtitle;

  /// A widget to display after the title instead of the default expansion arrow.
  final Widget? trailing;

  /// The widgets that are displayed when the tile expands.
  final List<Widget> children;

  /// Called when the tile expands or collapses.
  final ValueChanged<bool>? onExpansionChanged;

  /// Specifies if the list tile is initially expanded (true) or collapsed (false, the default).
  final bool initiallyExpanded;

  /// Specifies whether the state of the children is maintained when the tile expands and collapses.
  final bool maintainState;

  /// The tile's internal padding.
  final EdgeInsetsGeometry? tilePadding;

  /// Specifies padding for [children].
  final EdgeInsetsGeometry? childrenPadding;

  /// The background color of the tile when expanded.
  final Color? backgroundColor;

  /// The background color of the tile when collapsed.
  final Color? collapsedBackgroundColor;

  /// The color of the tile's titles when expanded.
  final Color? textColor;

  /// The color of the tile's titles when collapsed.
  final Color? collapsedTextColor;

  /// The color of the tile's expansion icon when expanded.
  final Color? iconColor;

  /// The color of the tile's expansion icon when collapsed.
  final Color? collapsedIconColor;

  /// The tile's border shape when expanded.
  final ShapeBorder? shape;

  /// The tile's border shape when collapsed.
  final ShapeBorder? collapsedShape;

  /// Whether the tile is interactive.
  final bool enabled;

  /// The content will be clipped (or not) according to this option.
  final Clip clipBehavior;

  /// Specifies the alignment of [children], which are arranged in a column when
  /// the tile is expanded.
  final Alignment? expandedAlignment;

  /// Specifies the alignment of each child within [children] when the tile is expanded.
  final CrossAxisAlignment? expandedCrossAxisAlignment;

  @override
  State<AdaptiveExpansionTile> createState() => _AdaptiveExpansionTileState();
}

class _AdaptiveExpansionTileState extends State<AdaptiveExpansionTile>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _animationController;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _iconTurns = _animationController.drive(
      Tween<double>(
        begin: 0.0,
        end: 0.25,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
    );
    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.enabled) return;

    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
    widget.onExpansionChanged?.call(_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isIOS) {
      return _buildIOSExpansionTile(context);
    }
    return _buildMaterialExpansionTile(context);
  }

  Widget _buildIOSExpansionTile(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    final effectiveBackgroundColor = _isExpanded
        ? (widget.backgroundColor ??
              (isDark
                  ? CupertinoColors.systemGrey6.darkColor
                  : CupertinoColors.systemBackground))
        : (widget.collapsedBackgroundColor ??
              (isDark
                  ? CupertinoColors.systemGrey6.darkColor
                  : CupertinoColors.systemBackground));

    final effectiveTextColor = _isExpanded
        ? (widget.textColor ?? CupertinoColors.label.resolveFrom(context))
        : (widget.collapsedTextColor ??
              CupertinoColors.label.resolveFrom(context));

    final effectiveIconColor = _isExpanded
        ? (widget.iconColor ?? CupertinoColors.systemGrey.resolveFrom(context))
        : (widget.collapsedIconColor ??
              CupertinoColors.systemGrey.resolveFrom(context));

    final effectiveTilePadding =
        widget.tilePadding ??
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0);

    final effectiveChildrenPadding =
        widget.childrenPadding ??
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: effectiveBackgroundColor,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isDark
              ? CupertinoColors.systemGrey4.darkColor
              : CupertinoColors.systemGrey5.color,
          width: 0.5,
        ),
        boxShadow: _isExpanded
            ? [
                BoxShadow(
                  color:
                      (isDark
                              ? CupertinoColors.black
                              : CupertinoColors.systemGrey)
                          .withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 12.0,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color:
                      (isDark
                              ? CupertinoColors.black
                              : CupertinoColors.systemGrey)
                          .withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 4.0,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              onPressed: widget.enabled ? _handleTap : null,
              padding: EdgeInsets.zero,
              child: Container(
                padding: effectiveTilePadding,
                child: Row(
                  children: [
                    if (widget.leading != null) ...[
                      Container(
                        width: 32.0,
                        height: 32.0,
                        decoration: BoxDecoration(
                          color: effectiveIconColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Center(
                          child: DefaultTextStyle(
                            style: TextStyle(color: effectiveTextColor),
                            child: IconTheme(
                              data: IconThemeData(
                                color: effectiveIconColor,
                                size: 20.0,
                              ),
                              child: widget.leading!,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12.0),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DefaultTextStyle(
                            style: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .copyWith(
                                  color: effectiveTextColor,
                                  fontSize: 17.0,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.4,
                                ),
                            child: widget.title,
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 3.0),
                            DefaultTextStyle(
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .copyWith(
                                    color: CupertinoColors.secondaryLabel
                                        .resolveFrom(context),
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: -0.2,
                                  ),
                              child: widget.subtitle!,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    if (widget.trailing != null)
                      DefaultTextStyle(
                        style: TextStyle(color: effectiveTextColor),
                        child: IconTheme(
                          data: IconThemeData(color: effectiveIconColor),
                          child: widget.trailing!,
                        ),
                      )
                    else
                      Container(
                        width: 28.0,
                        height: 28.0,
                        decoration: BoxDecoration(
                          color: effectiveIconColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: RotationTransition(
                            turns: _iconTurns,
                            child: Icon(
                              CupertinoIcons.chevron_right,
                              color: effectiveIconColor,
                              size: 16.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Separator line when expanded
            if (_isExpanded)
              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 16.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      (isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.separator)
                          .resolveFrom(context)
                          .withValues(alpha: 0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ClipRect(
              clipBehavior: widget.clipBehavior,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                child: _isExpanded
                    ? Padding(
                        padding: effectiveChildrenPadding,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment:
                              widget.expandedCrossAxisAlignment ??
                              CrossAxisAlignment.center,
                          children: widget.children,
                        ),
                      )
                    : const SizedBox(width: double.infinity, height: 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialExpansionTile(BuildContext context) {
    return ExpansionTile(
      key: widget.key,
      leading: widget.leading,
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: widget.trailing,
      onExpansionChanged: widget.onExpansionChanged,
      initiallyExpanded: widget.initiallyExpanded,
      maintainState: widget.maintainState,
      tilePadding: widget.tilePadding,
      childrenPadding: widget.childrenPadding,
      backgroundColor: widget.backgroundColor,
      collapsedBackgroundColor: widget.collapsedBackgroundColor,
      textColor: widget.textColor,
      collapsedTextColor: widget.collapsedTextColor,
      iconColor: widget.iconColor,
      collapsedIconColor: widget.collapsedIconColor,
      shape: widget.shape,
      collapsedShape: widget.collapsedShape,
      clipBehavior: widget.clipBehavior,
      expandedAlignment: widget.expandedAlignment,
      expandedCrossAxisAlignment: widget.expandedCrossAxisAlignment,
      children: widget.children,
    );
  }
}
