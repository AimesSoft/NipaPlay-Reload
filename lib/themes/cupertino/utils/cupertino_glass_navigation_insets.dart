import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/system_window_traits.dart';

const double _glassTabBarEdgeGap = 6.0;
const double _pageActionsEdgeGap = 12.0;
const double _ios27PageActionsExtraTrailingGap = 16.0;
const double _sideNavigationEdgeGap = 6.0;
const double _sidePageActionsTopGap = 4.0;

/// Height required by the fallback glass tab bar's icon-and-label layout.
const double cupertinoGlassTabBarHeight = 64.0;

/// Resolves the bottom offset for the floating liquid-glass tab bar.
///
/// Keeps the entire system navigation inset unobstructed and adds a small,
/// consistent visual gap on every platform using the Flutter fallback.
double resolveGlassTabBarBottomOffset({
  required double viewPaddingBottom,
}) {
  return viewPaddingBottom + _glassTabBarEdgeGap;
}

/// Resolves the trailing offset for the floating page-action toolbar.
///
/// iOS 27 Liquid Glass chrome extends farther toward the screen edge than the
/// other toolbar implementations, so only that release gets an extra inset.
double resolvePageActionsTrailingOffset({
  required double viewPaddingRight,
  required int iosMajorVersion,
}) {
  return viewPaddingRight +
      _pageActionsEdgeGap +
      (iosMajorVersion == 27 ? _ios27PageActionsExtraTrailingGap : 0);
}

/// Placement of the phone chrome when the system puts bars on the side of the
/// window (iPhone Duo).
///
/// Apple's iPhone Duo guidelines move toolbars and the tab bar into one
/// vertical column along the bar edge: toolbar items at the top, under the
/// camera and status bar, and the tab bar aligned to the bottom. Controls line
/// up with the camera, and content stays outside the column so the controls
/// never cover it.
@immutable
class CupertinoSideNavigationLayout {
  const CupertinoSideNavigationLayout({
    required this.placement,
    required this.columnWidth,
    required this.controlsCenterOffset,
    required this.tabBarBottom,
    required this.pageActionsTop,
  });

  final PhoneNavigationPlacement placement;

  /// Width reserved along the bar edge, measured from the window edge.
  final double columnWidth;

  /// Distance from the bar edge to the line the controls are centered on.
  final double controlsCenterOffset;

  final double tabBarBottom;
  final double pageActionsTop;

  bool get isLeft => placement == PhoneNavigationPlacement.left;

  EdgeInsets get contentPadding => isLeft
      ? EdgeInsets.only(left: columnWidth)
      : EdgeInsets.only(right: columnWidth);

  /// Distance from the bar edge to a control of [width] on the center line.
  double edgeOffsetFor(double width) => controlsCenterOffset - width / 2;
}

/// Returns the side column layout, or null when bars belong at the bottom.
///
/// [occlusions] are the system's reserved regions in window coordinates. Those
/// overlapping the column (camera, status bar) push the controls away from the
/// top or bottom, and the narrowest one inside it sets the center line.
CupertinoSideNavigationLayout? resolveSideNavigationLayout({
  required PhoneNavigationPlacement placement,
  required Size windowSize,
  required EdgeInsets viewPadding,
  required List<Rect> occlusions,
  required double barWidth,
}) {
  if (!placement.isVertical) return null;
  final isLeft = placement == PhoneNavigationPlacement.left;
  final edgeInset = isLeft ? viewPadding.left : viewPadding.right;
  final columnWidth =
      math.max(edgeInset, barWidth + _sideNavigationEdgeGap * 2);
  final columnLeft = isLeft ? 0.0 : windowSize.width - columnWidth;
  final columnRight = columnLeft + columnWidth;
  var topClearance = viewPadding.top;
  var bottomClearance = viewPadding.bottom;
  for (final region in occlusions) {
    if (region.right <= columnLeft || region.left >= columnRight) continue;
    if (region.center.dy < windowSize.height / 2) {
      topClearance = math.max(topClearance, region.bottom);
    } else {
      bottomClearance =
          math.max(bottomClearance, windowSize.height - region.top);
    }
  }

  const tolerance = 0.5;
  var controlsCenterOffset = columnWidth / 2;
  final columnOcclusions = occlusions
      .where((region) =>
          region.left >= columnLeft - tolerance &&
          region.right <= columnRight + tolerance)
      .toList(growable: false);
  if (columnOcclusions.isNotEmpty) {
    // The system aligns its side controls with the camera, the narrowest
    // region in the column.
    final camera =
        columnOcclusions.reduce((a, b) => a.width <= b.width ? a : b);
    final cameraCenter =
        isLeft ? camera.center.dx : windowSize.width - camera.center.dx;
    final minCenter = barWidth / 2 + _sideNavigationEdgeGap;
    controlsCenterOffset = cameraCenter.clamp(
      minCenter,
      math.max(minCenter, columnWidth - minCenter),
    );
  }

  return CupertinoSideNavigationLayout(
    placement: placement,
    columnWidth: columnWidth,
    controlsCenterOffset: controlsCenterOffset,
    tabBarBottom: resolveGlassTabBarBottomOffset(
      viewPaddingBottom: bottomClearance,
    ),
    pageActionsTop: topClearance + _sidePageActionsTopGap,
  );
}
