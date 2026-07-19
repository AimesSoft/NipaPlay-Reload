import 'package:flutter/cupertino.dart';
import '../../src/renderer/liquid_glass_renderer.dart';

import '../../theme/glass_theme_data.dart';
import '../../types/glass_quality.dart';
import '../shared/adaptive_liquid_glass_layer.dart';

/// Position of the badge relative to the child widget.
enum BadgePosition {
  /// Top right corner (default for notification counts)
  topRight,

  /// Top left corner
  topLeft,

  /// Bottom right corner
  bottomRight,

  /// Bottom left corner
  bottomLeft,
}

/// A glass morphism badge following iOS 26 liquid glass design.
///
/// [GlassBadge] provides notification count or status dot indicators with:
/// - iOS 26 liquid glass backdrop effect
/// - Count badge with automatic sizing (1-2 digits small, 3+ wider)
/// - Dot badge for status indicators (online, active, etc.)
/// - Four position variants (topRight, topLeft, bottomRight, bottomLeft)
/// - Auto-hide when count is 0
/// - Theme-aware colors
/// - Customizable size and colors
///
/// ## Usage
///
/// ### Count Badge (Notification)
/// ```dart
/// GlassBadge(
///   count: 5,
///   child: GlassIconButton(
///     icon: CupertinoIcons.bell,
///     onTap: () => showNotifications(),
///   ),
/// )
/// ```
///
/// ### Dot Badge (Status Indicator)
/// ```dart
/// GlassBadge.dot(
///   color: Colors.green, // Online status
///   child: CircleAvatar(
///     backgroundImage: NetworkImage('https://...'),
///   ),
/// )
/// ```
///
/// ### Custom Position
/// ```dart
/// GlassBadge(
///   count: 12,
///   position: BadgePosition.topLeft,
///   child: Icon(Icons.mail),
/// )
/// ```
///
/// ### Custom Colors
/// ```dart
/// GlassBadge(
///   count: 3,
///   backgroundColor: Colors.blue,
///   textColor: CupertinoColors.white,
///   child: Icon(Icons.message),
/// )
/// ```
///
/// ### Auto-hide when Zero
/// ```dart
/// GlassBadge(
///   count: unreadCount, // Hides when 0
///   child: Icon(Icons.inbox),
/// )
/// ```
///
/// ## iOS 26 Design Principles
///
/// - **Circular morphology**: Perfect circle for dots, pill for counts
/// - **Liquid glass backdrop**: Subtle glass effect on badge
/// - **Semantic colors**: Red for notifications, custom for status
/// - **Smart positioning**: Overlays child without obscuring content
/// - **Adaptive sizing**: Badge grows with digit count
/// - **Visibility**: Only shows when count > 0 or explicitly shown
class GlassBadge extends StatelessWidget {
  /// Creates a badge with a count number.
  const GlassBadge({
    required this.child,
    super.key,
    this.count = 0,
    this.position = BadgePosition.topRight,
    this.backgroundColor,
    this.textColor,
    this.settings,
    this.quality,
    this.showZero = false,
    this.maxCount = 99,
  })  : isDot = false,
        dotColor = null;

  /// Creates a dot badge (status indicator).
  ///
  /// Use for online/offline status, active state indicators, etc.
  ///
  /// Example:
  /// ```dart
  /// GlassBadge.dot(
  ///   color: Colors.green,
  ///   position: BadgePosition.bottomRight,
  ///   child: Avatar(...),
  /// )
  /// ```
  const GlassBadge.dot({
    required this.child,
    super.key,
    this.dotColor = CupertinoColors.systemGreen,
    this.position = BadgePosition.topRight,
    this.settings,
    this.quality,
  })  : isDot = true,
        count = 0,
        backgroundColor = null,
        textColor = null,
        showZero = false,
        maxCount = 99;

  /// The widget to display the badge on top of
  final Widget child;

  /// Whether this is a dot badge (status indicator)
  final bool isDot;

  /// The count to display in the badge
  ///
  /// If 0 and [showZero] is false, the badge is hidden.
  final int count;

  /// Position of the badge relative to the child
  final BadgePosition position;

  /// Background color of the badge
  ///
  /// Defaults to red for count badges (iOS notification style).
  final Color? backgroundColor;

  /// Text color for the count
  ///
  /// Defaults to white.
  final Color? textColor;

  /// Color of the dot badge
  ///
  /// Only used for [GlassBadge.dot].
  final Color? dotColor;

  /// Whether to show the badge when count is 0
  ///
  /// Defaults to false (badge hidden when count is 0).
  final bool showZero;

  /// Maximum count to display
  ///
  /// If count exceeds this, displays "99+" (or maxCount+).
  /// Defaults to 99.
  final int maxCount;

  /// Custom glass settings (overrides theme)
  final LiquidGlassSettings? settings;

  /// Rendering quality (overrides theme)
  final GlassQuality? quality;

  @override
  Widget build(BuildContext context) {
    // Don't show count badge if count is 0 and showZero is false
    if (!isDot && count == 0 && !showZero) {
      return child;
    }

    // Build the semantic label for the badge overlay.
    // - Count badges: "5 notifications" (matches iOS badge VoiceOver)
    // - Dot badges: "Active" (status indicator)
    final String badgeLabel = isDot
        ? 'Active'
        : (count > maxCount
            ? '$maxCount+ notifications'
            : '$count notifications');

    return Semantics(
      label: badgeLabel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: _getTopPosition(),
            right: _getRightPosition(),
            bottom: _getBottomPosition(),
            left: _getLeftPosition(),
            // Badge visual is decorative — the parent Semantics node above
            // carries the label, so exclude the badge widget itself.
            child: ExcludeSemantics(
              child:
                  isDot ? _buildDotBadge(context) : _buildCountBadge(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(BuildContext context) {
    final themeData = GlassThemeData.of(context);
    final glowColors = themeData.glowColorsFor(context);

    final bgColor =
        backgroundColor ?? glowColors.danger ?? const Color(0xFFFF3B30);
    final fgColor = textColor ?? CupertinoColors.white;

    // Format count display
    final String displayText =
        count > maxCount ? '$maxCount+' : count.toString();

    // Determine size based on digit count
    final bool isWide = count > 9 || count > maxCount;
    final double minWidth = isWide ? 20.0 : 18.0;
    final double horizontalPadding = isWide ? 6.0 : 0.0;

    return AdaptiveLiquidGlassLayer(
      settings: settings ??
          const LiquidGlassSettings(
            thickness: 20.0,
            blur: 4.0,
            refractiveIndex: 1.1,
            saturation: 1.2,
          ),
      quality: quality,
      child: Container(
        constraints: BoxConstraints(
          minWidth: minWidth,
          minHeight: 18.0,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 2.0,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: CupertinoColors.white.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: bgColor.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Text(
          displayText,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fgColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildDotBadge(BuildContext context) {
    final color = dotColor ?? CupertinoColors.systemGreen;

    return AdaptiveLiquidGlassLayer(
      settings: settings ??
          const LiquidGlassSettings(
            thickness: 15.0,
            blur: 3.0,
            refractiveIndex: 1.1,
            saturation: 1.2,
          ),
      quality: quality,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: CupertinoColors.white,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  double? _getTopPosition() {
    switch (position) {
      case BadgePosition.topRight:
      case BadgePosition.topLeft:
        return isDot ? -2 : -6;
      case BadgePosition.bottomRight:
      case BadgePosition.bottomLeft:
        return null;
    }
  }

  double? _getRightPosition() {
    switch (position) {
      case BadgePosition.topRight:
      case BadgePosition.bottomRight:
        return isDot ? -2 : -6;
      case BadgePosition.topLeft:
      case BadgePosition.bottomLeft:
        return null;
    }
  }

  double? _getBottomPosition() {
    switch (position) {
      case BadgePosition.topRight:
      case BadgePosition.topLeft:
        return null;
      case BadgePosition.bottomRight:
      case BadgePosition.bottomLeft:
        return isDot ? -2 : -6;
    }
  }

  double? _getLeftPosition() {
    switch (position) {
      case BadgePosition.topRight:
      case BadgePosition.bottomRight:
        return null;
      case BadgePosition.topLeft:
      case BadgePosition.bottomLeft:
        return isDot ? -2 : -6;
    }
  }
}
