import 'package:flutter/material.dart';

typedef ContextMenuSurfaceBuilder = Widget Function(
  BuildContext context,
  ContextMenuStyle style,
  Size size,
  Widget child,
);

@immutable
class ContextMenuStyle {
  final double width;
  final double itemHeight;
  final double borderRadius;
  final EdgeInsets itemPadding;
  final double iconSize;
  final Color iconColor;
  final TextStyle labelStyle;
  final Color disabledForegroundColor;
  final Color hoverColor;
  final Color highlightColor;
  final ContextMenuSurfaceBuilder surfaceBuilder;

  const ContextMenuStyle({
    required this.surfaceBuilder,
    required this.width,
    required this.itemHeight,
    required this.borderRadius,
    required this.itemPadding,
    required this.iconSize,
    required this.iconColor,
    required this.labelStyle,
    required this.disabledForegroundColor,
    required this.hoverColor,
    required this.highlightColor,
  });

  Size menuSize(int actionCount) {
    return Size(width, itemHeight * actionCount);
  }
}

@immutable
class ContextMenuAction {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  const ContextMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });
}

class ContextMenu extends StatelessWidget {
  final ContextMenuStyle style;
  final List<ContextMenuAction> actions;
  final VoidCallback? onDismiss;

  const ContextMenu({
    super.key,
    required this.style,
    required this.actions,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final size = style.menuSize(actions.length);

    final content = SizedBox(
      width: size.width,
      height: size.height,
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < actions.length; i++)
              _ContextMenuActionTile(
                style: style,
                action: actions[i],
                onDismiss: onDismiss,
                showDivider: i != actions.length - 1,
              ),
          ],
        ),
      ),
    );

    return style.surfaceBuilder(context, style, size, content);
  }
}

class _ContextMenuActionTile extends StatelessWidget {
  final ContextMenuStyle style;
  final ContextMenuAction action;
  final VoidCallback? onDismiss;
  final bool showDivider;

  const _ContextMenuActionTile({
    required this.style,
    required this.action,
    required this.onDismiss,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final foregroundColor =
        action.enabled ? style.labelStyle.color : style.disabledForegroundColor;
    final iconColor = action.enabled ? style.iconColor : style.disabledForegroundColor;
    final textStyle = foregroundColor == null
        ? style.labelStyle
        : style.labelStyle.copyWith(color: foregroundColor);

    final Color baseDividerColor = style.labelStyle.color ?? Colors.black;
    final Color dividerColor = baseDividerColor.withValues(
      alpha: (baseDividerColor.a * 0.16).clamp(0.0, 1.0),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: dividerColor,
                  width: 0.6,
                ),
              )
            : null,
      ),
      child: SizedBox(
        width: double.infinity,
        height: style.itemHeight,
        child: InkWell(
          onTap: action.enabled
              ? () {
                  onDismiss?.call();
                  action.onPressed();
                }
              : null,
          hoverColor: style.hoverColor,
          highlightColor: style.highlightColor,
          child: Padding(
            padding: style.itemPadding,
            child: Row(
              children: [
                Icon(action.icon, size: style.iconSize, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    action.label,
                    style: textStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
