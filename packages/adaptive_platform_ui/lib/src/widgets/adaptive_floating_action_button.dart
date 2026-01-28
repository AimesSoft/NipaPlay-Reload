import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';

/// An adaptive floating action button that renders platform-specific styles
///
/// On iOS 26+: Uses circular button with native iOS 26 design and shadow
/// On iOS <26: Uses CupertinoButton with circular shape and shadow
/// On Android: Uses Material FloatingActionButton
///
/// Example:
/// ```dart
/// AdaptiveFloatingActionButton(
///   onPressed: () {
///     print('FAB pressed');
///   },
///   child: Icon(Icons.add),
/// )
/// ```
class AdaptiveFloatingActionButton extends StatelessWidget {
  /// Creates an adaptive floating action button
  const AdaptiveFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.mini = false,
    this.tooltip,
    this.heroTag,
  });

  /// The callback that is called when the button is tapped
  final VoidCallback? onPressed;

  /// The widget below this widget in the tree (typically an Icon)
  final Widget child;

  /// The background color of the button
  ///
  /// On iOS: Background color of the circular button
  /// On Android: Background color of the FAB
  final Color? backgroundColor;

  /// The foreground color of the button (typically icon color)
  ///
  /// On iOS: Icon color
  /// On Android: Icon color
  final Color? foregroundColor;

  /// The elevation of the button
  ///
  /// On iOS: Controls shadow intensity
  /// On Android: Material elevation
  final double? elevation;

  /// Whether to use a mini (smaller) floating action button
  final bool mini;

  /// Tooltip text for the button
  final String? tooltip;

  /// Hero tag for page transitions
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    // iOS implementation
    if (PlatformInfo.isIOS) {
      return _buildIOSButton(context);
    }

    // Android - Use Material FloatingActionButton
    if (PlatformInfo.isAndroid) {
      return _buildMaterialFAB(context);
    }

    // Fallback to Material
    return _buildMaterialFAB(context);
  }

  Widget _buildIOSButton(BuildContext context) {
    final defaultBackgroundColor =
        backgroundColor ?? CupertinoColors.systemBlue;
    final defaultForegroundColor = foregroundColor ?? CupertinoColors.white;
    final buttonSize = mini ? 40.0 : 56.0;
    final iconSize = mini ? 20.0 : 24.0;
    final shadowElevation = elevation ?? 6.0;

    Widget button = Container(
      width: buttonSize,
      height: buttonSize,
      decoration: BoxDecoration(
        color: defaultBackgroundColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: shadowElevation * 1.5,
            offset: Offset(0, shadowElevation / 2),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: IconTheme(
          data: IconThemeData(color: defaultForegroundColor, size: iconSize),
          child: child,
        ),
      ),
    );

    // Wrap with hero if tag is provided
    if (heroTag != null) {
      button = Hero(tag: heroTag!, child: button);
    }

    return button;
  }

  Widget _buildMaterialFAB(BuildContext context) {
    Widget fab;

    if (mini) {
      fab = FloatingActionButton.small(
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        elevation: elevation,
        tooltip: tooltip,
        heroTag: heroTag,
        child: child,
      );
    } else {
      fab = FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        elevation: elevation,
        tooltip: tooltip,
        heroTag: heroTag,
        child: child,
      );
    }

    return fab;
  }
}
