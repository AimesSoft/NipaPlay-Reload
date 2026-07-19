import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'theme/glass_theme.dart';
import 'theme/glass_theme_data.dart';
import 'types/glass_quality.dart';
import 'utils/accessibility_config.dart' as glass_config;
import 'utils/glass_performance_monitor.dart';
import 'src/renderer/liquid_glass_renderer.dart';
import 'src/renderer/shaders.dart';
import 'src/renderer/internal/multi_shader_builder.dart';
import 'widgets/shared/glass_adaptive_scope.dart';
import 'widgets/shared/glass_effect.dart';
import 'widgets/shared/glass_accessibility_scope.dart';
import 'widgets/shared/lightweight_liquid_glass.dart';

/// Entry point and configuration for the Liquid Glass Widgets library.
///
/// ## Setup
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await LiquidGlassWidgets.initialize(); // pre-warms shaders
///
///   runApp(LiquidGlassWidgets.wrap(
///     child: const MyApp(),
///     adaptiveQuality: true,
///     theme: GlassThemeData(
///       light: GlassThemeVariant(settings: GlassThemeSettings(blur: 10)),
///       dark:  GlassThemeVariant(settings: GlassThemeSettings(blur: 14)),
///     ),
///   ));
/// }
/// ```
class LiquidGlassWidgets {
  LiquidGlassWidgets._();

  // ── Global accessors ───────────────────────────────────────────────────────

  /// Whether glass widgets automatically respect system accessibility settings
  /// (Reduce Motion, Reduce Transparency / High Contrast).
  ///
  /// Set via [wrap]. Defaults to `true`. Read by glass widgets at build time
  /// via [GlassAccessibilityScope] or a direct [MediaQuery] fallback.
  ///
  /// The setter is provided as an escape hatch for tests and advanced runtime
  /// overrides. In production code, prefer setting this through [wrap].
  static bool get respectSystemAccessibility =>
      glass_config.respectSystemAccessibility;
  static set respectSystemAccessibility(bool value) =>
      glass_config.respectSystemAccessibility = value;

  /// Deprecated — use [respectSystemAccessibility] instead.
  ///
  /// Retained for discoverability (the two-word form reads naturally as a
  /// boolean predicate). Will be removed in v1.0.
  @Deprecated('Use respectSystemAccessibility instead.')
  static bool get respectsAccessibility => respectSystemAccessibility;
  @Deprecated('Use respectSystemAccessibility instead.')
  static set respectsAccessibility(bool value) =>
      respectSystemAccessibility = value;

  /// Global [LiquidGlassSettings] override for the entire application.
  ///
  /// When set, these settings are used as the base for all glass widgets
  /// unless overridden at the widget or layer level.
  static LiquidGlassSettings? globalSettings;

  // ── initialize() ───────────────────────────────────────────────────────────

  /// Initializes platform-level resources for the Liquid Glass library.
  ///
  /// **Responsibility**: async platform / engine setup only. Call once in
  /// `main()` before [runApp]. All behavioral configuration belongs in [wrap].
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await LiquidGlassWidgets.initialize();
  ///   runApp(LiquidGlassWidgets.wrap(const MyApp()));
  /// }
  /// ```
  ///
  /// ### Parameters
  ///
  /// **`enablePerformanceMonitor`** (default `true`)\
  /// In debug and profile builds, the library registers a
  /// `SchedulerBinding.addTimingsCallback` that watches raster durations while
  /// [GlassQuality.premium] surfaces are mounted. When frames consistently
  /// exceed the GPU budget, a single [FlutterError] is emitted with actionable
  /// guidance. The monitor is **automatically disabled in release builds** —
  /// zero overhead in shipped apps. Set to `false` to suppress it during
  /// profiling sessions where the warning would be a false positive.
  ///
  /// ### Tasks performed
  ///
  /// 1. Pre-warms / precaches the lightweight fragment shader.
  /// 2. Pre-warms the interactive indicator shader (custom refraction).
  /// 3. Pre-warms the Impeller rendering pipeline (iOS / Android / macOS).
  /// 4. Optionally registers the debug performance monitor.
  ///
  /// ### Shaders pre-warmed
  ///
  /// | Shader | Role |
  /// |---|---|
  /// | `lightweight_glass.frag` | Minimal glass layer |
  /// | `interactive_indicator.frag` | Custom refraction effect |
  /// | `liquid_glass_geometry_blended.frag` | Geometry / SDF pass |
  /// | `liquid_glass_final_render.frag` | Final composite pass |
  static Future<void> initialize({
    bool enablePerformanceMonitor = true,
  }) async {
    debugPrint('[LiquidGlass] Initializing library...');

    // 1. Pre-warm shader programs in parallel — prevents first-frame jank /
    //    "white flash" when glass widgets first appear.
    //
    //    Only shader disk-loads are awaited here (the only work that MUST
    //    complete before runApp, since a missing program causes a white flash).
    //
    //    The Impeller pipeline warm-up is scheduled post-first-frame instead —
    //    the splash screen or first non-glass frame provides enough GPU idle
    //    time for pipeline compilation without blocking runApp.
    await Future.wait([
      LightweightLiquidGlass.preWarm(),
      GlassEffect.preWarm(),
      MultiShaderBuilder.precacheShaders([
        ShaderKeys.blendedGeometry,
        ShaderKeys.liquidGlassRender,
      ]),
    ]);

    // 2. Schedule Impeller pipeline warm-up after the first frame — zero
    //    startup cost. The first non-glass frame (e.g. splash screen) provides
    //    ample idle GPU time for the driver to compile the Vulkan pipeline.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _warmUpImpellerPipeline());

    // 3. Register the debug performance monitor (no-op in release builds).
    if (enablePerformanceMonitor && !kReleaseMode) {
      GlassPerformanceMonitor.start();
    }

    debugPrint('[LiquidGlass] Initialization complete.');
  }

  // ── wrap() ─────────────────────────────────────────────────────────────────

  /// Wraps [child] in the Liquid Glass infrastructure scopes and applies all
  /// behavioral configuration.
  ///
  /// **Responsibility**: widget-tree composition and runtime behavior. All
  /// configuration that affects how glass widgets behave lives here — explicit,
  /// visible, and co-located with the widget tree entry point.
  ///
  /// **Optional** — provides app-wide theming and adaptive quality.
  /// `GlassBackdropScope` is no longer needed (each glass layer manages its own
  /// backdrop); `wrap()` is only required if you use `theme:` or
  /// `adaptiveQuality:`.
  ///
  /// ```dart
  /// // Zero-config (most apps):
  /// runApp(LiquidGlassWidgets.wrap(const MyApp()));
  ///
  /// // Recommended for Android / broad device support:
  /// runApp(LiquidGlassWidgets.wrap(
  ///   child: const MyApp(),
  ///   adaptiveQuality: true,
  ///   theme: GlassThemeData(...),
  /// ));
  ///
  /// // Game / experience — bypass accessibility, conservative quality start:
  /// runApp(LiquidGlassWidgets.wrap(
  ///   child: const MyApp(),
  ///   respectSystemAccessibility: false,
  ///   adaptiveQuality: true,
  ///   adaptiveConfig: GlassAdaptiveScopeConfig(
  ///     initialQuality: GlassQuality.standard,
  ///     allowStepUp: true,
  ///   ),
  /// ));
  /// ```
  ///
  /// ### Parameters
  ///
  /// **`respectSystemAccessibility`** (default `true`)\
  /// When `true`, system Reduce Motion and Reduce Transparency flags are
  /// respected automatically — no extra setup required. All glass widgets read
  /// `MediaQuery` directly and degrade gracefully. Set to `false` to ignore
  /// system accessibility flags globally (e.g. for a game where full glass
  /// fidelity is intentional regardless of OS settings). A
  /// [GlassAccessibilityScope] placed anywhere in the widget tree always takes
  /// precedence over this flag, allowing per-subtree overrides.
  ///
  /// **`adaptiveQuality`** (default `false`, **experimental**)\
  /// When `true`, inserts a root [GlassAdaptiveScope] that automatically
  /// benchmarks the device and adjusts the global glass quality ceiling in real
  /// time. Three phases:
  ///
  /// - **Phase 1** (synchronous): forces `minimal` where shaders are
  ///   unsupported; caps at `standard` on web.
  /// - **Phase 2** (~180 frames ≈ 3 s at 60 fps): measures real P75 raster
  ///   durations and sets the initial quality tier.
  /// - **Phase 3** (ongoing, near-zero overhead): degrades when P95 exceeds
  ///   1.5× the frame budget for 3 consecutive windows; recovers when P95
  ///   drops below 0.6× budget for 10 consecutive windows.
  ///
  /// **Experimental in 0.8.0** — Phase 2 thresholds (12 ms / 20 ms P75) are
  /// based on reasoning, not yet validated across the full Android device
  /// landscape. Enable this feature and report unexpected quality degradation
  /// or promotion to help us tune the thresholds.
  ///
  /// Acts as an app-wide *quality ceiling* — individual widgets with an
  /// explicit `quality:` parameter are still capped by it. When no
  /// [adaptiveConfig] is provided, the scope starts at [GlassQuality.standard]
  /// to prevent jank during the warm-up window on mid-range devices.
  ///
  /// For per-screen control, use [GlassAdaptiveScope] directly in the tree.

  ///
  /// **`adaptiveConfig`** (optional)\
  /// Custom [GlassAdaptiveScopeConfig] for the root [GlassAdaptiveScope].
  /// Ignored when [adaptiveQuality] is `false`. Defaults to
  /// `GlassAdaptiveScopeConfig(initialQuality: GlassQuality.standard)`.
  ///
  /// ### Scope nesting order (outermost → innermost → child)
  ///
  /// `GlassAdaptiveScope` (when enabled) → `GlassTheme` (when provided) → `child`
  static Widget wrap({
    required Widget child,
    GlassThemeData? theme,
    bool respectSystemAccessibility = true,
    bool adaptiveQuality = false,
    GlassAdaptiveScopeConfig? adaptiveConfig,
  }) {
    // Apply global accessibility preference.
    glass_config.respectSystemAccessibility = respectSystemAccessibility;

    Widget result = child;

    if (theme != null) {
      result = GlassTheme(data: theme, child: result);
    }

    if (adaptiveQuality) {
      // When no adaptiveConfig is given: GlassAdaptiveScope.initState() seeds
      // the first frame at GlassQuality.standard while Phase 2 benchmarks the
      // device (~3 s). Phase 2 then promotes to `premium` if the device passes
      // the warmup threshold — no caller config needed.
      //
      // When the caller provides adaptiveConfig: use their settings as-is.
      // If initialQuality is null, Phase 2 still runs fresh and promotes/demotes
      // from the conservative standard starting point.
      final config = adaptiveConfig ?? const GlassAdaptiveScopeConfig();

      result = GlassAdaptiveScope(
        minQuality: config.minQuality,
        maxQuality: config.maxQuality,
        initialQuality: config.initialQuality,
        targetFrameMs: config.targetFrameMs,
        allowStepUp: config.allowStepUp,
        onQualityChanged: config.onQualityChanged,
        onDiagnostic: config.onDiagnostic,
        debugLogDiagnostics: config.debugLogDiagnostics,
        child: result,
      );
    }

    return result;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Warms up the Impeller rendering pipeline for glass effects.
  ///
  /// Instantiates a minimal [LiquidGlassLayer] to trigger Impeller pipeline
  /// compilation — eliminating first-frame jank when glass effects appear.
  /// Skipped on Skia / Web where Impeller is not active.
  ///
  /// Called via [addPostFrameCallback] from [initialize], so it runs after
  /// the first frame rather than blocking [runApp]. The first non-glass frame
  /// (splash screen, loading state) provides natural GPU idle time for driver
  /// pipeline compilation without any artificial delay.
  static void _warmUpImpellerPipeline() {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      debugPrint('[LiquidGlass] Skipping Impeller warm-up (Skia/Web detected)');
      return;
    }

    try {
      const warmUpSettings = LiquidGlassSettings(
        blur: 3,
        thickness: 30,
        refractiveIndex: 1.5,
      );

      // Instantiating the layer registers the shader programs with the
      // Impeller engine and kicks off async driver pipeline compilation.
      // No artificial delay needed — the post-frame scheduling ensures the
      // engine is in a stable state to accept the compilation work.
      final _ = LiquidGlassLayer(
        settings: warmUpSettings,
        child: const SizedBox.shrink(),
      );

      debugPrint('[LiquidGlass] ✓ Impeller pipeline warm-up scheduled');
    } catch (e) {
      debugPrint('[LiquidGlass] Impeller warm-up failed (non-critical): $e');
    }
  }
}
