import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart'
    show AdaptiveSwitch;
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_player_menu_components.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tvos_remote_text_input_scope.dart';

/// Shared presentation primitives for the phone player-menu renderer.
///
/// The bottom sheet already supplies the glass surface, title, and navigation.
/// Sections therefore stay unframed instead of nesting another rounded card.
class AdaptivePlayerMenuSection extends StatelessWidget {
  const AdaptivePlayerMenuSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 12),
  });

  final List<Widget> children;
  final Widget? header;
  final Widget? footer;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
      return NipaplayLargeScreenPlayerMenuSection(
        header: header,
        footer: footer,
        margin: margin,
        children: children,
      );
    }

    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    final headerStyle = CupertinoTheme.of(context).textTheme.textStyle.copyWith(
          color: secondaryColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        );
    final footerStyle = headerStyle.copyWith(
      color: CupertinoColors.tertiaryLabel.resolveFrom(context),
      fontWeight: FontWeight.normal,
    );

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 7),
              child: DefaultTextStyle(style: headerStyle, child: header!),
            ),
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const GlassDivider(indent: 16, endIndent: 16),
          ],
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 0),
              child: DefaultTextStyle(style: footerStyle, child: footer!),
            ),
        ],
      ),
    );
  }
}

class AdaptivePlayerMenuTile extends StatelessWidget {
  const AdaptivePlayerMenuTile({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.additionalInfo,
    this.trailing,
    this.onTap,
    this.padding,
  });

  final Widget title;
  final Widget? leading;
  final Widget? subtitle;
  final Widget? additionalInfo;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    Widget? effectiveTrailing = trailing;
    if (additionalInfo != null) {
      effectiveTrailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DefaultTextStyle(
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  fontSize: 14,
                ),
            child: additionalInfo!,
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      );
    }

    if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
      return NipaplayLargeScreenPlayerMenuTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        additionalInfo: additionalInfo,
        trailing: trailing,
        onActivate: onTap,
        padding: padding,
      );
    }

    return GlassListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: effectiveTrailing,
      onTap: onTap,
      contentPadding:
          padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    );
  }
}

/// Switch presentation shared by every player-menu pane.
///
/// The television renderer uses the real Fluent UI toggle so the focused
/// control has the same shape and interaction semantics as settings. Phone
/// and desktop surfaces keep their existing adaptive platform switch.
class AdaptivePlayerMenuSwitch extends StatelessWidget {
  const AdaptivePlayerMenuSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
      return FluentSettingsSwitch(value: value, onChanged: onChanged);
    }
    return AdaptiveSwitch(value: value, onChanged: onChanged);
  }
}

/// A generic tappable surface used by timeline and playlist rows that are not
/// shaped like a conventional settings tile.
class AdaptivePlayerMenuActionSurface extends StatelessWidget {
  const AdaptivePlayerMenuActionSurface({
    super.key,
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
      return NipaplayLargeScreenPlayerMenuActionSurface(
        onActivate: onTap,
        padding: EdgeInsets.zero,
        margin: EdgeInsets.zero,
        child: child,
      );
    }
    return GestureDetector(onTap: onTap, child: child);
  }
}

/// Marks a danmaku-list action so the television menu can resolve its initial
/// focus from the rows that are actually laid out in the current viewport.
class AdaptivePlayerMenuDanmakuListRow extends StatelessWidget {
  const AdaptivePlayerMenuDanmakuListRow({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
      return NipaplayLargeScreenPlayerMenuDanmakuRow(child: child);
    }
    return child;
  }
}

class AdaptivePlayerMenuTextField extends StatelessWidget {
  const AdaptivePlayerMenuTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isTelevision = useTvOSRemoteTextInput(context);
    final field = GlassTextField(
      controller: controller,
      focusNode: isTelevision ? null : focusNode,
      placeholder: placeholder,
      prefixIcon: prefix,
      suffixIcon: suffix,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly || isTelevision,
      autofocus: isTelevision ? false : autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      padding: padding,
      useOwnLayer: true,
      quality: GlassQuality.standard,
    );
    if (!isTelevision) return field;
    return TvOSRemoteTextInputControl(
      focusNode: focusNode,
      title: placeholder,
      maxLength: maxLength,
      obscureText: obscureText,
      autofocus: autofocus,
      child: field,
    );
  }
}

class AdaptivePlayerMenuProgressIndicator extends StatelessWidget {
  const AdaptivePlayerMenuProgressIndicator({
    super.key,
    this.size = 20,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return GlassProgressIndicator.circular(
      size: size,
      useOwnLayer: false,
      quality: GlassQuality.standard,
    );
  }
}
