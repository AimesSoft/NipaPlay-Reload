import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/tmdb_logo_brightness.dart';
import 'package:nipaplay/services/tmdb_logo_inspector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('transparent canvas does not darken white ink or brighten black ink',
      () {
    final white = measureTmdbLogoBrightness(Uint8List.fromList([
      for (var i = 0; i < 1000; i++) ...[0, 0, 0, 0],
      255,
      255,
      255,
      255,
    ]));
    final black = measureTmdbLogoBrightness(Uint8List.fromList([
      for (var i = 0; i < 1000; i++) ...[255, 255, 255, 0],
      0,
      0,
      0,
      255,
    ]));
    expect(white?.isBright, isTrue);
    expect(black?.isBright, isFalse);
    expect(white?.luminance, closeTo(1, 0.00001));
  });
  test(
      'bright colors and light gray remain readable, invisible pixels do not count',
      () {
    expect(
        measureTmdbLogoBrightness(Uint8List.fromList([255, 0, 0, 255]))
            ?.isBright,
        isTrue);
    expect(
        measureTmdbLogoBrightness(Uint8List.fromList([220, 220, 220, 255]))
            ?.isBright,
        isTrue);
    expect(measureTmdbLogoBrightness(Uint8List.fromList([255, 255, 255, 10])),
        isNull);
    expect(
        TmdbLogoBrightness.fromJson(
            {'luminance': double.nan, 'brightFraction': 1}),
        isNull);
  });
  for (final white in [false, true]) {
    test(
        'actual transparent PNG ${white ? "white" : "black"} logo is classified',
        () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
          const ui.Rect.fromLTWH(5, 5, 40, 10),
          ui.Paint()
            ..color = white
                ? const ui.Color(0xffffffff)
                : const ui.Color(0xff000000));
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 24);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final result = await inspectTmdbLogoBytes(png!.buffer.asUint8List());
      expect(result?.isBright, white);
      image.dispose();
      picture.dispose();
    });
    test('SVG ${white ? "white" : "black"} logo is evaluated after rendering',
        () async {
      final svg =
          '<svg xmlns="http://www.w3.org/2000/svg" width="640" height="240"><rect x="50" y="50" width="400" height="100" fill="${white ? "#ffffff" : "#000000"}"/></svg>';
      final result = await inspectTmdbLogoBytes(
          Uint8List.fromList(utf8.encode(svg)),
          svg: true);
      expect(result?.isBright, white);
    });
  }
}
