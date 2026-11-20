import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nipaplay/utils/video_frame_image.dart';

void main() {
  test('thumbnail worker handles encoded frames and keeps aspect ratio',
      () async {
    final image = img.Image(width: 960, height: 540);
    img.fill(image, color: img.ColorRgb8(200, 60, 30));
    for (final bytes in [img.encodePng(image), img.encodeJpg(image)]) {
      final result = await compute(
          encodeVideoThumbnail,
          VideoFrameImageRequest(
              bytes: Uint8List.fromList(bytes), width: 960, height: 540));
      final decoded = img.decodeJpg(result!)!;
      expect(decoded.width, lessThanOrEqualTo(480));
      expect(decoded.height, 240);
      expect(decoded.width / decoded.height, closeTo(16 / 9, .01));
      expect(decoded.getPixel(0, 0).r, greaterThan(180));
    }
  });
  test('raw RGBA and BGRA with row padding preserve color and force alpha', () {
    for (final bgra in [false, true]) {
      final bytes = Uint8List.fromList(bgra
          ? [30, 60, 200, 0, 0, 0, 0, 0, 30, 60, 200, 0, 0, 0, 0, 0]
          : [200, 60, 30, 0, 0, 0, 0, 0, 200, 60, 30, 0, 0, 0, 0, 0]);
      final decoded = decodeVideoFrameImage(VideoFrameImageRequest(
          bytes: bytes, width: 1, height: 2, bgra: bgra))!;
      expect(decoded.getPixel(0, 1).r, 200);
      expect(decoded.getPixel(0, 1).b, 30);
      expect(decoded.getPixel(0, 1).a, 255);
      expect(bytes[3], 0,
          reason: 'native snapshot bytes must remain untouched');
    }
  });
  test('fallback dimensions, black frames and corrupt data retain behavior',
      () {
    final bytes = Uint8List.fromList([255, 0, 0, 0]);
    expect(
        encodeVideoThumbnail(VideoFrameImageRequest(
            bytes: bytes,
            width: 0,
            height: 0,
            sourceWidth: 1,
            sourceHeight: 1)),
        isNotNull);
    expect(
        encodeVideoThumbnail(
            VideoFrameImageRequest(bytes: Uint8List(16), width: 2, height: 2)),
        isNull);
    expect(
        encodeVideoThumbnail(
            VideoFrameImageRequest(bytes: Uint8List(3), width: 2, height: 2)),
        isNull);
  });
}
