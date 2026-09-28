import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A small proportional copy is enough to choose a cover alignment. The
/// visible backdrop still uses its separately decoded, full-resolution image.
Future<ui.Image> makeImmersiveBackdropAnalysisImage(ui.Image image) async {
  final scale = math.min(1.0, math.min(256 / image.width, 384 / image.height));
  if (scale == 1) return image.clone();
  final width = math.max(1, (image.width * scale).round());
  final height = math.max(1, (image.height * scale).round());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// Finds a display centre for [BoxFit.cover]; the bitmap is never cropped or
/// stretched. Portrait poster art generally overflows vertically on both the
/// full-width desktop backdrop and the half-height phone hero.
Future<Alignment> chooseImmersiveBackdropAlignment(
  ui.Image analysisImage,
  Size viewport,
) async {
  if (viewport.width <= 0 || viewport.height <= 0) return Alignment.center;
  final aspect = viewport.width / viewport.height;
  if (analysisImage.width / analysisImage.height >= aspect) {
    return Alignment.center;
  }
  final bytes =
      await analysisImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return Alignment.center;
  final rgba = Uint8List.fromList(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  final y = await compute(
    _chooseVerticalAlignment,
    _FocusInput(rgba, analysisImage.width, analysisImage.height, aspect),
  );
  return Alignment(0, y);
}

class _FocusInput {
  const _FocusInput(this.rgba, this.width, this.height, this.aspect);

  final Uint8List rgba;
  final int width;
  final int height;
  final double aspect;
}

double _chooseVerticalAlignment(_FocusInput input) {
  final width = input.width;
  final height = input.height;
  final count = width * height;
  if (count == 0 || input.rgba.length < count * 4) return 0;
  final cropHeight = width / input.aspect;
  final windowHeight = cropHeight.round().clamp(1, height);
  final maxTop = height - windowHeight;
  if (maxTop == 0) return 0;

  final luminance = Float32List(count);
  final saturation = Float32List(count);
  for (var i = 0; i < count; i++) {
    final offset = i * 4;
    final red = input.rgba[offset] / 255;
    final green = input.rgba[offset + 1] / 255;
    final blue = input.rgba[offset + 2] / 255;
    final maximum = math.max(red, math.max(green, blue));
    final minimum = math.min(red, math.min(green, blue));
    saturation[i] = (maximum - minimum) / math.max(maximum, 0.05);
    luminance[i] = red * 0.2126 + green * 0.7152 + blue * 0.0722;
  }

  final edges = Float32List(count);
  final localColourChange = Float32List(count);
  for (var y = 0; y < height; y++) {
    final above = math.max(0, y - 1) * width;
    final below = math.min(height - 1, y + 1) * width;
    final farAbove = math.max(0, y - 6) * width;
    final farBelow = math.min(height - 1, y + 6) * width;
    for (var x = 0; x < width; x++) {
      final left = math.max(0, x - 1);
      final right = math.min(width - 1, x + 1);
      final farLeft = math.max(0, x - 6);
      final farRight = math.min(width - 1, x + 6);
      final i = y * width + x;
      final dx =
          (luminance[y * width + right] - luminance[y * width + left]) / 2;
      final dy = (luminance[below + x] - luminance[above + x]) / 2;
      edges[i] = math.sqrt(dx * dx + dy * dy);

      final r = input.rgba[i * 4].toDouble();
      final g = input.rgba[i * 4 + 1].toDouble();
      final b = input.rgba[i * 4 + 2].toDouble();
      final leftOffset = (y * width + farLeft) * 4;
      final rightOffset = (y * width + farRight) * 4;
      final aboveOffset = (farAbove + x) * 4;
      final belowOffset = (farBelow + x) * 4;
      final neighbourR = input.rgba[leftOffset] +
          input.rgba[rightOffset] +
          input.rgba[aboveOffset] +
          input.rgba[belowOffset];
      final neighbourG = input.rgba[leftOffset + 1] +
          input.rgba[rightOffset + 1] +
          input.rgba[aboveOffset + 1] +
          input.rgba[belowOffset + 1];
      final neighbourB = input.rgba[leftOffset + 2] +
          input.rgba[rightOffset + 2] +
          input.rgba[aboveOffset + 2] +
          input.rgba[belowOffset + 2];
      localColourChange[i] = (r - neighbourR / 4).abs() / 765 +
          (g - neighbourG / 4).abs() / 765 +
          (b - neighbourB / 4).abs() / 765;
    }
  }

  final saturationScale = _percentile90(saturation);
  final edgeScale = _percentile90(edges);
  final colourScale = _percentile90(localColourChange);
  final rowSaliency = Float32List(height);
  final rowDetail = Float32List(height);
  for (var x = 0; x < width; x++) {
    final centredX = width == 1 ? 0.0 : 2 * x / (width - 1) - 1;
    final xWeight = 0.65 + 0.35 * math.exp(-0.5 * math.pow(centredX / 0.6, 2));
    for (var y = 0; y < height; y++) {
      final i = y * width + x;
      final chroma = math.min(1.0, saturation[i] / saturationScale);
      final edge = math.min(1.0, edges[i] / edgeScale);
      final colour = math.min(1.0, localColourChange[i] / colourScale);
      rowSaliency[y] +=
          (0.35 * chroma + 0.35 * edge + 0.30 * colour) * xWeight / width;
      rowDetail[y] += (0.55 * edge + 0.45 * colour) * xWeight / width;
    }
  }

  final centreTop = maxTop / 2;
  final radius = math.min(height * 0.20, maxTop / 2);
  final searchStart = math.max(0, (centreTop - radius).round());
  var searchEnd = math.min(maxTop, (centreTop + radius).round());
  // A wide crop moved below centre often favours clothing, a colourful floor,
  // or a printed title at the expense of the characters' heads.
  if (input.aspect > 1.2) {
    searchEnd = math.min(searchEnd, centreTop.round());
  }
  final boundaryBand = math.max(2, (windowHeight * 0.045).round());
  final yWeights = List<double>.generate(windowHeight, (index) {
    final centredY =
        windowHeight == 1 ? 0.0 : 2 * index / (windowHeight - 1) - 1;
    return 0.55 + 0.45 * math.exp(-0.5 * math.pow(centredY / 0.55, 2));
  });

  double score(int top) {
    var content = 0.0;
    for (var y = 0; y < windowHeight; y++) {
      content += rowSaliency[top + y] * yWeights[y];
    }
    content /= windowHeight;
    var upperCut = 0.0;
    var lowerCut = 0.0;
    for (var y = 0; y < boundaryBand; y++) {
      upperCut += rowDetail[top + y];
      lowerCut += rowDetail[top + windowHeight - boundaryBand + y];
    }
    upperCut /= boundaryBand;
    lowerCut /= boundaryBand;
    final centreShift = (top - centreTop).abs() / height;
    final upwardTieBreak = (centreTop - top) / height;
    return content -
        0.32 * upperCut -
        0.04 * lowerCut -
        0.04 * centreShift +
        0.012 * upwardTieBreak;
  }

  final centreCandidate = centreTop.round();
  final centreScore = score(centreCandidate);
  var bestTop = centreCandidate;
  var bestScore = centreScore;
  for (var top = searchStart; top <= searchEnd; top++) {
    final candidateScore = score(top);
    if (candidateScore > bestScore) {
      bestScore = candidateScore;
      bestTop = top;
    }
  }
  if (bestScore - centreScore < 0.006) bestTop = centreCandidate;
  return (2 * bestTop / maxTop - 1).clamp(-1.0, 1.0);
}

double _percentile90(Float32List values) {
  final bins = Uint32List(256);
  for (final value in values) {
    bins[(value.clamp(0.0, 1.0) * 255).round()]++;
  }
  final threshold = (values.length * 0.9).ceil();
  var count = 0;
  for (var index = 0; index < bins.length; index++) {
    count += bins[index];
    if (count >= threshold) return math.max(index / 255, 0.01);
  }
  return 1;
}
