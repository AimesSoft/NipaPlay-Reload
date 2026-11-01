import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/apple_native_media_control.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

enum MediaDetailActionEmphasis { primary, secondary }

/// Actions used by the immersive media detail page.
///
/// Uses native Apple Liquid Glass on supported devices and keeps the existing
/// NipaPlay overlay on other platforms.
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

  static bool get supportsNativeLiquidGlass =>
      AppleNativeMediaControl.supported;

  static bool useNativeLiquidGlass(BuildContext context) {
    final enabled = context
            .watch<AppearanceSettingsProvider?>()
            ?.enableMediaDetailLiquidGlass ??
        true;
    return supportsNativeLiquidGlass && enabled;
  }

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

    if (AdaptiveMediaDetailActionButton.useNativeLiquidGlass(context)) {
      const labelStyle = TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );
      final detailStyle = TextStyle(
        fontSize: 11,
        color: Colors.white.withValues(alpha: 0.78),
      );
      double textWidth(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      final labelWidth = textWidth(widget.label, labelStyle);
      final detailWidth = textWidth(widget.detail ?? '', detailStyle);
      final width = (labelWidth > detailWidth ? labelWidth : detailWidth) + 72;
      return SizedBox(
        width: widget.expanded
            ? double.infinity
            : width.clamp(80.0, MediaQuery.sizeOf(context).width - 32),
        child: AppleNativeMediaControl(
          label: widget.label,
          detail: widget.detail,
          symbol: switch (widget.label) {
            '返回' => 'chevron.left',
            '评论' => 'bubble.right',
            '选择剧集' => 'list.bullet',
            _ => 'play.fill',
          },
          primary: primary,
          color: primary ? accent : null,
          onPressed: widget.onPressed,
        ),
      );
    }

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
