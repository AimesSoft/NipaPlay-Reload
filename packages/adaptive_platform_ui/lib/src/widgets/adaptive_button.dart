import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';
import '../style/sf_symbol.dart';
import 'ios26/ios26_button.dart';

/// An adaptive button that renders platform-specific button styles
///
/// On iOS 26+: Uses native iOS 26 button design with modern styling
/// On iOS <26 (iOS 18 and below): Uses CupertinoButton with traditional iOS styling
/// On Android: Uses Material Design button (ElevatedButton or TextButton)
///
/// Example:
/// ```dart
/// AdaptiveButton(
///   onPressed: () {
///     print('Button pressed');
///   },
///   label: 'Click Me',
/// )
/// ```
class AdaptiveButton extends StatelessWidget {
  /// Creates an adaptive button with a text label
  const AdaptiveButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.color,
    this.textColor,
    this.style = AdaptiveButtonStyle.filled,
    this.size = AdaptiveButtonSize.medium,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.enabled = true,
    this.useSmoothRectangleBorder = true,
  }) : child = null,
       icon = null,
       iconColor = null,
       sfSymbol = null;

  /// Creates an adaptive button with a custom child widget
  const AdaptiveButton.child({
    super.key,
    required this.onPressed,
    required this.child,
    this.color,
    this.style = AdaptiveButtonStyle.filled,
    this.size = AdaptiveButtonSize.medium,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.enabled = true,
    this.useSmoothRectangleBorder = true,
  }) : label = null,
       textColor = null,
       icon = null,
       iconColor = null,
       sfSymbol = null;

  /// Creates an adaptive button with an icon
  const AdaptiveButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    this.color,
    this.iconColor,
    this.style = AdaptiveButtonStyle.filled,
    this.size = AdaptiveButtonSize.medium,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.enabled = true,
    this.useSmoothRectangleBorder = true,
  }) : label = null,
       textColor = null,
       child = null,
       sfSymbol = null;

  /// Creates an adaptive button with a native SF Symbol icon (iOS only)
  const AdaptiveButton.sfSymbol({
    super.key,
    required this.onPressed,
    required this.sfSymbol,
    this.color,
    this.style = AdaptiveButtonStyle.glass,
    this.size = AdaptiveButtonSize.medium,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.enabled = true,
    this.useSmoothRectangleBorder = true,
  }) : label = null,
       textColor = null,
       child = null,
       icon = null,
       iconColor = null;

  /// The callback that is called when the button is tapped
  final VoidCallback? onPressed;

  /// The text label of the button (used in default constructor)
  final String? label;

  /// The widget below this widget in the tree (used in .child constructor)
  final Widget? child;

  /// The icon to display (used in .icon constructor)
  final IconData? icon;

  /// The SF Symbol to display (used in .sfSymbol constructor)
  final SFSymbol? sfSymbol;

  /// The color of the button
  ///
  /// On iOS: Uses iOS system colors
  /// On Android: Uses Material theme colors
  final Color? color;

  /// The color of the button text (only for label mode)
  final Color? textColor;

  /// The color of the icon (only for icon mode)
  final Color? iconColor;

  /// The visual style of the button
  final AdaptiveButtonStyle style;

  /// The size preset for the button
  final AdaptiveButtonSize size;

  /// The amount of space to surround the child inside the button
  final EdgeInsetsGeometry? padding;

  /// The border radius of the button
  final BorderRadius? borderRadius;

  /// The minimum size of the button
  final Size? minSize;

  /// Whether the button is enabled
  final bool enabled;

  /// Whether to use smooth rectangle border (iOS 26+ only)
  /// When false, uses perfectly circular/capsule shape
  /// Default is true for smooth rectangle, set to false for circular
  final bool useSmoothRectangleBorder;

  @override
  Widget build(BuildContext context) {
    // iOS 26+ - Use native iOS 26 button design
    if (PlatformInfo.isIOS26OrHigher()) {
      // SF Symbol mode - use native SF Symbol rendering
      if (sfSymbol != null) {
        return IOS26Button.sfSymbol(
          onPressed: onPressed,
          sfSymbol: sfSymbol!,
          style: _mapToIOS26Style(style),
          size: _mapToIOS26Size(size),
          color: color,
          enabled: enabled,
          padding: padding,
          borderRadius: borderRadius,
          minSize: minSize,
          useSmoothRectangleBorder: useSmoothRectangleBorder,
        );
      }

      // Child mode - overlay widget on native button
      if (child != null) {
        return IOS26Button.child(
          onPressed: onPressed,
          style: _mapToIOS26Style(style),
          size: _mapToIOS26Size(size),
          color: color,
          enabled: enabled,
          padding: padding,
          borderRadius: borderRadius,
          minSize: minSize,
          useSmoothRectangleBorder: useSmoothRectangleBorder,
          child: child!,
        );
      }

      // Icon mode - use child mode with Icon widget
      if (icon != null) {
        return IOS26Button.child(
          onPressed: onPressed,
          style: _mapToIOS26Style(style),
          size: _mapToIOS26Size(size),
          color: color,
          enabled: enabled,
          padding: padding,
          borderRadius: borderRadius,
          minSize: minSize,
          useSmoothRectangleBorder: useSmoothRectangleBorder,
          child: Icon(icon, color: iconColor, size: 24),
        );
      }

      // Label mode
      return IOS26Button(
        onPressed: onPressed,
        label: label!,
        textColor: textColor,
        style: _mapToIOS26Style(style),
        size: _mapToIOS26Size(size),
        color: color,
        enabled: enabled,
        padding: padding,
        borderRadius: borderRadius,
        minSize: minSize,
        useSmoothRectangleBorder: useSmoothRectangleBorder,
      );
    }

    // iOS 18 and below - Use traditional CupertinoButton
    if (PlatformInfo.isIOS) {
      return _buildCupertinoButton(context);
    }

    // Android - Use Material Design button
    if (PlatformInfo.isAndroid) {
      return _buildMaterialButton(context);
    }

    // Fallback for other platforms (web, desktop, etc.)
    return _buildMaterialButton(context);
  }

  Widget _buildCupertinoButton(BuildContext context) {
    final buttonColor = color ?? CupertinoColors.systemBlue;
    final effectiveOnPressed = enabled ? onPressed : null;

    // Build child widget based on mode
    Widget buttonChild;
    if (sfSymbol != null) {
      // SF Symbol fallback - use CupertinoIcons or Icon
      buttonChild = Icon(
        CupertinoIcons.circle_fill, // Default fallback icon
        color: sfSymbol!.color,
        size: sfSymbol!.size,
      );
    } else if (icon != null) {
      buttonChild = Icon(icon, color: iconColor);
    } else if (child != null) {
      buttonChild = child!;
    } else {
      buttonChild = Text(label ?? '', style: TextStyle(color: textColor));
    }

    switch (style) {
      case AdaptiveButtonStyle.filled:
        return CupertinoButton.filled(
          onPressed: effectiveOnPressed,
          padding: padding,
          borderRadius:
              borderRadius ?? const BorderRadius.all(Radius.circular(8.0)),
          child: buttonChild,
        );

      case AdaptiveButtonStyle.plain:
        return CupertinoButton(
          onPressed: effectiveOnPressed,
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
          color: null,
          child: DefaultTextStyle(
            style: TextStyle(color: textColor ?? buttonColor),
            child: buttonChild,
          ),
        );

      case AdaptiveButtonStyle.glass:
      case AdaptiveButtonStyle.prominentGlass:
        // Cupertino doesn't have glass effects on old iOS, fallback to tinted
        return CupertinoButton(
          onPressed: effectiveOnPressed,
          padding: padding,
          borderRadius:
              borderRadius ?? const BorderRadius.all(Radius.circular(8.0)),
          color: buttonColor.withValues(alpha: 0.15),
          child: DefaultTextStyle(
            style: TextStyle(color: textColor ?? buttonColor),
            child: buttonChild,
          ),
        );

      default:
        // For other styles, use regular CupertinoButton with color
        return CupertinoButton(
          onPressed: effectiveOnPressed,
          padding: padding,
          borderRadius:
              borderRadius ?? const BorderRadius.all(Radius.circular(8.0)),
          color: buttonColor,
          child: buttonChild,
        );
    }
  }

  Widget _buildMaterialButton(BuildContext context) {
    final buttonColor = color ?? Theme.of(context).colorScheme.primary;
    final effectiveOnPressed = enabled ? onPressed : null;

    // Build child widget based on mode
    Widget buttonChild;
    if (sfSymbol != null) {
      // SF Symbol fallback - use Material Icons
      buttonChild = Icon(
        Icons.circle, // Default fallback icon
        color: sfSymbol!.color,
        size: sfSymbol!.size,
      );
    } else if (icon != null) {
      buttonChild = Icon(icon, color: iconColor);
    } else if (child != null) {
      buttonChild = child!;
    } else {
      buttonChild = Text(label ?? '');
    }

    switch (style) {
      case AdaptiveButtonStyle.filled:
        return ElevatedButton(
          onPressed: effectiveOnPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: buttonColor,
            foregroundColor: textColor ?? Colors.white,
            padding: padding ?? _getDefaultPadding(),
            minimumSize: minSize ?? Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius ?? BorderRadius.circular(8.0),
            ),
          ),
          child: buttonChild,
        );

      case AdaptiveButtonStyle.tinted:
        return FilledButton.tonal(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: buttonColor.withValues(alpha: 0.15),
            foregroundColor: buttonColor,
            padding: padding ?? _getDefaultPadding(),
            minimumSize: minSize ?? Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius ?? BorderRadius.circular(8.0),
            ),
          ),
          child: buttonChild,
        );

      case AdaptiveButtonStyle.bordered:
        return OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: buttonColor,
            side: BorderSide(color: buttonColor),
            padding: padding ?? _getDefaultPadding(),
            minimumSize: minSize ?? Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius ?? BorderRadius.circular(8.0),
            ),
          ),
          child: buttonChild,
        );

      case AdaptiveButtonStyle.plain:
        return TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(
            foregroundColor: buttonColor,
            padding: padding ?? _getDefaultPadding(),
            minimumSize: minSize ?? Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius ?? BorderRadius.circular(8.0),
            ),
          ),
          child: buttonChild,
        );

      case AdaptiveButtonStyle.gray:
        // Material doesn't have a direct "gray" style, use filled button with gray color
        return FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.grey.shade300,
            foregroundColor: Colors.grey.shade800,
            padding: padding ?? _getDefaultPadding(),
            minimumSize: minSize ?? Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius ?? BorderRadius.circular(8.0),
            ),
          ),
          child: buttonChild,
        );

      case AdaptiveButtonStyle.glass:
      case AdaptiveButtonStyle.prominentGlass:
        // Material doesn't have glass effects, fallback to tinted style
        return FilledButton.tonal(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: buttonColor.withValues(alpha: 0.15),
            foregroundColor: buttonColor,
            padding: padding ?? _getDefaultPadding(),
            minimumSize: minSize ?? Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius ?? BorderRadius.circular(8.0),
            ),
          ),
          child: buttonChild,
        );
    }
  }

  IOS26ButtonStyle _mapToIOS26Style(AdaptiveButtonStyle style) {
    switch (style) {
      case AdaptiveButtonStyle.filled:
        return IOS26ButtonStyle.filled;
      case AdaptiveButtonStyle.tinted:
        return IOS26ButtonStyle.tinted;
      case AdaptiveButtonStyle.gray:
        return IOS26ButtonStyle.gray;
      case AdaptiveButtonStyle.bordered:
        return IOS26ButtonStyle.bordered;
      case AdaptiveButtonStyle.plain:
        return IOS26ButtonStyle.plain;
      case AdaptiveButtonStyle.glass:
        return IOS26ButtonStyle.glass;
      case AdaptiveButtonStyle.prominentGlass:
        return IOS26ButtonStyle.prominentGlass;
    }
  }

  IOS26ButtonSize _mapToIOS26Size(AdaptiveButtonSize size) {
    switch (size) {
      case AdaptiveButtonSize.small:
        return IOS26ButtonSize.small;
      case AdaptiveButtonSize.medium:
        return IOS26ButtonSize.medium;
      case AdaptiveButtonSize.large:
        return IOS26ButtonSize.large;
    }
  }

  EdgeInsetsGeometry _getDefaultPadding() {
    switch (size) {
      case AdaptiveButtonSize.small:
        return const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0);
      case AdaptiveButtonSize.medium:
        return const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
      case AdaptiveButtonSize.large:
        return const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0);
    }
  }
}

/// Button style variants that adapt to each platform
enum AdaptiveButtonStyle {
  /// Solid filled button (primary action)
  filled,

  /// Tinted/tonal button with subtle background
  tinted,

  /// Gray button with neutral appearance
  gray,

  /// Outlined/bordered button
  bordered,

  /// Plain text button
  plain,

  /// Glass effect button (iOS 26+ only)
  glass,

  /// Prominent glass button (iOS 26+ only)
  prominentGlass,
}

/// Button size presets
enum AdaptiveButtonSize {
  /// Small button (28pt height on iOS)
  small,

  /// Medium button (36pt height on iOS) - default
  medium,

  /// Large button (44pt height on iOS)
  large,
}
