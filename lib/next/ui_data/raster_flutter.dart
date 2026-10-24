import 'dart:typed_data';
import 'dart:ui' as ui;
import 'raster_io.dart' as background;

Future<void> validateRaster(List<int> bytes) async {
  if (ui.RootIsolateToken.instance == null) return background.validateRaster(bytes);
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  codec.dispose();
}

Future<int> rasterTint(List<int> bytes) async {
  if (ui.RootIsolateToken.instance == null) return background.rasterTint(bytes);
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes),
      targetWidth: 64);
  final frame = await codec.getNextFrame();
  final data =
      (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final bins = <int, List<int>>{};
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i + 3) < 128) continue;
    final r = data.getUint8(i),
        g = data.getUint8(i + 1),
        b = data.getUint8(i + 2);
    final bucket = bins.putIfAbsent(
        (r >> 4) << 8 | (g >> 4) << 4 | b >> 4, () => [0, 0, 0, 0]);
    bucket[0]++;
    bucket[1] += r;
    bucket[2] += g;
    bucket[3] += b;
  }
  frame.image.dispose();
  codec.dispose();
  if (bins.isEmpty) return 0xff000000;
  final dominant = bins.values.reduce((a, b) => a[0] >= b[0] ? a : b);
  return 0xff000000 |
      (dominant[1] ~/ dominant[0]) << 16 |
      (dominant[2] ~/ dominant[0]) << 8 |
      dominant[3] ~/ dominant[0];
}
