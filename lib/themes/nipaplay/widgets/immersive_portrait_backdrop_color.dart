import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_backdrop_focus.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';

const Color immersivePortraitFallbackColor = Color(0xFF10131D);

class ImmersiveBackdropAppearance {
  const ImmersiveBackdropAppearance(this.alignment, this.color);

  final Alignment alignment;
  final Color color;
}

/// Samples the edge of the *visible* cover crop, rather than the bottom of the
/// source image (which may be cropped away on a narrow portrait screen).
Future<Color> extractImmersivePortraitBackdropColor(
  ui.Image image,
  Size viewport, {
  Alignment alignment = Alignment.center,
}) async {
  if (viewport.width <= 0 || viewport.height <= 0) {
    return immersivePortraitFallbackColor;
  }
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return immersivePortraitFallbackColor;

  final sourceWidth = image.width;
  final sourceHeight = image.height;
  final sourceAspect = sourceWidth / sourceHeight;
  final viewportAspect = viewport.width / viewport.height;
  final visibleWidth = sourceAspect > viewportAspect
      ? sourceHeight * viewportAspect
      : sourceWidth.toDouble();
  final visibleHeight = sourceAspect > viewportAspect
      ? sourceHeight.toDouble()
      : sourceWidth / viewportAspect;
  final left = (sourceWidth - visibleWidth) * (alignment.x + 1) / 2;
  final top = (sourceHeight - visibleHeight) * (alignment.y + 1) / 2;
  final xStart = left.floor().clamp(0, sourceWidth - 1);
  final xEnd = (left + visibleWidth).ceil().clamp(xStart + 1, sourceWidth);
  final yStart =
      (top + visibleHeight * 0.84).floor().clamp(0, sourceHeight - 1);
  final yEnd = (top + visibleHeight).ceil().clamp(yStart + 1, sourceHeight);

  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;
  var weightSum = 0.0;
  const hueBucketCount = 12;
  final hueWeights = List<double>.filled(hueBucketCount, 0);
  final hueReds = List<double>.filled(hueBucketCount, 0);
  final hueGreens = List<double>.filled(hueBucketCount, 0);
  final hueBlues = List<double>.filled(hueBucketCount, 0);
  for (var y = yStart; y < yEnd; y++) {
    for (var x = xStart; x < xEnd; x++) {
      final offset = (y * sourceWidth + x) * 4;
      final alpha = bytes.getUint8(offset + 3) / 255;
      if (alpha < 0.1) continue;
      final pixelRed = bytes.getUint8(offset);
      final pixelGreen = bytes.getUint8(offset + 1);
      final pixelBlue = bytes.getUint8(offset + 2);
      red += pixelRed * alpha;
      green += pixelGreen * alpha;
      blue += pixelBlue * alpha;
      weightSum += alpha;

      final pixel = HSLColor.fromColor(
        Color.fromARGB(255, pixelRed, pixelGreen, pixelBlue),
      );
      if (pixel.saturation < 0.22 || pixel.lightness < 0.08) continue;
      final bucket = (pixel.hue / 30).floor() % hueBucketCount;
      final colorWeight = alpha * pixel.saturation;
      hueWeights[bucket] += colorWeight;
      hueReds[bucket] += pixelRed * colorWeight;
      hueGreens[bucket] += pixelGreen * colorWeight;
      hueBlues[bucket] += pixelBlue * colorWeight;
    }
  }
  if (weightSum == 0) return immersivePortraitFallbackColor;

  final average = Color.fromARGB(
    255,
    (red / weightSum).round(),
    (green / weightSum).round(),
    (blue / weightSum).round(),
  );
  var bestBucket = 0;
  for (var index = 1; index < hueBucketCount; index++) {
    if (hueWeights[index] > hueWeights[bestBucket]) bestBucket = index;
  }
  // A sizeable chromatic region keeps a multicolour poster from averaging to
  // muddy grey. Neutral artwork continues to use its real average colour.
  final sampled = hueWeights[bestBucket] >= weightSum * 0.08
      ? Color.fromARGB(
          255,
          (hueReds[bestBucket] / hueWeights[bestBucket]).round(),
          (hueGreens[bestBucket] / hueWeights[bestBucket]).round(),
          (hueBlues[bestBucket] / hueWeights[bestBucket]).round(),
        )
      : average;
  return toneImmersivePortraitBackdropColor(sampled);
}

/// Keeps even semi-transparent secondary labels readable on the solid fill.
/// The floor is based on the page's faintest substantive white text (68%).
Color toneImmersivePortraitBackdropColor(Color sampled) {
  final hsl = HSLColor.fromColor(sampled);
  // Keep white labels readable while retaining the poster's hue. Near-neutral
  // artwork stays neutral instead of acquiring an arbitrary red hue.
  final saturation =
      hsl.saturation < 0.08 ? hsl.saturation : hsl.saturation.clamp(0.4, 0.86);
  var lightness = hsl.lightness.clamp(0.18, 0.29).toDouble();
  Color toned() =>
      hsl.withSaturation(saturation).withLightness(lightness).toColor();

  var background = toned();
  while (lightness > 0.06 &&
      immersivePortraitSecondaryTextContrast(background) < 4.5) {
    lightness = (lightness - 0.01).clamp(0.06, 0.29);
    background = toned();
  }
  return background;
}

double immersivePortraitSecondaryTextContrast(Color background) {
  final foreground = Color.alphaBlend(
    Colors.white.withValues(alpha: 0.68),
    background,
  );
  return (foreground.computeLuminance() + 0.05) /
      (background.computeLuminance() + 0.05);
}

Future<Color> loadImmersivePortraitBackdropColor(
  String? url,
  Size viewport,
) async {
  return (await loadImmersiveBackdropAppearance(
    url,
    viewport,
    sampleColor: true,
  ))
      .color;
}

/// The focus and portrait fill are derived from the same proportional sample.
/// For network images, matching [targetWidth] to the visible backdrop lets the
/// image cache coalesce the main decode instead of fetching a second URL size.
Future<ImmersiveBackdropAppearance> loadImmersiveBackdropAppearance(
  String? url,
  Size viewport, {
  bool sampleColor = false,
  int? targetWidth,
}) async {
  final value = url?.trim() ?? '';
  const fallback = ImmersiveBackdropAppearance(
    Alignment.center,
    immersivePortraitFallbackColor,
  );
  if (value.isEmpty) return fallback;

  try {
    ui.Image? source;
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'http' || uri?.scheme == 'https') {
      final cached = await ImageCacheManager.instance.loadImage(
        value,
        targetWidth: targetWidth ?? 256,
      );
      // The cache can evict its handle while analysis is in flight.
      source = cached.clone();
    } else {
      if (kIsWeb) return fallback;
      final file = File(value);
      if (!await file.exists()) return fallback;
      final codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: 256,
      );
      try {
        source = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }
    try {
      final sample = await makeImmersiveBackdropAnalysisImage(source);
      try {
        final alignment =
            await chooseImmersiveBackdropAlignment(sample, viewport);
        final color = sampleColor
            ? await extractImmersivePortraitBackdropColor(
                sample,
                viewport,
                alignment: alignment,
              )
            : immersivePortraitFallbackColor;
        return ImmersiveBackdropAppearance(alignment, color);
      } finally {
        sample.dispose();
      }
    } finally {
      source.dispose();
    }
  } catch (error) {
    debugPrint('Unable to analyse immersive backdrop: $error');
    return fallback;
  }
}
