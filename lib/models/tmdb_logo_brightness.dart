import 'dart:math' as math;
import 'dart:typed_data';

/// Visible-ink brightness: transparent pixels never count as black background.
class TmdbLogoBrightness {
  const TmdbLogoBrightness(this.luminance, this.brightFraction);
  final double luminance;
  final double brightFraction;

  bool get isBright => luminance >= 0.18 || brightFraction >= 0.45;
  Map<String, double> toJson() =>
      {'luminance': luminance, 'brightFraction': brightFraction};

  static TmdbLogoBrightness? fromJson(dynamic json) {
    if (json is! Map ||
        json['luminance'] is! num ||
        json['brightFraction'] is! num) {
      return null;
    }
    final l = (json['luminance'] as num).toDouble();
    final f = (json['brightFraction'] as num).toDouble();
    return l.isFinite && f.isFinite && l >= 0 && l <= 1 && f >= 0 && f <= 1
        ? TmdbLogoBrightness(l, f)
        : null;
  }
}

TmdbLogoBrightness? measureTmdbLogoBrightness(Uint8List straightRgba) {
  double linear(int channel) {
    final value = channel / 255;
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  var weight = 0.0;
  var luminance = 0.0;
  var bright = 0.0;
  for (var i = 0; i + 3 < straightRgba.length; i += 4) {
    final alpha = straightRgba[i + 3];
    if (alpha < 32) continue;
    final w = alpha / 255;
    final l = 0.2126 * linear(straightRgba[i]) +
        0.7152 * linear(straightRgba[i + 1]) +
        0.0722 * linear(straightRgba[i + 2]);
    weight += w;
    luminance += l * w;
    if (l >= 0.35) bright += w;
  }
  return weight == 0
      ? null
      : TmdbLogoBrightness(luminance / weight, bright / weight);
}
