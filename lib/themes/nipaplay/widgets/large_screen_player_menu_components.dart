import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

const double kNipaplayLargeScreenPlayerMenuSidebarWidth = 256;

/// Identifies an actionable danmaku-list row inside the large-screen menu.
///
/// The list is lazily built and may begin with a partially clipped row after
/// it jumps to the current playback time. The menu panel uses this marker to
/// choose the first fully visible row when focus enters the content region.
class NipaplayLargeScreenPlayerMenuDanmakuRow extends StatelessWidget {
  const NipaplayLargeScreenPlayerMenuDanmakuRow({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Reusable presentation primitives for player settings shown on a television.
///
/// The player-menu panes keep owning their data and operations. These widgets
/// only define the large-screen layout and focus affordances so every renderer
/// can share the same remote-friendly behaviour.
class NipaplayLargeScreenPlayerMenuSection extends StatelessWidget {
  const NipaplayLargeScreenPlayerMenuSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.margin = const EdgeInsets.fromLTRB(18, 10, 18, 18),
  });

  final List<Widget> children;
  final Widget? header;
  final Widget? footer;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final secondary = colorScheme.onSurface.withValues(alpha: 0.62);
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: secondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                child: header!,
              ),
            ),
          ...children,
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: secondary, fontSize: 12),
                child: footer!,
              ),
            ),
        ],
      ),
    );
  }
}

class NipaplayLargeScreenPlayerMenuActionSurface extends StatelessWidget {
  const NipaplayLargeScreenPlayerMenuActionSurface({
    super.key,
    required this.child,
    this.onActivate,
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    this.margin = const EdgeInsets.only(bottom: 8),
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.focusScale = 1.008,
  });

  final Widget child;
  final VoidCallback? onActivate;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;
  final double focusScale;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.current;
    return Padding(
      padding: margin,
      child: NipaplayLargeScreenFocusableAction(
        focusNode: focusNode,
        autofocus: autofocus,
        onActivate: onActivate,
        borderRadius: borderRadius,
        focusScale: focusScale,
        padding: padding,
        style: NipaplayLargeScreenFocusableStyle(
          idleBackgroundDark: selected
              ? accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.08),
          idleBackgroundLight: selected
              ? accent.withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.055),
        ),
        child: child,
      ),
    );
  }
}

class NipaplayLargeScreenPlayerMenuTile extends StatelessWidget {
  const NipaplayLargeScreenPlayerMenuTile({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.additionalInfo,
    this.trailing,
    this.onActivate,
    this.focusNode,
    this.selected = false,
    this.padding,
  });

  final Widget title;
  final Widget? leading;
  final Widget? subtitle;
  final Widget? additionalInfo;
  final Widget? trailing;
  final VoidCallback? onActivate;
  final FocusNode? focusNode;
  final bool selected;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final secondary =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          child: title,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          DefaultTextStyle.merge(
            style: TextStyle(color: secondary, fontSize: 12.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            child: subtitle!,
          ),
        ],
      ],
    );

    return NipaplayLargeScreenPlayerMenuActionSurface(
      focusNode: focusNode,
      onActivate: onActivate,
      selected: selected,
      padding: padding ?? const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          if (leading != null) ...[
            IconTheme.merge(
              data: const IconThemeData(size: 22),
              child: leading!,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(child: text),
          if (additionalInfo != null) ...[
            const SizedBox(width: 12),
            DefaultTextStyle.merge(
              style: TextStyle(
                color: secondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              child: additionalInfo!,
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class NipaplayLargeScreenPlayerMenuTab extends StatelessWidget {
  const NipaplayLargeScreenPlayerMenuTab({
    super.key,
    required this.icon,
    required this.title,
    required this.category,
    required this.selected,
    required this.focused,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String category;
  final bool selected;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppAccentColors.current;
    final active = selected || focused;
    final foreground =
        active ? Colors.white : (isDark ? Colors.white70 : Colors.black54);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color:
                active ? accent.withValues(alpha: focused ? 0.92 : 0.56) : null,
            border: Border(
              left: BorderSide(
                color: selected ? accent : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 21, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.68),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.chevron_right_rounded, size: 20, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class NipaplayLargeScreenPlayerMenuChip extends StatelessWidget {
  const NipaplayLargeScreenPlayerMenuChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return NipaplayLargeScreenPlayerMenuActionSurface(
      selected: selected,
      onActivate: onPressed,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class NipaplayLargeScreenPlayerMenuIconButton extends StatelessWidget {
  const NipaplayLargeScreenPlayerMenuIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: NipaplayLargeScreenPlayerMenuActionSurface(
        onActivate: onPressed,
        focusScale: 1.06,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(9),
        child: Icon(icon, size: 20),
      ),
    );
  }
}
