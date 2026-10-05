import 'dart:math' as math;

/// Centers a window without producing a negative upper bound for short lists.
int danmakuListWindowStart(int centerIndex, int itemCount, int windowSize) {
  return (centerIndex - windowSize ~/ 2)
      .clamp(0, math.max(0, itemCount - windowSize));
}
