import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:nipaplay/models/tmdb_logo_brightness.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';

/// Inspects the very same cached rendition that the detail page will display.
/// No second thumbnail request and no modification of the original artwork.
Future<TmdbLogoBrightness?> inspectCachedTmdbLogo(String url) async {
  final bytes = await ImageCacheManager.instance.loadImageBytes(url);
  final uri = Uri.parse(url);
  final path = Uri.tryParse(uri.queryParameters['url'] ?? url)?.path ?? '';
  return inspectTmdbLogoBytes(bytes, svg: path.toLowerCase().endsWith('.svg'));
}

Future<TmdbLogoBrightness?> inspectTmdbLogoBytes(Uint8List bytes,
    {bool svg = false}) async {
  ui.Image? image;
  try {
    if (svg) {
      final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
      try {
        if (info.size.isEmpty) return null;
        final scale = math.min(128 / info.size.width, 128 / info.size.height);
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
          ..scale(scale)
          ..drawPicture(info.picture);
        final picture = recorder.endRecording();
        try {
          image = await picture.toImage(
              (info.size.width * scale).ceil().clamp(1, 128),
              (info.size.height * scale).ceil().clamp(1, 128));
        } finally {
          picture.dispose();
        }
      } finally {
        info.picture.dispose();
      }
    } else {
      final codec = await ui.instantiateImageCodec(bytes,
          targetWidth: 128, allowUpscaling: false);
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }
    final rgba =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    return rgba == null
        ? null
        : measureTmdbLogoBrightness(
            rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes));
  } finally {
    image?.dispose();
  }
}
