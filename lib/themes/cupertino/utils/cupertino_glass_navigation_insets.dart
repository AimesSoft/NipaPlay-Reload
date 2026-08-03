const double _glassTabBarEdgeGap = 6.0;
const double _pageActionsEdgeGap = 12.0;
const double _nativeIOS26PageActionsExtraTrailingGap = 16.0;

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
/// Native iOS 26 Liquid Glass chrome extends farther toward the screen edge
/// than the fallback toolbar, so it needs a little more visual breathing room.
double resolvePageActionsTrailingOffset({
  required double viewPaddingRight,
  required bool usesNativeIOS26Toolbar,
}) {
  return viewPaddingRight +
      _pageActionsEdgeGap +
      (usesNativeIOS26Toolbar ? _nativeIOS26PageActionsExtraTrailingGap : 0);
}
