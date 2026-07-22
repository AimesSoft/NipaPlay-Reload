const double _glassTabBarEdgeGap = 6.0;

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
