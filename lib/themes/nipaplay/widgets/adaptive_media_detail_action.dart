import 'package:flutter/material.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

enum MediaDetailActionEmphasis { primary, secondary }

/// Actions used by the immersive media detail page.
///
/// NipaPlay currently has no bridge to Apple's native Liquid Glass controls.
/// The bundled cross-platform shader implementation is deliberately not used
/// here: unsupported platforms render the same lightweight NipaPlay overlay.
class AdaptiveMediaDetailActionButton extends StatefulWidget {
  const AdaptiveMediaDetailActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.detail,
    this.emphasis = MediaDetailActionEmphasis.secondary,
    this.expanded = false,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onPressed;
  final MediaDetailActionEmphasis emphasis;
  final bool expanded;

  static bool get supportsNativeLiquidGlass => false;

  @override
  State<AdaptiveMediaDetailActionButton> createState() =>
      _AdaptiveMediaDetailActionButtonState();
}

class _AdaptiveMediaDetailActionButtonState
    extends State<AdaptiveMediaDetailActionButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final active = enabled && (_hovered || _focused);
    final primary = widget.emphasis == MediaDetailActionEmphasis.primary;
    final accent = AppAccentColors.current;
    final foreground =
        enabled ? Colors.white : Colors.white.withValues(alpha: 0.42);
    final background = primary
        ? accent.withValues(alpha: active ? 1 : 0.92)
        : Colors.black.withValues(alpha: active ? 0.48 : 0.32);
    final border = primary
        ? accent.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: active ? 0.3 : 0.18);

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.symmetric(
        horizontal: primary ? 20 : 17,
        vertical: widget.detail == null ? 12 : 9,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
        boxShadow: primary && active
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 22, color: foreground),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.detail?.isNotEmpty == true)
                  Text(
                    widget.detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.78),
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        child: FocusableActionDetector(
          enabled: enabled,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(10),
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.white.withValues(alpha: 0.08),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class AdaptiveMediaDetailIconButton extends StatelessWidget {
  const AdaptiveMediaDetailIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AdaptiveMediaDetailActionButton(
        icon: icon,
        label: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
