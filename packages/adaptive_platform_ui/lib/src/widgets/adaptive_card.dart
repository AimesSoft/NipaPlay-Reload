import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';

/// An adaptive card that renders platform-specific card styles
///
/// On iOS: Uses custom iOS-style card with Cupertino design
/// On Android: Uses Material Design Card
///
/// Example:
/// ```dart
/// AdaptiveCard(
///   child: Padding(
///     padding: EdgeInsets.all(16),
///     child: Text('Card Content'),
///   ),
/// )
/// ```
class AdaptiveCard extends StatelessWidget {
  /// Creates an adaptive card
  const AdaptiveCard({
    super.key,
    this.color,
    this.elevation,
    this.shape,
    this.borderOnForeground = true,
    this.margin,
    this.clipBehavior,
    this.semanticContainer = true,
    required this.child,
    this.padding,
    this.borderRadius,
  });

  /// The card's background color
  ///
  /// On iOS: Uses the color directly
  /// On Android: Uses the color for the Material widget
  final Color? color;

  /// The z-coordinate at which to place this card
  ///
  /// This controls the size of the shadow below the card on Android.
  /// On iOS, this parameter is ignored as iOS cards use borders instead.
  final double? elevation;

  /// The shape of the card's Material on Android
  ///
  /// On iOS, this parameter is ignored
  final ShapeBorder? shape;

  /// Whether to paint the shape border in front of the child on Android
  ///
  /// On iOS, this parameter is ignored
  final bool borderOnForeground;

  /// The empty space that surrounds the card
  final EdgeInsetsGeometry? margin;

  /// The content will be clipped (or not) according to this option
  ///
  /// Defaults to [Clip.none] on iOS and uses Material defaults on Android
  final Clip? clipBehavior;

  /// Whether this widget represents a single semantic container
  final bool semanticContainer;

  /// The widget below this widget in the tree
  final Widget child;

  /// Internal padding for the card content
  ///
  /// If null, no padding is applied
  final EdgeInsetsGeometry? padding;

  /// Border radius for the card
  ///
  /// On iOS: Uses this radius for the card corners
  /// On Android: Uses this if shape is not provided
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    // iOS - Use custom iOS-style card
    if (PlatformInfo.isIOS) {
      return _IOSCard(
        color: color,
        margin: margin,
        clipBehavior: clipBehavior ?? Clip.none,
        semanticContainer: semanticContainer,
        borderRadius: borderRadius,
        child: content,
      );
    }

    // Android - Use Material Design Card
    if (PlatformInfo.isAndroid) {
      return Card(
        color: color,
        elevation: elevation,
        shape:
            shape ??
            (borderRadius != null
                ? RoundedRectangleBorder(borderRadius: borderRadius!)
                : null),
        borderOnForeground: borderOnForeground,
        margin: margin,
        clipBehavior: clipBehavior,
        semanticContainer: semanticContainer,
        child: content,
      );
    }

    // Fallback for other platforms (web, desktop, etc.)
    return Card(
      color: color,
      elevation: elevation,
      shape:
          shape ??
          (borderRadius != null
              ? RoundedRectangleBorder(borderRadius: borderRadius!)
              : null),
      borderOnForeground: borderOnForeground,
      margin: margin,
      clipBehavior: clipBehavior,
      semanticContainer: semanticContainer,
      child: content,
    );
  }
}

/// iOS-style card widget
class _IOSCard extends StatelessWidget {
  const _IOSCard({
    required this.color,
    required this.margin,
    required this.clipBehavior,
    required this.semanticContainer,
    required this.borderRadius,
    required this.child,
  });

  final Color? color;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;
  final bool semanticContainer;
  final BorderRadius? borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    // Default iOS card background color
    final backgroundColor =
        color ??
        (isDark ? CupertinoColors.darkBackgroundGray : CupertinoColors.white);

    // Default border radius
    final radius = borderRadius ?? BorderRadius.circular(12);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: radius,
        border: Border.all(
          color: isDark
              ? CupertinoColors.systemGrey6
              : CupertinoColors.separator,
          width: 0.5,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: CupertinoColors.systemGrey.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: semanticContainer
            ? Semantics(container: true, child: child)
            : child,
      ),
    );
  }
}
