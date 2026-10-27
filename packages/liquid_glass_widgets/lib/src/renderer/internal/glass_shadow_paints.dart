import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Paints for the glass layer's shadow pass, reused across frames.
///
/// The layer repaints on every transform change (scroll, drag, jelly scale),
/// while its shadows rarely change, so the tint/blur paints are rebuilt only
/// when the shadow values do.
class GlassShadowPaints {
  List<BoxShadow> _shadows = const [];
  List<Paint> _paints = const [];

  /// Punches the glass interior out of its own shadow.
  final Paint cutoutPaint = Paint()..blendMode = BlendMode.dstOut;

  /// One paint per shadow, in order. Returns the same list while the shadow
  /// values are unchanged.
  List<Paint> resolve(List<BoxShadow> shadows) {
    if (listEquals(shadows, _shadows)) return _paints;
    _shadows = List.unmodifiable(shadows);
    _paints = List.unmodifiable([
      for (final shadow in shadows)
        Paint()
          ..colorFilter = ColorFilter.mode(shadow.color, BlendMode.srcIn)
          ..imageFilter = ImageFilter.blur(
            sigmaX: shadow.blurSigma,
            sigmaY: shadow.blurSigma,
            tileMode: TileMode.decal,
          ),
    ]);
    return _paints;
  }
}
