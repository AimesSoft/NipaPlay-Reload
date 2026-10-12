import 'dart:typed_data';
import 'package:image/image.dart' as img;

img.Image _decode(List<int> bytes) =>
    img.decodeImage(Uint8List.fromList(bytes)) ??
    (throw const FormatException('Artwork is not a supported raster image.'));

Future<void> validateRaster(List<int> bytes) async {
  _decode(bytes);
}

Future<int> rasterTint(List<int> bytes) async {
  final image = img.copyResize(_decode(bytes), width: 64);
  final bins = <int, List<int>>{};
  for (final p in image) {
    if (p.a < 128) continue;
    final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
    final bucket = bins.putIfAbsent(
        (r >> 4) << 8 | (g >> 4) << 4 | b >> 4, () => [0, 0, 0, 0]);
    bucket[0]++;
    bucket[1] += r;
    bucket[2] += g;
    bucket[3] += b;
  }
  if (bins.isEmpty) return 0xff000000;
  final dominant = bins.values.reduce((a, b) => a[0] >= b[0] ? a : b);
  return 0xff000000 |
      (dominant[1] ~/ dominant[0]) << 16 |
      (dominant[2] ~/ dominant[0]) << 8 |
      dominant[3] ~/ dominant[0];
}
