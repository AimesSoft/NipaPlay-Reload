import 'dart:ui';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/renderer/internal/glass_shadow_paints.dart';

void main() {
  test('unchanged shadows reuse paints with identical filter parameters', () {
    final cache = GlassShadowPaints();
    const shadow = BoxShadow(color: Color(0x55000000), blurRadius: 8);
    final first = cache.resolve([shadow]);
    final sameValues = cache.resolve([
      const BoxShadow(color: Color(0x55000000), blurRadius: 8),
    ]);
    expect(sameValues, same(first));
    expect(first.single.colorFilter,
        const ColorFilter.mode(Color(0x55000000), BlendMode.srcIn));
    expect(
        first.single.imageFilter,
        ImageFilter.blur(
            sigmaX: shadow.blurSigma,
            sigmaY: shadow.blurSigma,
            tileMode: TileMode.decal));
    expect(cache.cutoutPaint.blendMode, BlendMode.dstOut);
    expect(
        cache.resolve([shadow.copyWith(blurRadius: 12)]), isNot(same(first)));
    expect(cache.resolve([]), isEmpty);
  });
}
