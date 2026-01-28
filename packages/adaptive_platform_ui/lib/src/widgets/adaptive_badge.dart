import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';

/// An adaptive badge that renders platform-specific badge styles
///
/// On iOS: Uses custom iOS-style badge with Cupertino design
/// On Android: Uses Material Design Badge
///
/// Example:
/// ```dart
/// AdaptiveBadge(
///   count: 5,
///   child: Icon(Icons.notifications),
/// )
/// ```
class AdaptiveBadge extends StatelessWidget {
  /// Creates an adaptive badge
  const AdaptiveBadge({
    super.key,
    this.count,
    this.label,
    this.backgroundColor,
    this.textColor,
    this.showZero = false,
    this.isLarge = false,
    this.alignment,
    this.offset,
    required this.child,
  }) : assert(
         count != null || label != null,
         'Either count or label must be provided',
       );

  /// The count to display in the badge
  ///
  /// If null, [label] must be provided
  final int? count;

  /// The label text to display in the badge
  ///
  /// If null, [count] will be used
  final String? label;

  /// The background color of the badge
  ///
  /// Defaults to red on both platforms
  final Color? backgroundColor;

  /// The text color of the badge
  ///
  /// Defaults to white on both platforms
  final Color? textColor;

  /// Whether to show the badge when count is 0
  ///
  /// Defaults to false
  final bool showZero;

  /// Whether to use a larger badge size
  ///
  /// Defaults to false
  final bool isLarge;

  /// The alignment of the badge relative to the child
  ///
  /// Defaults to top-end alignment
  final AlignmentGeometry? alignment;

  /// The offset of the badge from its default position
  final Offset? offset;

  /// The widget to display the badge on
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Don't show badge if count is 0 and showZero is false
    if (count != null && count == 0 && !showZero) {
      return child;
    }

    // Display "99+" for counts greater than 99
    final displayText =
        label ??
        (count != null ? (count! > 99 ? '99+' : count!.toString()) : '');

    // iOS - Use custom iOS-style badge
    if (PlatformInfo.isIOS) {
      return _IOSBadge(
        displayText: displayText,
        backgroundColor: backgroundColor ?? CupertinoColors.systemRed,
        textColor: textColor ?? CupertinoColors.white,
        isLarge: isLarge,
        alignment: alignment,
        offset: offset,
        child: child,
      );
    }

    // Android - Use Material Design Badge
    if (PlatformInfo.isAndroid) {
      return Badge(
        label: Text(displayText),
        backgroundColor: backgroundColor,
        textColor: textColor,
        isLabelVisible: true,
        alignment: alignment ?? AlignmentDirectional.topEnd,
        offset: offset,
        largeSize: isLarge ? 24 : null,
        child: child,
      );
    }

    // Fallback for other platforms (web, desktop, etc.)
    return Badge(
      label: Text(displayText),
      backgroundColor: backgroundColor,
      textColor: textColor,
      isLabelVisible: true,
      alignment: alignment ?? AlignmentDirectional.topEnd,
      offset: offset,
      largeSize: isLarge ? 24 : null,
      child: child,
    );
  }
}

/// iOS-style badge widget
class _IOSBadge extends StatelessWidget {
  const _IOSBadge({
    required this.displayText,
    required this.backgroundColor,
    required this.textColor,
    required this.isLarge,
    required this.alignment,
    required this.offset,
    required this.child,
  });

  final String displayText;
  final Color backgroundColor;
  final Color textColor;
  final bool isLarge;
  final AlignmentGeometry? alignment;
  final Offset? offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final badgeSize = isLarge ? 24.0 : 18.0;
    final fontSize = isLarge ? 13.0 : 11.0;
    final minWidth = isLarge ? 24.0 : 18.0;

    // Calculate badge position
    final badgeAlignment = alignment ?? Alignment.topRight;
    final badgeOffset = offset ?? const Offset(-4, 4);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top:
              badgeAlignment == Alignment.topRight ||
                  badgeAlignment == Alignment.topLeft
              ? badgeOffset.dy
              : null,
          bottom:
              badgeAlignment == Alignment.bottomRight ||
                  badgeAlignment == Alignment.bottomLeft
              ? -badgeOffset.dy
              : null,
          right:
              badgeAlignment == Alignment.topRight ||
                  badgeAlignment == Alignment.bottomRight
              ? badgeOffset.dx
              : null,
          left:
              badgeAlignment == Alignment.topLeft ||
                  badgeAlignment == Alignment.bottomLeft
              ? -badgeOffset.dx
              : null,
          child: Container(
            constraints: BoxConstraints(
              minWidth: minWidth,
              minHeight: badgeSize,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: displayText.length > 1 ? 6 : 0,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(badgeSize / 2),
            ),
            child: Center(
              child: Text(
                displayText,
                style: TextStyle(
                  color: textColor,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
