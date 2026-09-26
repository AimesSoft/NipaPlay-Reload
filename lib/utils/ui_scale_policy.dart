import 'dart:math' as math;
import 'dart:ui' show Size;

class UiScalePolicy {
  static const min = 0.5;
  static const max = 1.3;
  static const step = 0.05;

  /// Match NipaPlay's desktop-sized controls to a TV's actual output. Up to
  /// 1080p, compensate for Android's logical density in this layout; above 1080p,
  /// retain the same content density instead of making 4K controls tiny.
  /// Physical PPI and viewing distance are not reliably available from Android.
  static double forTelevisionDisplay({
    required Size physicalSize,
    required double devicePixelRatio,
  }) {
    if (!physicalSize.width.isFinite ||
        !physicalSize.height.isFinite ||
        physicalSize.isEmpty ||
        !devicePixelRatio.isFinite ||
        devicePixelRatio <= 0) {
      return 1.0;
    }
    final resolutionScale = math.max(
      1.0,
      math.max(
          physicalSize.longestSide / 1920, physicalSize.shortestSide / 1080),
    );
    final scale = (resolutionScale / devicePixelRatio).clamp(min, max);
    return ((scale / step).round() * step).clamp(min, max).toDouble();
  }
}
