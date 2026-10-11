import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Static film grain over the whole surface (concept `.grain`: overlay, 7%).
///
/// One noise tile is generated once per process and drawn as a repeating
/// shader, one noise texel per physical pixel.
class Grain extends StatefulWidget {
  const Grain({super.key, this.opacity = 0.07});
  final double opacity;

  @override
  State<Grain> createState() => _GrainState();
}

class _GrainState extends State<Grain> {
  static Future<ui.Image>? _tile;
  ui.Image? _image;

  static Future<ui.Image> _makeTile() {
    const n = 256;
    final random = Random(7);
    final pixels = Uint8List(n * n * 4);
    // Two octaves of value noise keep it from looking like pure static.
    final coarse =
        List<double>.generate((n ~/ 2) * (n ~/ 2), (_) => random.nextDouble());
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final fine = random.nextDouble();
        final c = coarse[(y ~/ 2) * (n ~/ 2) + (x ~/ 2)];
        final v = ((fine * 0.62 + c * 0.38) * 255).round().clamp(0, 255);
        final i = (y * n + x) * 4;
        pixels[i] = v;
        pixels[i + 1] = v;
        pixels[i + 2] = v;
        pixels[i + 3] = 255;
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        pixels, n, n, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  @override
  void initState() {
    super.initState();
    (_tile ??= _makeTile()).then((image) {
      if (mounted) setState(() => _image = image);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.expand();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _GrainPainter(
              image, widget.opacity, MediaQuery.devicePixelRatioOf(context)),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.image, this.opacity, this.dpr);
  final ui.Image image;
  final double opacity;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = Float64List.fromList([
      1 / dpr, 0, 0, 0, //
      0, 1 / dpr, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
    final paint = Paint()
      ..shader = ui.ImageShader(
          image, TileMode.repeated, TileMode.repeated, scale,
          filterQuality: FilterQuality.none)
      ..blendMode = BlendMode.overlay
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.image != image || old.opacity != opacity || old.dpr != dpr;
}
