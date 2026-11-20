import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nipaplay/utils/screenshot_encoding.dart';

void main() {
  final image = img.Image(width: 96, height: 64);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, (x * 37 + y * 13) % 256, (x * 19 + y * 47) % 256,
          (x * 73 + y * 31) % 256);
    }
  }

  test('PNG screenshots preserve all pixels and use matching file metadata',
      () {
    final bytes = encodeScreenshotImage(image,
        format: ScreenshotFormat.png, jpegQuality: 70);
    final decoded = img.decodePng(bytes)!;
    expect(decoded.width, image.width);
    expect(decoded.height, image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final original = image.getPixel(x, y);
        final result = decoded.getPixel(x, y);
        expect([result.r, result.g, result.b],
            [original.r, original.g, original.b]);
      }
    }
    expect(ScreenshotFormat.png.extension, 'png');
    expect(ScreenshotFormat.png.mimeType, 'image/png');
  });

  test('JPEG quality changes actual file size while preserving dimensions', () {
    final standard = encodeScreenshotImage(image,
        format: ScreenshotFormat.jpeg, jpegQuality: 70);
    final maximum = encodeScreenshotImage(image,
        format: ScreenshotFormat.jpeg, jpegQuality: 100);
    expect(standard.length, lessThan(maximum.length));
    for (final bytes in [standard, maximum]) {
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.width, image.width);
      expect(decoded.height, image.height);
    }
    expect(ScreenshotFormat.jpeg.extension, 'jpg');
    expect(ScreenshotFormat.jpeg.mimeType, 'image/jpeg');
  });

  test('existing settings retain JPEG until PNG is selected', () {
    expect(ScreenshotFormat.fromPreference(null), ScreenshotFormat.jpeg);
    expect(ScreenshotFormat.fromPreference('unknown'), ScreenshotFormat.jpeg);
    expect(ScreenshotFormat.fromPreference('png'), ScreenshotFormat.png);
  });
}
