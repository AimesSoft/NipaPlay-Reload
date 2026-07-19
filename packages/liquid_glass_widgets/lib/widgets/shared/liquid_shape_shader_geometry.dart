import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../src/renderer/liquid_glass_renderer.dart';

/// Resolves a liquid shape's circular-arc corner radius for fragment shaders.
///
/// Concrete type matching is stable in AOT/obfuscated builds, unlike runtime
/// class-name inspection.
double resolveLiquidShapeCornerRadius(LiquidShape shape, Size size) {
  final maxRadius = math.min(size.width, size.height) / 2.0;
  final radius = switch (shape) {
    LiquidOval() => maxRadius,
    LiquidRoundedSuperellipse(:final borderRadius) => borderRadius,
    LiquidRoundedRectangle(:final borderRadius) => borderRadius,
    LiquidVerticalRoundedSuperellipse() => 0.0,
    LiquidVerticalRoundedRectangle() => 0.0,
  };
  return radius.clamp(0.0, maxRadius).toDouble();
}
