import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../src/renderer/liquid_glass_settings.dart';
import '../types/glass_specular_sharpness.dart';

/// A partial override of [LiquidGlassSettings] for use in [GlassThemeVariant].
///
/// Unlike [LiquidGlassSettings], every field here is optional (`null`).
/// A `null` value means "do not override — use the widget's own default".
///
/// This solves the footgun where setting a single property like `thickness`
/// in the theme would silently zero out all other settings (e.g. `glassColor`
/// would revert to fully transparent because the constructor default is
/// `Color.fromARGB(0, …)`).
///
/// ## Usage
///
/// ```dart
/// GlassTheme(
///   data: GlassThemeData(
///     light: GlassThemeVariant(
///       // Only thickness and blur are overridden — glassColor, refractiveIndex,
///       // lightIntensity, etc. continue to use each widget's own defaults.
///       settings: GlassThemeSettings(
///         thickness: 40,
///         blur: 6,
///       ),
///     ),
///   ),
///   child: …,
/// )
/// ```
///
/// ## Merge order
///
/// 1. Widget's own explicit `settings` parameter (highest priority)
/// 2. Theme `GlassThemeSettings` — only non-null fields applied
/// 3. Widget's built-in per-widget defaults (lowest priority)
@immutable
class GlassThemeSettings {
  /// Creates a partial settings override.
  ///
  /// Every parameter is optional. Omitted (null) parameters leave the
  /// corresponding property on the target widget unchanged.
  const GlassThemeSettings({
    this.visibility,
    this.glassColor,
    this.thickness,
    this.blur,
    this.chromaticAberration,
    this.lightAngle,
    this.lightIntensity,
    this.ambientStrength,
    this.refractiveIndex,
    this.saturation,
    this.specularSharpness,
  });

  /// See [LiquidGlassSettings.visibility].
  final double? visibility;

  /// See [LiquidGlassSettings.glassColor].
  final Color? glassColor;

  /// See [LiquidGlassSettings.thickness].
  final double? thickness;

  /// See [LiquidGlassSettings.blur].
  final double? blur;

  /// See [LiquidGlassSettings.chromaticAberration].
  final double? chromaticAberration;

  /// See [LiquidGlassSettings.lightAngle].
  final double? lightAngle;

  /// See [LiquidGlassSettings.lightIntensity].
  final double? lightIntensity;

  /// See [LiquidGlassSettings.ambientStrength].
  final double? ambientStrength;

  /// See [LiquidGlassSettings.refractiveIndex].
  final double? refractiveIndex;

  /// See [LiquidGlassSettings.saturation].
  final double? saturation;

  /// See [LiquidGlassSettings.specularSharpness].
  final GlassSpecularSharpness? specularSharpness;

  /// Returns a new [LiquidGlassSettings] by applying this override onto [base].
  ///
  /// Only non-null fields in this override replace the corresponding
  /// value in [base]. Null fields leave [base]'s value untouched.
  LiquidGlassSettings applyTo(LiquidGlassSettings base) {
    return LiquidGlassSettings(
      visibility: visibility ?? base.visibility,
      glassColor: glassColor ?? base.glassColor,
      thickness: thickness ?? base.thickness,
      blur: blur ?? base.blur,
      chromaticAberration: chromaticAberration ?? base.chromaticAberration,
      lightAngle: lightAngle ?? base.lightAngle,
      lightIntensity: lightIntensity ?? base.lightIntensity,
      ambientStrength: ambientStrength ?? base.ambientStrength,
      refractiveIndex: refractiveIndex ?? base.refractiveIndex,
      saturation: saturation ?? base.saturation,
      specularSharpness: specularSharpness ?? base.specularSharpness,
    );
  }

  /// Linearly interpolates between two partial overrides.
  ///
  /// Because every field is an *optional* override, interpolation has to
  /// respect the meaning of `null` ("use the widget's own default") rather
  /// than treating it as zero:
  ///
  /// - When a field is non-null on **both** sides it is smoothly
  ///   interpolated.
  /// - When a field is null on **either** side it switches discretely at the
  ///   midpoint (`t < 0.5` keeps [a]'s value, otherwise [b]'s). Interpolating
  ///   against an unknown widget default would produce a visible flash
  ///   through zero.
  /// - [specularSharpness] is an enum and always switches at the midpoint.
  ///
  /// Returns null when both [a] and [b] are null. Used by
  /// [GlassThemeVariant.lerp] to cross-fade between light and dark theme
  /// variants during content-aware brightness flips.
  static GlassThemeSettings? lerp(
    GlassThemeSettings? a,
    GlassThemeSettings? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return GlassThemeSettings(
      visibility: _lerpDoubleField(a.visibility, b.visibility, t),
      glassColor: _lerpColorField(a.glassColor, b.glassColor, t),
      thickness: _lerpDoubleField(a.thickness, b.thickness, t),
      blur: _lerpDoubleField(a.blur, b.blur, t),
      chromaticAberration:
          _lerpDoubleField(a.chromaticAberration, b.chromaticAberration, t),
      lightAngle: _lerpDoubleField(a.lightAngle, b.lightAngle, t),
      lightIntensity: _lerpDoubleField(a.lightIntensity, b.lightIntensity, t),
      ambientStrength:
          _lerpDoubleField(a.ambientStrength, b.ambientStrength, t),
      refractiveIndex:
          _lerpDoubleField(a.refractiveIndex, b.refractiveIndex, t),
      saturation: _lerpDoubleField(a.saturation, b.saturation, t),
      specularSharpness: t < 0.5 ? a.specularSharpness : b.specularSharpness,
    );
  }

  static double? _lerpDoubleField(double? a, double? b, double t) {
    if (a != null && b != null) return lerpDouble(a, b, t);
    return t < 0.5 ? a : b;
  }

  static Color? _lerpColorField(Color? a, Color? b, double t) {
    if (a != null && b != null) return Color.lerp(a, b, t);
    return t < 0.5 ? a : b;
  }

  /// Creates a copy with overridden values.
  GlassThemeSettings copyWith({
    double? visibility,
    Color? glassColor,
    double? thickness,
    double? blur,
    double? chromaticAberration,
    double? lightAngle,
    double? lightIntensity,
    double? ambientStrength,
    double? refractiveIndex,
    double? saturation,
    GlassSpecularSharpness? specularSharpness,
  }) {
    return GlassThemeSettings(
      visibility: visibility ?? this.visibility,
      glassColor: glassColor ?? this.glassColor,
      thickness: thickness ?? this.thickness,
      blur: blur ?? this.blur,
      chromaticAberration: chromaticAberration ?? this.chromaticAberration,
      lightAngle: lightAngle ?? this.lightAngle,
      lightIntensity: lightIntensity ?? this.lightIntensity,
      ambientStrength: ambientStrength ?? this.ambientStrength,
      refractiveIndex: refractiveIndex ?? this.refractiveIndex,
      saturation: saturation ?? this.saturation,
      specularSharpness: specularSharpness ?? this.specularSharpness,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassThemeSettings &&
          runtimeType == other.runtimeType &&
          visibility == other.visibility &&
          glassColor == other.glassColor &&
          thickness == other.thickness &&
          blur == other.blur &&
          chromaticAberration == other.chromaticAberration &&
          lightAngle == other.lightAngle &&
          lightIntensity == other.lightIntensity &&
          ambientStrength == other.ambientStrength &&
          refractiveIndex == other.refractiveIndex &&
          saturation == other.saturation &&
          specularSharpness == other.specularSharpness;

  @override
  int get hashCode => Object.hash(
        visibility,
        glassColor,
        thickness,
        blur,
        chromaticAberration,
        lightAngle,
        lightIntensity,
        ambientStrength,
        refractiveIndex,
        saturation,
        specularSharpness,
      );

  @override
  String toString() => 'GlassThemeSettings('
      'visibility: $visibility, '
      'thickness: $thickness, '
      'blur: $blur, '
      'glassColor: $glassColor'
      ')';
}
