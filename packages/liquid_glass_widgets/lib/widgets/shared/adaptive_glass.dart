import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../src/renderer/liquid_glass_renderer.dart';
import '../../theme/glass_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../types/glass_quality.dart';
import '../../utils/glass_performance_monitor.dart';
import 'glass_accessibility_scope.dart';
import 'glass_isolation_scope.dart';
import 'lightweight_liquid_glass.dart';
import 'inherited_liquid_glass.dart';

/// A renderer-agnostic glass surface that intelligently selects the best
/// rendering path based on [GlassQuality] and the active Flutter renderer.
///
/// **Fallback chain:**
/// 1. Premium quality + Impeller available → Full shader (best quality)
/// 2. Premium quality + Skia/web → Lightweight shader (our calibrated shader)
/// 3. Standard quality → Always lightweight shader
/// 4. If lightweight shader fails → FakeGlass (final fallback)
///
/// Prefer this over [LiquidGlass] directly: [LiquidGlass] is Impeller-only
/// and silently renders nothing on Skia/Web.
///
/// Example:
/// ```dart
/// AdaptiveGlass(
///   shape: LiquidRoundedSuperellipse(borderRadius: 20),
///   settings: LiquidGlassSettings(blur: 8),
///   child: Text('Hello glass'),
/// )
/// ```
class AdaptiveGlass extends StatelessWidget {
  const AdaptiveGlass({
    required this.shape,
    required this.settings,
    required this.child,
    this.quality = GlassQuality.standard,
    this.useOwnLayer = true,
    this.clipBehavior = Clip.antiAlias,
    this.allowElevation = true,
    this.glowIntensity = 0.0,
    this.isInteractive = false,
    this.platformViewBackdrop = false,
    super.key,
  });

  /// The shape that defines the outline and clipping path of the glass surface.
  final LiquidShape shape;

  /// Visual parameters for the glass effect (blur radius, tint, specular etc.).
  final LiquidGlassSettings settings;

  /// The widget displayed inside the glass surface.
  final Widget child;

  /// Controls render fidelity. Defaults to [GlassQuality.standard].
  ///
  /// [GlassQuality.premium] enables the full shader pipeline with specular
  /// reflections and dynamic refraction.
  /// [GlassQuality.minimal] always renders the frosted fallback, avoiding the
  /// shader entirely (useful during animations or on low-end devices).
  final GlassQuality quality;

  /// If `true`, wraps the glass layer in a [RepaintBoundary] (own compositing
  /// layer). This can improve performance when the glass surface moves
  /// independently of the rest of the widget tree, at the cost of extra GPU
  /// memory. Defaults to `true`.
  final bool useOwnLayer;

  /// How to clip the child widget to the [shape] boundary.
  /// Defaults to [Clip.antiAlias].
  final Clip clipBehavior;

  /// When `true`, optimises the frosted fallback for surfaces that update their
  /// layout bounds frequently (e.g. spring-animated buttons). Omits the
  /// [BackdropFilter] on [GlassQuality.minimal] to avoid compositor flicker.
  final bool isInteractive;

  /// Whether to allow "Specular Elevation" when in a grouped context.
  /// Should be true for interactive objects (buttons) and false for layers/containers.
  final bool allowElevation;

  /// Interactive glow intensity for Skia/Web (0.0-1.0).
  ///
  /// On Impeller, this is ignored and [GlassGlow] widget is used instead.
  /// On Skia/Web, this controls shader-based button press feedback.
  ///
  /// Defaults to 0.0 (no glow).
  final double glowIntensity;

  /// When true, this glass renders via the live `BackdropFilter` path (the
  /// lightweight render) EVEN at [GlassQuality.premium] — because the premium
  /// shader samples a `toImageSync` texture, which cannot capture an iOS
  /// PlatformView (map, video). Set this on glass directly over a PlatformView
  /// so the live view shows through instead of a solid slab. Refraction is lost
  /// (no texture), but rim/lighting and the live blur remain. Premium children
  /// that refract Flutter content (e.g. the indicator) should NOT set this.
  final bool platformViewBackdrop;

  /// Detects if Impeller rendering engine is active.
  ///
  /// Returns true when shader filters are supported (Impeller),
  /// false when using Skia or web renderers.
  ///
  /// This is the same check used internally by liquid_glass_renderer.
  static bool get _canUseImpeller => ui.ImageFilter.isShaderFilterSupported;

  /// Static helper to render glass in a grouped context without creating a new layer.
  /// This is the adaptive replacement for [LiquidGlass.withOwnLayer].
  static Widget grouped({
    required LiquidShape shape,
    required Widget child,
    GlassQuality quality = GlassQuality.standard,
    Clip clipBehavior = Clip.antiAlias,
    double glowIntensity = 0.0,
    bool isInteractive = false,
    bool platformViewBackdrop = false,
  }) {
    return AdaptiveGlass(
      shape: shape,
      settings: const LiquidGlassSettings(), // Inherited via inLayer
      quality: quality,
      useOwnLayer: false,
      clipBehavior: clipBehavior,
      glowIntensity: glowIntensity,
      isInteractive: isInteractive,
      platformViewBackdrop: platformViewBackdrop,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Resolve Settings
    // In grouped mode, the explicit `settings` field is a const placeholder;
    // we must inherit the real settings from the ancestor layer.
    final inherited =
        context.dependOnInheritedWidgetOfExactType<InheritedLiquidGlass>();
    final baseSettings =
        (!useOwnLayer && inherited != null) ? inherited.settings : settings;

    // ---- MINIMAL FAST-PATH ---------------------------------------------------
    // GlassQuality.minimal bypasses all custom shaders. Renders via
    // _FrostedFallback: ClipPath(ShapeBorderClipper) + BackdropFilter + tint.
    // ClipPath correctly clips ALL shape types (oval, superellipse, rect).
    // Zero fragment shader cost on any device.
    //
    // platformViewBackdrop ALSO routes here: over a PlatformView only a live
    // BackdropFilter samples the composited map. The premium/standard shaders
    // read a captured backdrop that EXCLUDES the platform view (see
    // canUsePremiumShader below), so they render inert there — the frost is the
    // one tier that actually blurs over a PlatformView. This finally delivers
    // the "live BackdropFilter path" the canUsePremiumShader comment promises.
    // --------------------------------------------------------------------------
    if (quality == GlassQuality.minimal ||
        baseSettings.effectiveBlur == 0 ||
        platformViewBackdrop) {
      return _wrapWithDecorations(
        context,
        baseSettings,
        _FrostedFallback(
          shape: shape,
          settings: baseSettings,
          clipBehavior: clipBehavior,
          glowIntensity: glowIntensity,
          isAccessibilityFallback: false,
          isInteractive: isInteractive,
          platformViewBackdrop: platformViewBackdrop,
          child: child,
        ),
      );
    }

    // ---- IP1: ACCESSIBILITY FAST-PATH ----------------------------------------
    // iOS 26 glass degrades to a solid frosted panel when "Reduce Transparency"
    // is enabled. We honour the equivalent Flutter signal (highContrast, which
    // is the closest available platform proxy for isReduceTransparencyEnabled).
    //
    // When triggered, the entire glass shader pipeline is bypassed. The fallback
    // is a ClipRRect + BackdropFilter(blur) + semi-opaque tinted container —
    // still visually layered, but with no refraction, no specular, and no
    // chromatic aberration. Zero GPU shader cost.
    //
    // GlassAccessibilityScope must be in the widget tree for this to activate;
    // without it, defaults.reduceTransparency = false and we proceed normally.
    // --------------------------------------------------------------------------
    final accessibilityData = GlassAccessibilityData.of(context);
    if (accessibilityData.reduceTransparency) {
      return _wrapWithDecorations(
        context,
        baseSettings,
        _FrostedFallback(
          shape: shape,
          settings: baseSettings,
          clipBehavior: clipBehavior,
          glowIntensity: glowIntensity,
          isAccessibilityFallback: true,
          isInteractive: isInteractive,
          child: child,
        ),
      );
    }

    // If we are on Skia/Web, we CANNOT use LiquidGlass.withOwnLayer or withOwnLayer
    // because those will fall back to FakeGlass (solid color) inside the renderer.
    // We MUST use our LightweightLiquidGlass to get actual glass effects.

    // platformViewBackdrop forces the live BackdropFilter path even at premium:
    // the premium shader's toImageSync backdrop can't capture a PlatformView, so
    // over one it must use BackdropFilter (live) instead. The local/cheap checks
    // are evaluated before the platform shader-support query (_canUseImpeller).
    final bool canUsePremiumShader = !kIsWeb &&
        !platformViewBackdrop &&
        quality == GlassQuality.premium &&
        _canUseImpeller;

    if (!canUsePremiumShader) {
      // 1. Detect Grouped Elevation
      // When a parent provides the blur (Batch-Blur Optimization), we lose the
      // "double-darkening" effect of nested blurs. We compensate with the
      // densityFactor parameter (0.0-1.0) which triggers synthetic density physics
      // in the shader to make elevated widgets "pop" against the background.
      final bool shouldElevate =
          allowElevation && (inherited?.isBlurProvidedByAncestor ?? false);

      // Calculate density factor for shader (0.0 = normal, 1.0 = elevated)
      final double densityFactor = shouldElevate ? 1.0 : 0.0;

      // Normalise settings for the 2D lightweight shader to prevent it from looking
      // overpowering when the user has tuned their settings for the 3D premium shader.
      //
      // BYPASS: When quality is explicitly GlassQuality.standard, the settings
      // are already calibrated for the Standard renderer — skip normalization.
      // Normalization only makes sense when adapting Premium-tuned settings to
      // Standard; if the caller already knows they're on Standard, their values
      // must be passed through unchanged so tuning sliders take full effect.
      final bool skipNormalization = quality == GlassQuality.standard;

      final LiquidGlassSettings normalizedSettings;
      if (skipNormalization) {
        normalizedSettings = baseSettings.copyWith(
          glassColor: baseSettings.glassColor.withValues(
            alpha: (baseSettings.glassColor.a *
                    baseSettings.standardOpacityMultiplier)
                .clamp(0.0, 1.0),
          ),
        );
      } else {
        // Frosting normalization: adapts Premium settings for the 2D shader.
        // Thickness scaled down (2D inner shadows look much thicker than 3D bevels).
        // Light intensity scaled down (2D gradients look brighter than 3D speculars).
        normalizedSettings = baseSettings.copyWith(
          thickness: (baseSettings.effectiveThickness * 0.4)
              .clamp(0.0, double.infinity),
          lightIntensity:
              (baseSettings.effectiveLightIntensity * 0.6).clamp(0.0, 10.0),
          glassColor: baseSettings.glassColor.withValues(
            alpha: (baseSettings.glassColor.a *
                    baseSettings.standardOpacityMultiplier)
                .clamp(0.0, 1.0),
          ),
        );
      }

      // Apply subtle elevation boost to settings (preserves saturation!)
      final color = normalizedSettings.effectiveGlassColor;
      final effectiveSettings = shouldElevate
          ? LiquidGlassSettings(
              glassColor:
                  color, // Removed flat +0.2 alpha boost for predictability
              refractiveIndex: normalizedSettings.refractiveIndex,
              thickness: normalizedSettings.effectiveThickness,
              lightAngle: normalizedSettings.lightAngle,
              lightIntensity: (normalizedSettings.effectiveLightIntensity * 1.2)
                  .clamp(0.0, 10.0),
              chromaticAberration: normalizedSettings.chromaticAberration,
              blur: normalizedSettings.effectiveBlur,
              visibility: normalizedSettings.visibility,
              saturation: normalizedSettings.effectiveSaturation,
              ambientStrength:
                  (normalizedSettings.effectiveAmbientStrength * 0.4)
                      .clamp(0.0, 1.0),
              glowIntensity: normalizedSettings.glowIntensity,
              // Preserve whiten through the elevation rebuild; otherwise the
              // whitening would silently drop to 0 for grouped/elevated
              // surfaces such as bars.
              whitenStrength: normalizedSettings.whitenStrength,
              whitenGated: normalizedSettings.whitenGated,
            )
          : normalizedSettings;

      // If this is a container (allowElevation=false), we are providing a blur
      // for all our children to use. We update the InheritedLiquidGlass tree.
      if (!allowElevation) {
        return _wrapWithDecorations(
          context,
          baseSettings,
          LightweightLiquidGlass(
            shape: shape,
            settings: effectiveSettings,
            densityFactor: 0.0, // Containers are never elevated
            glowIntensity: 0.0, // Containers don't glow
            child: InheritedLiquidGlass(
              settings: effectiveSettings,
              quality: quality,
              isBlurProvidedByAncestor: true,
              child: child,
            ),
          ),
        );
      }

      // Elevated widgets use PATH B (no backgroundKey). They composite via
      // SrcOver against the container's output.
      final Widget lightweightWidget = LightweightLiquidGlass(
        shape: shape,
        settings: effectiveSettings,
        densityFactor: densityFactor, // 0.0 or 1.0 based on elevation
        glowIntensity:
            glowIntensity * 0.35, // Normalise additive glow to match Impeller
        child: child,
      );

      return _wrapWithDecorations(context, baseSettings, lightweightWidget);
    }

    // Impeller + Premium Path: Use the renderer's native path.
    // Wrap in PremiumGlassTracker so GlassPerformanceMonitor can correlate
    // slow raster frames with active premium surfaces.
    //
    // Force useOwnLayer when inside a GlassIsolationScope (e.g. GlassScaffold
    // bottom bar). This gives bars their own compositing layer so body glass
    // cards don't composite over bar buttons.
    //
    // NOTE: isInteractive is NOT included here. It only controls
    // RepaintBoundary wrapping (lines below). Including it would force
    // every GlassButton into its own compositing layer, breaking grouped
    // rendering inside bars (e.g. BottomBarExtraBtn must blend with the
    // tab pill, not render as a separate glass surface). Buttons that need
    // independent refraction should set useOwnLayer: true explicitly.
    //
    // De-isolate children of the own-layer so nested glass (e.g. tab
    // items inside a bottom bar) groups with this layer rather than
    // creating additional own-layers (which would cause double-glass).
    final effectiveUseOwnLayer =
        useOwnLayer || GlassIsolationScope.isIsolated(context);

    if (effectiveUseOwnLayer) {
      // Resolve shadows for the GPU cutout method
      final isDark = GlassTheme.brightnessOf(context) == Brightness.dark;
      final shadows = (isDark || _FrostedFallback._isFlatEdge(shape))
          ? const <BoxShadow>[]
          : baseSettings.effectiveShadow;

      Widget premium = LiquidGlass.withOwnLayer(
        shape: shape,
        settings: settings,
        shadows: shadows,
        clipBehavior: clipBehavior,
        // De-isolate children so nested glass groups with this own-layer
        // rather than creating its own (which causes double-glass).
        // Carry the parent's defaultQuality through so quality hints
        // (e.g. premium for bars) are preserved even when de-isolated.
        child: GlassIsolationScope(
          isolated: false,
          defaultQuality: GlassIsolationScope.defaultQualityOf(context),
          child: child,
        ),
      );

      return _wrapWithBacker(
        baseSettings,
        PremiumGlassTracker(
          child: premium,
        ),
      );
    } else {
      // Grouped elements (e.g. inside GlassBottomBar) rely on the ancestor's
      // LiquidGlassLayer to provide the RepaintBoundary and BackdropGroup.
      // IMPORTANT: Do NOT wrap grouped elements with the shadow Stack — it
      // inserts a widget between the grouped glass and its ancestor blend
      // group, breaking metaball morphing (the blend SDF pass requires
      // grouped render objects to be direct descendants of the shared layer).
      return PremiumGlassTracker(
        child: LiquidGlass.grouped(
          shape: shape,
          clipBehavior: clipBehavior,
          child: child,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Light-mode drop shadow — iOS 26 glass elevation
  //
  // Apple's iOS 26 uses a soft, diffuse drop shadow to give glass surfaces
  // depth and elevation in light mode, instead of relying on a visible border.
  // In dark mode, the shadow is invisible (absorbed by the dark background),
  // so we skip it entirely to avoid unnecessary compositing cost.
  //
  // Suppressed for flat-edge shapes (borderRadius: 0) like app bars and bottom
  // bars, which span edge-to-edge and don't need individual elevation.
  // ---------------------------------------------------------------------------
  Widget _wrapWithLightModeShadow(
      BuildContext context, LiquidGlassSettings baseSettings, Widget glass) {
    final isDark = GlassTheme.brightnessOf(context) == Brightness.dark;

    // Skip shadow in dark mode or for flat-edge shapes (bars, full-width surfaces).
    if (isDark || _FrostedFallback._isFlatEdge(shape)) {
      return glass;
    }

    // Resolve the shadow from settings (per-widget or inherited).
    final shadows = baseSettings.effectiveShadow;
    if (shadows.isEmpty) return glass;

    // Extract border radius from the shape for the shadow decoration.
    final borderRadius = _borderRadiusFromShape(shape);

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        // 1. The glass surface (BackdropFilter captures only the background)
        glass,

        // 2. The drop shadow (painted on top, but inverse-clipped so it only
        // appears OUTSIDE the glass). This prevents the glass from blurring its
        // own shadow, which would otherwise create a dirty dark rim.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipPath(
              clipBehavior: Clip.antiAlias,
              clipper: _InverseShapeClipper(shape),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  boxShadow: shadows,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Applies the backer (behind the glass) and the light-mode drop shadow
  /// (outside the glass) to [glass]. Both are no-ops when their respective
  /// settings are unset, so existing recipes are unaffected. Same signature as
  /// [_wrapWithLightModeShadow] so the non-premium call sites just swap names.
  Widget _wrapWithDecorations(
      BuildContext context, LiquidGlassSettings baseSettings, Widget glass) {
    return _wrapWithBacker(
      baseSettings,
      _wrapWithLightModeShadow(context, baseSettings, glass),
    );
  }

  // ---------------------------------------------------------------------------
  // Backer — Apple "dimming layer" behind the glass
  //
  // A shape-matched color pad composited BEHIND the glass (the inverse of the
  // drop shadow, which sits OUTSIDE the boundary). Gives a control's content
  // contrast over rich/colorful backdrops — video, maps, photography — where
  // the glass tint alone can't. Rendered at the widget level via [_ShapeClip]
  // (ClipRRect for superellipses, so the clip forwards to the iOS PlatformView
  // mutator stack), independent of the shader tier — so it works over a
  // PlatformView, where a shader-side tint cannot reach.
  //
  // Unlike the shadow, it applies in BOTH brightnesses and for flat-edge shapes
  // (a bar over a map is a primary use case). NOT applied on the grouped path:
  // like the shadow, inserting a Stack between a grouped glass and its shared
  // layer would break metaball morphing.
  // ---------------------------------------------------------------------------
  Widget _wrapWithBacker(LiquidGlassSettings baseSettings, Widget glass) {
    final backerColor = baseSettings.backerColor;
    if (backerColor == null || backerColor.a == 0) return glass;

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        // 1. The dimming pad — BEHIND the glass, clipped to the glass shape.
        Positioned.fill(
          child: IgnorePointer(
            child: _ShapeClip(
              shape: shape,
              platformViewBackdrop: platformViewBackdrop,
              child: ColoredBox(color: backerColor),
            ),
          ),
        ),
        // 2. The glass on top; its translucency lets the pad dim it through.
        glass,
      ],
    );
  }

  /// Extracts a [BorderRadius] from a [LiquidShape] for shadow decoration.
  static BorderRadius? _borderRadiusFromShape(LiquidShape shape) {
    if (shape is LiquidRoundedSuperellipse) {
      return BorderRadius.circular(shape.borderRadius);
    }
    if (shape is LiquidRoundedRectangle) {
      return BorderRadius.circular(shape.borderRadius);
    }
    if (shape is LiquidVerticalRoundedSuperellipse) {
      return BorderRadius.vertical(
        top: Radius.circular(shape.topRadius),
        bottom: Radius.circular(shape.bottomRadius),
      );
    }
    if (shape is LiquidVerticalRoundedRectangle) {
      return BorderRadius.vertical(
        top: Radius.circular(shape.topRadius),
        bottom: Radius.circular(shape.bottomRadius),
      );
    }
    if (shape is LiquidOval) {
      // Large radius approximation for oval/circle shapes.
      return BorderRadius.circular(9999);
    }
    return null;
  }
}

/// Clips out the interior of a shape, leaving only the exterior.
/// Used to prevent drop shadows from bleeding under translucent glass.
class _InverseShapeClipper extends CustomClipper<Path> {
  const _InverseShapeClipper(this.shape);

  final LiquidShape shape;

  @override
  Path getClip(Size size) {
    final rect = Offset.zero & size;
    final shapePath = shape.getOuterPath(rect);

    // Create an outer rect that encompasses the entire shadow blur radius
    // 50px is plenty for our 12px max blur radius.
    final outerRect = rect.inflate(50.0);
    final outerPath = Path()..addRect(outerRect);

    // Subtract the shape from the outer bounds, leaving a hole in the middle.
    // Uses CPU path operations (supported in Impeller).
    return Path.combine(PathOperation.difference, outerPath, shapePath);
  }

  @override
  bool shouldReclip(_InverseShapeClipper oldClipper) =>
      oldClipper.shape != shape;
}

// ---------------------------------------------------------------------------
// _FrostedFallback — shader-free glass fallback surface
//
// Used by:
//   • GlassQuality.minimal      — developer-requested safe mode
//   • GlassAccessibilityScope   — OS Reduce Transparency preference
//
// Visual quality parity with upstream FakeGlass (whynotmake.it):
//   • BackdropFilter blur  — same sigma as the normal glass blur
//   • Saturation matrix    — Rec. 709 luma-coefficient ColorFilter
//   • Specular rim         — two Canvas strokes with a light-angle linear
//                            gradient (pure srcOver — no GPU readback)
//   • Shape clipping       — ClipRRect for rect/squircle, or ClipOval
//
// No GLSL shaders. No FragmentShader. No Impeller-specific paths.
// Runs identically on Skia, Impeller, Web, Windows, and Linux.
// ---------------------------------------------------------------------------
class _FrostedFallback extends StatelessWidget {
  const _FrostedFallback({
    required this.shape,
    required this.settings,
    required this.child,
    this.clipBehavior = Clip.antiAlias,
    this.glowIntensity = 0.0,
    this.isAccessibilityFallback = false,
    this.isInteractive = false,
    this.platformViewBackdrop = false,
  });

  final LiquidShape shape;
  final LiquidGlassSettings settings;
  final Widget child;
  final Clip clipBehavior;
  final double glowIntensity;

  /// When true (OS Reduce Transparency), opacity is boosted for legibility:
  /// alpha = (tint.a × 0.5 + 0.40).clamp(0.40, 0.80).
  ///
  /// When false (GlassQuality.minimal — developer choice), the glass color
  /// alpha is used more directly so the surface stays translucent:
  /// alpha = tint.a.clamp(0.05, 0.55).
  final bool isAccessibilityFallback;

  /// Signals that this surface frequently updates its layout bounds or transform
  /// via spring animations (e.g. GlassButton, interactive pill indicators).
  ///
  /// When true, during [GlassQuality.minimal] we omit the [BackdropFilter] to
  /// prevent compositor desync flicker caused by the bounds changing continuously.
  final bool isInteractive;

  /// When true, this frost sits directly over a PlatformView (map/video) via the
  /// `platformViewBackdrop` route. The live [BackdropFilter] is the ONLY path
  /// that blurs a hybrid-composed PlatformView, so it must run even for
  /// interactive surfaces — otherwise the [isInteractive] blur-omission below
  /// leaves over-map buttons with no blur at all (the brief tap-scale flicker is
  /// negligible next to having no blur).
  final bool platformViewBackdrop;

  /// Rec. 709 saturation matrix — identical to upstream FakeGlass.
  ///
  /// saturation = 0  → grayscale
  /// saturation = 1  → unchanged
  /// saturation > 1  → over-saturated (default glass is 1.5)
  static List<double> _saturationMatrix(double saturation) {
    const lumR = 0.299;
    const lumG = 0.587;
    const lumB = 0.114;
    final s = saturation;
    final inv = 1.0 - s;
    return [
      lumR * inv + s, lumG * inv, lumB * inv, 0, 0, // R
      lumR * inv, lumG * inv + s, lumB * inv, 0, 0, // G
      lumR * inv, lumG * inv, lumB * inv + s, 0, 0, // B
      0, 0, 0, 1, 0, // A
    ];
  }

  @override
  Widget build(BuildContext context) {
    final blur = settings.effectiveBlur.clamp(0.0, 40.0);
    // Whiten veil: lift the tint toward white by a ramp of
    // [LiquidGlassSettings.whitenStrength], matching the Standard path
    // (lightweight_liquid_glass.dart). This is why minimal-tier controls
    // whiten from the same single knob — no per-widget code needed. The veil
    // ramp uses the same gain as the Standard path so a single whitenStrength
    // value reads consistently across tiers. Minimal's tint is already a
    // uniform flat fill, so this lerp is the whole whiten here.
    const double kWhitenVeilGain = 1.5;
    final double whiten = settings.whitenStrength.clamp(0.0, 1.0).toDouble();
    final double veil = whiten <= 0.0
        ? 0.0
        : (whiten * kWhitenVeilGain).clamp(0.0, 1.0).toDouble();
    final tint = veil <= 0.0
        ? settings.effectiveGlassColor
        : Color.lerp(
            settings.effectiveGlassColor, const Color(0xFFFFFFFF), veil)!;

    final double frostedAlpha = isAccessibilityFallback
        // Accessibility: boost opacity so content remains legible
        // even when Reduce Transparency removes blur on older hardware.
        ? (tint.a * 0.5 + 0.40).clamp(0.40, 0.80)
        // Minimal (developer choice): honour the specified glass color alpha,
        // allowing it to go up to 1.0 for solid color modes.
        : tint.a.clamp(0.05, 1.0);
    final frostedColor = tint.withValues(alpha: frostedAlpha);

    final sat = settings.effectiveSaturation;
    final bool needsSaturation = (sat - 1.0).abs() > 0.01;

    // ── Layer stack (bottom to top) ─────────────────────────────────────────
    //
    // Accessibility fallback: opacity heavily boosted for legibility (Reduce
    // Transparency intent — less see-through = more readable).
    //
    // Minimal developer mode: alpha is used more directly (honours the
    // developer's specified glassColor), giving a lighter, more translucent
    // surface.
    //
    // BackdropFilter rules:
    // - Always used in accessibility mode to ensure strong contrast.
    // - In minimal mode, used for STATIONARY surfaces (app bar, bottom bar)
    //   to retain the frosted glass aesthetic.
    // - OMITTED for INTERACTIVE surfaces (buttons, sliding pills) in minimal
    //   mode because BackdropFilter re-samples the background every frame and
    //   desyncs with spring bounds changes, causing a "flashing" or flickering
    //   artifact beneath the element.
    // - EXCEPT when platformViewBackdrop is set: over a PlatformView the live
    //   BackdropFilter is the only path that blurs the (hybrid-composed) map, so
    //   it must run even for interactive buttons. Without this, #128's frost
    //   route delivers no blur for over-map controls (heading, 2D, ⋯ buttons).
    // ────────────────────────────────────────────────────────────────────────
    final bool useBlur =
        (isAccessibilityFallback || !isInteractive || platformViewBackdrop) &&
            blur > 0;

    Widget body;
    if (useBlur) {
      body = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(color: frostedColor),
          child: needsSaturation
              ? BackdropFilter(
                  filter: ui.ColorFilter.matrix(_saturationMatrix(sat)),
                  child: const SizedBox.expand(),
                )
              : const SizedBox.expand(),
        ),
      );
    } else {
      // Minimal interactive path: blur-free frosted tint prevents cache flicker
      // when updating rapidly during spring physics drag.
      body = DecoratedBox(
        decoration: BoxDecoration(color: frostedColor),
        child: const SizedBox.expand(),
      );
    }

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip
          .hardEdge, // Locks dirty region to widget bounds — prevents page-wide flicker
      children: [
        if (useBlur)
          // Stationary surfaces: blur + tint clipped to shape.
          //
          // Use ClipRRect when the shape resolves to a rounded rect —
          // Flutter PR #177551 (in 3.41+) forwards ClipRRect clip data
          // to iOS PlatformView mutators, so ClipRRect (not ClipPath)
          // is what lets the engine clip a descendant BackdropFilter
          // over a PlatformView. Eliminates the rectangular blur halo
          // around rounded glass surfaces stacked over PlatformViews
          // (e.g. mapbox_maps_flutter, video_player on iOS).
          Positioned.fill(
            child: _ShapeClip(
              shape: shape,
              platformViewBackdrop: platformViewBackdrop,
              child: body,
            ),
          ),

        if (!useBlur)
          // Interactive surfaces: pure ShapeDecoration vector — bypasses the
          // stencil buffer so sub-pixel spring deceleration never causes edge flicker.
          Positioned.fill(
            child: DecoratedBox(
              decoration: ShapeDecoration(color: frostedColor, shape: shape),
              child: const SizedBox.expand(),
            ),
          ),

        // Glow intensity wrapper for GlassButton tap feedback
        if (glowIntensity > 0)
          Positioned.fill(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape,
                color: (GlassTheme.brightnessOf(context) == Brightness.dark
                        ? Colors.white
                        : Colors.black)
                    .withValues(alpha: 0.15 * glowIntensity),
              ),
            ),
          ),

        // Text and contents MUST be strictly clipped to corner radii.
        // Same ClipRRect-over-ClipPath rationale as the blur body
        // above — see the [_ShapeClip] doc comment.
        _ShapeClip(
          shape: shape,
          platformViewBackdrop: platformViewBackdrop,
          child: child,
        ),

        // Specular Rim: drawn as a pure native overlay vector perfectly on top.
        // Wrapped in _ShapeClip because canvas.drawPath draws a center-aligned
        // stroke. Clipping it removes the outer half, creating a true 'inner
        // border' which is optically correct for glass internal reflections.
        //
        // Suppressed for flat-edge shapes (borderRadius: 0) like app bars,
        // where the rim looks like a Material divider rather than a glass edge.
        if (!_isFlatEdge(shape))
          Positioned.fill(
            child: IgnorePointer(
              child: _ShapeClip(
                shape: shape,
                platformViewBackdrop: platformViewBackdrop,
                child: CustomPaint(
                  painter: _SpecularRimPainter(
                    shape: shape,
                    settings: settings,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Returns true when [shape] has no rounded corners (borderRadius == 0).
  ///
  /// Full-width surfaces (app bars, bottom bars) use `borderRadius: 0` and
  /// the specular rim on their straight edges looks like a Material divider
  /// rather than an internal glass reflection.
  static bool _isFlatEdge(LiquidShape shape) {
    if (shape is LiquidRoundedRectangle && shape.borderRadius == 0) return true;
    if (shape is LiquidRoundedSuperellipse && shape.borderRadius == 0) {
      return true;
    }
    if (shape is LiquidVerticalRoundedRectangle &&
        shape.topRadius == 0 &&
        shape.bottomRadius == 0) {
      return true;
    }
    if (shape is LiquidVerticalRoundedSuperellipse &&
        shape.topRadius == 0 &&
        shape.bottomRadius == 0) {
      return true;
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// _SpecularRimPainter — light-angle specular rim stroke
//
// Ported from FakeGlass._paintSpecular() (whynotmake.it, MIT).
// Pure Canvas drawing: two gradient strokes with BlendMode.hardLight and
// BlendMode.overlay. Zero GPU shader cost on any platform.
// ---------------------------------------------------------------------------
class _SpecularRimPainter extends CustomPainter {
  const _SpecularRimPainter({
    required this.shape,
    required this.settings,
  });

  final LiquidShape shape;
  final LiquidGlassSettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    final lightIntensity = settings.effectiveLightIntensity.clamp(0.0, 1.0);
    if (lightIntensity == 0) return;

    final ambientStrength = settings.effectiveAmbientStrength.clamp(0.0, 1.0);
    final alpha = Curves.easeOut.transform(lightIntensity);
    final white = Colors.white.withValues(alpha: alpha);

    final rad = settings.lightAngle;
    final x = math.cos(rad);
    // Invert Y to match the GLSL fragment shader coordinate space (up is positive).
    final y = -math.sin(rad);

    // Expand to a square so the gradient angle matches the light angle exactly:
    // a squashed gradient rect distorts the effective direction.
    final bounds = Offset.zero & size;
    final squareBounds = Rect.fromCircle(
      center: bounds.center,
      radius: bounds.size.longestSide / 2,
    );

    // How far the light covers the glass (gradient stop spread).
    final lightCoverage = ui.lerpDouble(.3, .5, lightIntensity)!;

    // Adjust gradient scale for non-square aspect ratios.
    final aspectRatio = size.width / size.height.clamp(0.001, double.infinity);
    final alignmentWithShortestSide = (aspectRatio < 1 ? y : x).abs();
    final aspectAdjustment = 1 - 1 / aspectRatio.clamp(0.001, double.infinity);
    final gradientScale = aspectAdjustment * (1 - alignmentWithShortestSide);

    final inset = ui.lerpDouble(0, .5, gradientScale.clamp(0, 1))!;
    final secondInset =
        ui.lerpDouble(lightCoverage, .5, gradientScale.clamp(0, 1))!;

    final gradient = LinearGradient(
      colors: [
        white,
        white.withValues(alpha: ambientStrength),
        white.withValues(alpha: ambientStrength),
        white,
      ],
      stops: [inset, secondInset, 1 - secondInset, 1 - inset],
      begin: Alignment(x, y),
      end: Alignment(-x, -y),
    ).createShader(squareBounds);

    final path = shape.getOuterPath(bounds);

    // Pass 1: soft base stroke.
    // Doubled width since it is now clipped to the inner half.
    // BlendMode.overlay ensures the highlight reacts organically to the
    // background color underneath, rather than looking like a flat white line.
    canvas.drawPath(
      path,
      Paint()
        ..shader = gradient
        ..color = white.withValues(alpha: white.a * 0.4)
        ..blendMode = BlendMode.overlay
        ..style = PaintingStyle.stroke
        ..strokeWidth = ui.lerpDouble(1.0, 2.0, lightIntensity)!,
    );

    // Pass 2: sharp inner rim.
    // Doubled width since it is clipped to the inner half.
    canvas.drawPath(
      path,
      Paint()
        ..shader = gradient
        ..color = white.withValues(alpha: white.a * 0.6)
        ..blendMode = BlendMode.overlay
        ..style = PaintingStyle.stroke
        ..strokeWidth = (settings.effectiveThickness / 20).clamp(0.5, 2.0),
    );
  }

  @override
  bool shouldRepaint(_SpecularRimPainter old) =>
      old.settings != settings || old.shape != shape;
}

/// Wraps [child] in [ClipRRect] when the shape resolves to a
/// `RoundedRectangleBorder` (i.e. [LiquidRoundedSuperellipse] or
/// [LiquidVerticalRoundedSuperellipse]), otherwise falls back to
/// [ClipPath] with `ShapeBorderClipper`.
///
/// **Why this matters:** Flutter framework PR #177551 (merged Dec 2025,
/// shipped in 3.41.0-0.0.pre and forward) forwards `ClipRRect` clip data
/// to the iOS PlatformView mutator stack — which lets the engine
/// correctly clip a descendant [BackdropFilter] over a PlatformView.
/// The same fix does NOT apply to `ClipPath`, even when the path inside
/// is mathematically a rounded rect.
///
/// Eliminates the rectangular blur halo that appeared around rounded
/// `_FrostedFallback` surfaces when stacked over a PlatformView (e.g.
/// `mapbox_maps_flutter`'s `MapWidget`, `video_player` on iOS).
///
/// When [platformViewBackdrop] is true, any shape that can be expressed
/// as a [BorderRadius] (including [LiquidOval] → `circular(9999)` and
/// [LiquidRoundedRectangle]) is also routed through [ClipRRect] so the
/// clip is forwarded and the frost is bounded to the shape on PlatformViews.
/// Off a PlatformView, [LiquidOval] retains an exact [ClipPath] ellipse.
class _ShapeClip extends StatelessWidget {
  const _ShapeClip({
    required this.shape,
    required this.child,
    this.platformViewBackdrop = false,
  });

  final LiquidShape shape;
  final Widget child;

  /// When the clipped subtree sits over an iOS PlatformView, force a
  /// [ClipRRect]-based clip even for shapes that would otherwise fall through to
  /// a [ClipPath] (e.g. [LiquidOval], [LiquidRoundedRectangle]).
  ///
  /// Flutter's clip forwarding (#177551, 3.41+) only sends ClipRRect clip data
  /// to the iOS PlatformView mutator stack — a ClipPath leaves a descendant
  /// [BackdropFilter] unclipped, so the frost leaks a rectangular halo around
  /// the (visually round) surface. A ClipRRect with a full radius renders the
  /// same circle/stadium but IS forwarded, bounding the frost to the shape.
  /// Off a PlatformView the ClipPath path is exact (a true ellipse), so the swap
  /// is gated on this flag.
  final bool platformViewBackdrop;

  @override
  Widget build(BuildContext context) {
    final shape = this.shape;
    if (shape is LiquidRoundedSuperellipse) {
      return ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(shape.borderRadius)),
        child: child,
      );
    }
    if (shape is LiquidVerticalRoundedSuperellipse) {
      return ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(shape.topRadius),
          bottom: Radius.circular(shape.bottomRadius),
        ),
        child: child,
      );
    }
    // Over a PlatformView, route any radius-expressible shape (oval →
    // circle/stadium, rounded rect, vertical variants) through ClipRRect so the
    // clip is forwarded to the PlatformView mutator and a descendant
    // BackdropFilter is bounded to the shape — eliminating the rectangular halo.
    // #177551 only forwards ClipRRect, never ClipPath.
    if (platformViewBackdrop) {
      final borderRadius = AdaptiveGlass._borderRadiusFromShape(shape);
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius, child: child);
      }
    }
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: child,
    );
  }
}
