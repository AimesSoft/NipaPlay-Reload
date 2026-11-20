import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum ScreenshotFormat {
  jpeg('jpg', 'image/jpeg', 'JPEG（体积较小）'),
  png('png', 'image/png', 'PNG（无损）');

  const ScreenshotFormat(this.extension, this.mimeType, this.label);

  final String extension;
  final String mimeType;
  final String label;

  static ScreenshotFormat fromPreference(String? value) =>
      ScreenshotFormat.values.firstWhere(
        (format) => format.name == value,
        orElse: () => ScreenshotFormat.jpeg,
      );
}

Uint8List encodeScreenshotImage(
  img.Image image, {
  required ScreenshotFormat format,
  required int jpegQuality,
}) =>
    switch (format) {
      ScreenshotFormat.jpeg => img.encodeJpg(image, quality: jpegQuality),
      ScreenshotFormat.png => img.encodePng(image),
    };
