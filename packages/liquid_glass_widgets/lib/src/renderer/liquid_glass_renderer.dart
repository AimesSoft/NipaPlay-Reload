// Vendored from liquid_glass_renderer MIT © whynotmake.it
// Source: https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer
// Vendored at version 0.2.0-dev.4 on 2026-03-28.
import 'package:flutter/foundation.dart' show kDebugMode;

export 'glass_glow.dart' show GlassGlow, GlassGlowLayer;
export 'liquid_glass.dart' show LiquidGlass;
export 'liquid_glass_blend_group.dart' show LiquidGlassBlendGroup;
export 'liquid_glass_settings.dart' show LiquidGlassSettings;
export 'liquid_shape.dart';
export 'rendering/liquid_glass_layer.dart' show LiquidGlassLayer;
export 'stretch.dart'
    show
        AnchorStretchSettings,
        LiquidStretch,
        OffsetResistanceExtension,
        RawLiquidStretch;

/// Whether to paint the liquid glass geometry texture for debugging purposes.
///
/// When enabled, geometry textures will be drawn directly instead of the
/// liquid glass effect.
///
/// Will be set to `false` in release builds.
@pragma('vm:platform-const-if', !kDebugMode)
bool debugPaintLiquidGlassGeometry = false;
