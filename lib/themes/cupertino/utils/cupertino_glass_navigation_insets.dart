const double _glassTabBarEdgeGap = 6.0;
const double _pageActionsEdgeGap = 12.0;
const double _ios27PageActionsExtraTrailingGap = 16.0;

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
