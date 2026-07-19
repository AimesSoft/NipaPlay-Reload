import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../src/renderer/liquid_glass_renderer.dart';

import '../../theme/glass_theme_data.dart';
import '../../types/glass_quality.dart';
import '../../types/glass_button_style.dart';
import '../shared/adaptive_glass.dart';
import '../../theme/glass_theme_helpers.dart';
import '../surfaces/glass_app_bar.dart';

/// Glass morphism button with scale animation and glow effects.
///
/// This button provides a complete liquid glass experience with:
/// - Liquid glass visual effect with customizable settings
/// - Scale animation (squash & stretch) when pressed
/// - Touch-responsive glow effect on interaction (Impeller) or shader-based
///   glow (Skia)
/// - Full control over all animation and visual properties
/// - Accessibility support with semantic labels
/// - Flexible content support (icon or custom child)
///
/// ## Platform Rendering
///
/// The glow effect adapts to the platform:
/// - **Impeller**: Uses advanced compositing via [GlassGlow]
/// - **Skia/Web**: Animates shader saturation parameter for frosted glow
///
/// ## Usage Modes
///
/// ### Grouped Mode (default)
/// Uses [LiquidGlass.grouped] and inherits settings from parent
/// [LiquidGlassLayer]:
/// ```dart
/// AdaptiveLiquidGlassLayer(
///   settings: LiquidGlassSettings(...),
///   child: Column(
///     children: [
///       GlassButton(
///         icon: Icon(CupertinoIcons.heart),
///         onTap: () => print('Favorite'),
///       ),
///     ],
///   ),
/// )
/// ```
///
/// ### Standalone Mode
/// Creates its own layer with [LiquidGlass.withOwnLayer]:
/// ```dart
/// GlassButton(
///   icon: Icon(CupertinoIcons.play),
///   onTap: () => print('Play'),
///   useOwnLayer: true,
///   settings: LiquidGlassSettings(
///     thickness: 0.3,
///     blurRadius: 20,
///   ),
/// )
/// ```
///
/// ## Customization Examples
///
/// ### Custom stretch behavior:
/// ```dart
/// GlassButton(
///   icon: Icon(CupertinoIcons.star),
///   onTap: () {},
///   interactionScale: 1.1,  // Grow 10% when pressed
///   stretch: 0.8,           // More dramatic stretch
///   resistance: 0.15,       // Higher drag resistance
/// )
/// ```
///
/// ### Custom glow effect:
/// ```dart
/// GlassButton(
///   icon: Icon(CupertinoIcons.bolt),
///   onTap: () {},
///   glowColor: Colors.blue.withOpacity(0.4),
///   glowRadius: 1.5,  // Larger glow
/// )
/// ```
///
/// ### Custom content:
/// ```dart
/// GlassButton.custom(
///   onTap: () {},
///   width: 120,
///   height: 48,
///   child: Text('Click Me', style: TextStyle(color: Colors.white)),
/// )
/// ```
///
/// ## Navigation bar / toolbar usage
///
/// When multiple buttons share a [LiquidGlassBlendGroup] (e.g. inside an
/// [AdaptiveLiquidGlassLayer]), the drag-follow animation physically moves each
/// button's glass shape in the shader's coordinate space. Because the blend
/// group treats all shapes as a connected liquid surface, dragging one button
/// causes neighboring buttons to visually respond — this is intentional for
/// isolated floating buttons, but can feel jarring in a nav bar.
///
/// Reduce [stretch] for tightly-grouped buttons to keep the tactile press feel
/// without excessive cross-button coupling:
///
/// ```dart
/// // Nav bar / toolbar — subtle liquid feel, minimal coupling
/// GlassButton(
///   stretch: 0.15,
///   icon: Icon(CupertinoIcons.home),
///   onTap: () {},
/// )
///
/// // Standalone FAB — full liquid feel (default)
/// GlassButton(
///   icon: Icon(CupertinoIcons.add),
///   onTap: () {},
/// )
/// ```
///
/// Setting [stretch] to `0.0` disables drag-following entirely while keeping
/// the press-scale effect ([interactionScale]).
class GlassButton extends StatefulWidget {
  /// Creates a glass button with an icon.
  const GlassButton({
    required this.icon,
    required this.onTap,
    super.key,
    this.label = '',
    this.width = 56,
    this.height = 56,
    this.iconSize = 24.0,
    this.iconColor,
    this.shape = const LiquidOval(),
    this.settings,
    this.useOwnLayer = false,
    this.quality,
    // LiquidStretch properties
    this.interactionScale = 1.05,
    this.stretch = 0.5,
    this.resistance = 0.01,
    this.stretchHitTestBehavior = HitTestBehavior.opaque,
    // GlassGlow properties
    this.glowColor,
    this.glowRadius = 1.0,
    this.glowBlurRadius,
    this.glowSpreadRadius,
    this.glowOpacity,
    this.glowHitTestBehavior = HitTestBehavior.opaque,
    this.enabled = true,
    this.style = GlassButtonStyle.filled,
    this.persistPressOnDrag = true,
    this.anchorStretch = true,
    this.anchorStretchSettings = const AnchorStretchSettings(),
    this.alignment = Alignment.center,
    this.ambientBaseLight = 0.08,
    this.platformViewBackdrop = false,
  }) : child = null;

  /// Creates a glass button with custom content.
  ///
  /// This allows you to use any widget as the button's content instead of
  /// just an icon. Useful for text buttons, composite content, etc.
  ///
  /// Example:
  /// ```dart
  /// GlassButton.custom(
  ///   onTap: () {},
  ///   width: 120,
  ///   height: 48,
  ///   child: Row(
  ///     mainAxisAlignment: MainAxisAlignment.center,
  ///     children: [
  ///       Icon(CupertinoIcons.play, size: 16),
  ///       SizedBox(width: 8),
  ///       Text('Play'),
  ///     ],
  ///   ),
  /// )
  /// ```
  const GlassButton.custom({
    required this.child,
    required this.onTap,
    super.key,
    this.label = '',
    this.width,
    this.height,
    this.shape = const LiquidOval(),
    this.settings,
    this.useOwnLayer = false,
    this.quality,
    // LiquidStretch properties
    this.interactionScale = 1.05,
    this.stretch = 0.5,
    this.resistance = 0.01,
    this.stretchHitTestBehavior = HitTestBehavior.opaque,
    // GlassGlow properties
    this.glowColor,
    this.glowRadius = 1.0,
    this.glowBlurRadius,
    this.glowSpreadRadius,
    this.glowOpacity,
    this.glowHitTestBehavior = HitTestBehavior.opaque,
    this.enabled = true,
    this.style = GlassButtonStyle.filled,
    this.persistPressOnDrag = true,
    this.anchorStretch = true,
    this.anchorStretchSettings = const AnchorStretchSettings(),
    this.alignment = Alignment.center,
    this.ambientBaseLight = 0.08,
    this.platformViewBackdrop = false,
  })  : icon = null,
        iconSize = 24.0,
        iconColor = null;

  // ===========================================================================
  // Content Properties
  // ===========================================================================

  /// The widget to display in the button.
  ///
  /// Mutually exclusive with [child]. Pass any widget — standard [Icon]
  /// widgets will inherit color and size from [iconColor] and [iconSize]
  /// via [IconTheme]. Custom widgets handle their own styling.
  final Widget? icon;

  /// Custom widget to display in the button.
  ///
  /// Mutually exclusive with [icon]. Use [GlassButton.custom] constructor
  /// to provide custom content.
  final Widget? child;

  /// Size of the icon (only used when [icon] is provided).
  ///
  /// Defaults to 24.0.
  final double iconSize;

  /// Color of the icon (only used when [icon] is provided).
  ///
  /// Defaults to [CupertinoColors.white] for prominent buttons, and [CupertinoColors.label] otherwise.
  final Color? iconColor;

  // ===========================================================================
  // Button Properties
  // ===========================================================================

  /// Callback when the button is tapped.
  ///
  /// If [enabled] is false, this callback will not be invoked.
  final VoidCallback onTap;

  /// Whether the button is enabled.
  ///
  /// When false, the button will be visually disabled and [onTap] will not
  /// be invoked. The button will render with reduced opacity.
  ///
  /// Defaults to true.
  final bool enabled;

  /// Semantic label for accessibility.
  ///
  /// This label is announced by screen readers to describe the button's
  /// purpose. If empty, the button's visual content is used instead.
  ///
  /// Defaults to an empty string.
  final String label;

  /// Width of the button in logical pixels.
  ///
  /// When `null`, the button will size itself based on parent constraints
  /// (e.g. expanding to fill an [Expanded] widget).
  ///
  /// The default [GlassButton] constructor sets this to 56.0 for icon buttons.
  /// The [GlassButton.custom] constructor defaults to `null` so the button
  /// respects flexible parent layouts.
  final double? width;

  /// Height of the button in logical pixels.
  ///
  /// Defaults to 56.0.
  final double? height;

  // ===========================================================================
  // Glass Effect Properties
  // ===========================================================================

  /// Shape of the glass button.
  ///
  /// Can be [LiquidOval], [LiquidRoundedRectangle], or
  /// [LiquidRoundedSuperellipse].
  ///
  /// Defaults to [LiquidOval].
  final LiquidShape shape;

  /// Glass effect settings for the button.
  ///
  /// Controls the visual appearance of the glass effect including thickness,
  /// blur radius, color tint, lighting, and more.
  ///
  /// If null, settings are inherited from [DefaultButtonSettings] (set via
  /// [GlassAppBar.buttonSettings]), then from the page-level glass layer,
  /// then from the app-level [GlassTheme].
  final LiquidGlassSettings? settings;

  /// Whether to create its own layer or use grouped glass within an existing
  /// layer.
  ///
  /// - `false` (default): Uses [LiquidGlass.grouped], must be inside a
  /// [LiquidGlassLayer].
  ///   This is more performant when you have multiple glass elements that
  ///   can share the same rendering context.
  ///
  /// - `true`: Uses [LiquidGlass.withOwnLayer], can be used anywhere.
  ///   Creates an independent glass rendering context for this button.
  ///
  /// Defaults to false.
  final bool useOwnLayer;

  /// Rendering quality for the glass effect.
  ///
  /// Defaults to [GlassQuality.standard], which uses backdrop filter rendering.
  /// This works reliably in all contexts, including scrollable lists.
  ///
  /// Use [GlassQuality.premium] for the full Impeller shader pipeline. When using
  /// premium quality on a standalone button (outside of an [AdaptiveLiquidGlassLayer]
  /// or [LiquidGlassLayer]), you **must** also set [useOwnLayer] to `true`.
  /// Without it, the button has no ancestor layer to render against and will show
  /// an assertion error in debug mode (graceful pass-through in release).
  ///
  /// ```dart
  /// // ✓ Correct — standalone premium button
  /// GlassButton(
  ///   quality: GlassQuality.premium,
  ///   useOwnLayer: true,
  ///   icon: Icon(CupertinoIcons.play),
  ///   onTap: () {},
  /// )
  ///
  /// // ✓ Also correct — inside an AdaptiveLiquidGlassLayer (no useOwnLayer needed)
  /// AdaptiveLiquidGlassLayer(
  ///   quality: GlassQuality.premium,
  ///   child: GlassButton(
  ///     icon: Icon(CupertinoIcons.play),
  ///     onTap: () {},
  ///   ),
  /// )
  /// ```
  final GlassQuality? quality;

  /// The visual style of the button.
  ///
  /// Use [GlassButtonStyle.transparent] when grouping buttons to avoid
  /// double-drawing glass backgrounds.
  final GlassButtonStyle style;

  // ===========================================================================
  // LiquidStretch Properties (Animation & Interaction)
  // ===========================================================================

  /// The scale factor to apply when the user is interacting with the button.
  ///
  /// - 1.0 means no scaling
  /// - Greater than 1.0 means the button will grow (e.g., 1.05 = 5% larger)
  /// - Less than 1.0 means the button will shrink
  ///
  /// This creates a satisfying "press down" effect when the button is touched.
  ///
  /// Defaults to 1.05.
  final double interactionScale;

  /// The factor to multiply the drag offset by to determine the stretch amount.
  ///
  /// Controls how much the button stretches in response to drag gestures:
  /// - 0.0 means no stretch
  /// - 1.0 means the stretch matches the drag offset exactly (usually too much)
  /// - 0.5 (default) provides a balanced, natural stretch effect
  ///
  /// Higher values create more dramatic squash and stretch animations.
  ///
  /// Defaults to 0.5.
  final double stretch;

  /// The resistance factor to apply to the drag offset.
  ///
  /// Controls how "sticky" the drag feels. Higher values create more
  /// resistance, making the button feel heavier and more sluggish. Lower
  /// values make it feel lighter and more responsive.
  ///
  /// Uses non-linear damping that increases with distance from the rest
  /// position.
  ///
  /// Defaults to 0.01.
  final double resistance;

  /// The hit test behavior for the stretch gesture listener.
  ///
  /// Controls how the stretch effect responds to touches:
  /// - [HitTestBehavior.opaque]: Consumes all touches (default)
  /// - [HitTestBehavior.translucent]: Allows touches to pass through
  /// - [HitTestBehavior.deferToChild]: Only responds when touching the child
  ///
  /// Defaults to [HitTestBehavior.opaque].
  final HitTestBehavior stretchHitTestBehavior;

  // ===========================================================================
  // GlassGlow Properties (Touch Effects)
  // ===========================================================================

  /// The color of the glow effect.
  ///
  /// The glow will have this color's opacity at the center and fade to fully
  /// transparent at the edge. Use semi-transparent colors for best results.
  ///
  /// If null, uses the primary glow color from [GlassTheme].
  ///
  /// Common values:
  /// - [Colors.white24]: Subtle white glow
  /// - [Colors.blue.withOpacity(0.3)]: Blue glow
  /// - [Colors.transparent]: Disables glow effect
  ///
  /// Defaults to null (uses theme).
  final Color? glowColor;

  /// The radius of the glow effect relative to the layer's shortest side.
  ///
  /// - 1.0 (default): Glow radius equals the shortest dimension of the button
  /// - 0.5: Glow radius is half the shortest dimension
  /// - 2.0: Glow radius is twice the shortest dimension
  ///
  /// Larger values create a more diffuse, spread-out glow.
  ///
  /// Defaults to 1.0.
  final double glowRadius;

  /// Additional Gaussian blur sigma applied to the glow halo.
  ///
  /// If null, the value from [GlassThemeData.glowColorsFor] is used.
  /// Pass 0 to disable blur. Values of 4–16 create a diffuse halo.
  final double? glowBlurRadius;

  /// Extra glow circle spread as a fraction of the layer's shortest side.
  ///
  /// If null, the value from [GlassThemeData.glowColorsFor] is used.
  final double? glowSpreadRadius;

  /// Master opacity multiplier (0–1) applied on top of [glowColor]'s alpha.
  ///
  /// If null, the value from [GlassThemeData.glowColorsFor] is used.
  final double? glowOpacity;

  /// The hit test behavior for the glow gesture listener.
  ///
  /// Controls how the glow effect responds to touches:
  /// - [HitTestBehavior.opaque]: Consumes all touches (default)
  /// - [HitTestBehavior.translucent]: Allows touches to pass through
  /// - [HitTestBehavior.deferToChild]: Only responds when touching the child
  ///
  /// Defaults to [HitTestBehavior.opaque].
  final HitTestBehavior glowHitTestBehavior;

  /// Whether the pressed glass distortion persists while the finger is held
  /// down, even if dragged far away from the button.
  ///
  /// - `true` (default): The distortion and glow stay active for the entire
  ///   duration the finger is on screen, matching iOS 26 toolbar/navigation
  ///   buttons (Weather app, Maps, etc.). The button stretches with a jelly
  ///   feel and maintains its pressed visual state until the finger lifts.
  ///
  /// - `false`: The distortion cancels when the finger moves beyond the tap
  ///   tolerance (~18 logical pixels), matching iOS 26 lock screen buttons
  ///   (camera, torch) that snap back if you drag away.
  ///
  /// Defaults to true.
  final bool persistPressOnDrag;

  /// Whether the stretch anchors the button in place.
  ///
  /// When `true` (default), the button stays fixed and elongates toward
  /// the finger — matching iOS 26 button behaviour.
  /// When `false`, the button follows the finger (jelly-follow mode).
  ///
  /// Defaults to `true`.
  ///
  /// See [LiquidStretch.anchorStretch].
  final bool anchorStretch;

  /// Fine-tuning for the anchor stretch effect.
  ///
  /// Controls intensity, squash, translation damping, and bounciness.
  /// Most developers won’t need to change these — the defaults match
  /// iOS 26 button behaviour.
  ///
  /// See [AnchorStretchSettings] for details.
  final AnchorStretchSettings anchorStretchSettings;

  /// How to align the child content within the button bounds.
  ///
  /// Defaults to [Alignment.center], which is correct for icon buttons.
  /// Use [Alignment.topLeft] or similar for custom card-style layouts.
  final AlignmentGeometry alignment;

  /// Opacity of the ambient base light when the button is pressed.
  ///
  /// iOS 26 buttons maintain a subtle overall surface brightness when active,
  /// in addition to the directional glow that follows the finger. This
  /// prevents the button from going dark when the finger drags the directional
  /// highlight off-edge.
  ///
  /// - 0.0: No ambient base light (button goes dark off-edge)
  /// - 0.08 (default): Subtle surface luminosity matching iOS 26
  /// - 0.15: Noticeably brighter surface
  ///
  /// Set to 0.0 to disable.
  final double ambientBaseLight;

  /// When true (typically for iOS PlatformViews), forces the BackdropFilter
  /// fallback render path instead of the Impeller-native shader. Forwarded to
  /// the underlying [AdaptiveGlass].
  final bool platformViewBackdrop;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _saturationController;
  late final Animation<double> _saturationAnimation;

  @override
  void initState() {
    super.initState();
    _saturationController = AnimationController(
      duration: const Duration(milliseconds: 50), // Fast, instant response
      vsync: this,
    );
    _saturationAnimation = CurvedAnimation(
      parent: _saturationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _saturationController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Tap-based pressed state (persistPressOnDrag: false)
  // Used by lock screen camera/torch buttons — cancels on drag.
  //
  // All press handlers below guard on `mounted` before touching
  // [_saturationController]: a button can be DISPOSED mid-press — e.g. a
  // collapsing nav mini-bar removed by the very tap that expands it — after which
  // a queued pointerUp / pointerCancel still dispatches here and would call
  // `.reverse()` on the disposed controller, throwing
  // `AnimationController.reverse() called after dispose()` (assert `_ticker != null`).
  // ---------------------------------------------------------------------------

  void _handleTapDown(TapDownDetails details) {
    if (!mounted || !widget.enabled) return;
    _saturationController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (!mounted || !widget.enabled) return;
    _saturationController.reverse();
  }

  void _handleTapCancel() {
    if (!mounted || !widget.enabled) return;
    _saturationController.reverse();
  }

  // ---------------------------------------------------------------------------
  // Pointer-based pressed state (persistPressOnDrag: true)
  // Used by toolbar/nav buttons — distortion persists while finger is down.
  // Raw Listener tracks the pointer until pointerUp/Cancel regardless of
  // distance, matching iOS 26 Weather/Maps button behaviour.
  // ---------------------------------------------------------------------------

  void _handlePointerDown(PointerDownEvent event) {
    if (!mounted || !widget.enabled) return;
    _saturationController.forward();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!mounted || !widget.enabled) return;
    _saturationController.reverse();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (!mounted || !widget.enabled) return;
    _saturationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve quality and theme — hoisted here so stretchWidget can branch on quality
    final effectiveQuality = GlassThemeHelpers.resolveQuality(
      context,
      widgetQuality: widget.quality,
    );

    final resolvedGlowColors =
        GlassThemeData.of(context).glowColorsFor(context);
    final effectiveGlowColor = widget.glowColor ??
        resolvedGlowColors.primary ??
        CupertinoTheme.of(context)
            .textTheme
            .textStyle
            .color
            ?.withValues(alpha: 0.24) ??
        CupertinoColors.white.withValues(alpha: 0.24);
    final effectiveGlowBlurRadius =
        widget.glowBlurRadius ?? resolvedGlowColors.glowBlurRadius;
    final effectiveGlowSpreadRadius =
        widget.glowSpreadRadius ?? resolvedGlowColors.glowSpreadRadius;
    final effectiveGlowOpacity =
        widget.glowOpacity ?? resolvedGlowColors.glowOpacity;

    // Build the content widget (either icon or custom child)
    final contentWidget = SizedBox(
      height: widget.height,
      width: widget.width,
      child: Align(
        alignment: widget.alignment,
        widthFactor: widget.width == null ? 1.0 : null,
        heightFactor: widget.height == null ? 1.0 : null,
        child: widget.child ??
            IconTheme(
              data: IconThemeData(
                color: widget.iconColor ??
                    (widget.style == GlassButtonStyle.prominent
                        ? CupertinoColors.white
                        : (CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .color ??
                            CupertinoColors.label)),
                size: widget.iconSize,
              ),
              child: widget.icon ?? const SizedBox.shrink(),
            ),
      ),
    );

    // 2. Build the inner content (Ambient base + Glow + Icon/Child)
    //
    // The ambient base light provides a subtle surface brightness when pressed,
    // matching iOS 26 where active buttons never go completely dark even when
    // the directional glow follows the finger off-edge.
    final ambientOverlay = widget.ambientBaseLight > 0
        ? AnimatedBuilder(
            animation: _saturationAnimation,
            builder: (context, _) {
              final opacity =
                  _saturationAnimation.value * widget.ambientBaseLight;
              if (opacity <= 0) return const SizedBox.shrink();
              return Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: CupertinoColors.white.withValues(alpha: opacity),
                  ),
                ),
              );
            },
          )
        : null;

    final contentWithAmbient = ambientOverlay != null
        ? Stack(
            alignment: widget.alignment,
            children: [
              contentWidget,
              ambientOverlay,
            ],
          )
        : contentWidget;

    // This part is static relative to the glass saturation pulse
    final glowContent = GlassGlow(
      glowColor: effectiveGlowColor,
      glowRadius: widget.glowRadius,
      glowBlurRadius: effectiveGlowBlurRadius,
      glowSpreadRadius: effectiveGlowSpreadRadius,
      glowOpacity: effectiveGlowOpacity,
      hitTestBehavior: widget.glowHitTestBehavior,
      child: contentWithAmbient,
    );

    // 3. Animate ONLY the glass settings that change during interaction
    final glassWidget = AnimatedBuilder(
      animation: _saturationAnimation,
      child: glowContent,
      builder: (context, child) {
        if (widget.style == GlassButtonStyle.transparent) {
          // Clip interaction glow to the button's shape so it doesn't
          // bleed into a rectangle.
          return ClipPath(
            clipper: _ExpandedShapeClipper(shape: widget.shape, expansion: 0),
            clipBehavior: Clip.antiAlias,
            child: child!,
          );
        }

        // Resolve settings: widget explicit → app bar default → inherited.
        final effectiveExplicit =
            widget.settings ?? DefaultButtonSettings.of(context);
        var baseSettings = GlassThemeHelpers.resolveSettings(
          context,
          explicit: effectiveExplicit,
        );

        // Prominent style: thicker, more opaque, brighter glass for primary CTAs.
        // iOS 26's `.glassProminent` is visibly more frosted than `.glass`.
        if (widget.style == GlassButtonStyle.prominent) {
          baseSettings = baseSettings.copyWith(
            thickness: (baseSettings.effectiveThickness * 2.5).clamp(30, 100),
            glassColor: baseSettings.glassColor.withValues(
                alpha: (baseSettings.glassColor.a * 2.5).clamp(0.4, 0.9)),
            lightIntensity:
                (baseSettings.effectiveLightIntensity * 1.5).clamp(0.3, 1.0),
          );
        }

        // useOwnLayer is passed through to AdaptiveGlass, which automatically
        // promotes interactive elements to own-layer in premium mode (via
        // isInteractive: true). No need to auto-promote here.

        // Pass glow intensity directly to AdaptiveGlass for Skia shader feedback.
        // On Impeller, GlassGlow widget is used instead (separate from glass effect).
        // On Skia/Web, glowIntensity controls shader-based additive brightness.
        return AdaptiveGlass(
          shape: widget.shape,
          settings: baseSettings, // Preserve user's saturation setting!
          quality: effectiveQuality,
          useOwnLayer: widget.useOwnLayer,
          glowIntensity: _saturationAnimation.value, // 0.0-1.0 animation
          isInteractive: true, // Buttons manage their own RepaintBoundary
          platformViewBackdrop: widget.platformViewBackdrop,
          child: child!,
        );
      },
    );

    // 4. Wrap with stretch animation and interaction containers
    // These remain outside the AnimatedBuilder to prevent redundant rebuilds.
    //
    // We skip RepaintBoundary when the button can be stretched. The stretch
    // animation applies a Transform.scale that scales the cached texture:
    //
    // - Minimal: always skipped (vector ClipPath — no bitmap to distort).
    // - Premium + stretch: skipped. Impeller's LiquidGlassLayer compositing
    //   bakes shape edges into the cached texture; scaling that texture causes
    //   bilinear interpolation artefacts. This is a known Impeller limitation
    //   — the fix belongs at the shader/compositing level, not as a per-button
    //   ClipPath workaround. Standard's 2D shader re-executes within the
    //   boundary so it stays sharp.
    // - Premium + no stretch (stretch == 0): kept. No scaling means no
    //   artefacts, and the boundary gives a pure performance win for the
    //   expensive Impeller pipeline.
    // - Standard: always kept. The lightweight shader re-executes at the
    //   correct resolution even inside a RepaintBoundary.

    final bool hasStretch = widget.stretch > 0;
    final bool skipBoundary = effectiveQuality == GlassQuality.minimal ||
        (effectiveQuality == GlassQuality.premium && hasStretch);

    // Resolve interaction settings: explicit widget param > theme > default
    final themeInteraction = GlassThemeData.of(context).interaction;

    final stretchContent = LiquidStretch(
      interactionScale: widget.interactionScale != 1.05
          ? widget.interactionScale
          : themeInteraction.interactionScale ?? widget.interactionScale,
      stretch: widget.stretch != 0.5
          ? widget.stretch
          : themeInteraction.stretch ?? widget.stretch,
      resistance: widget.resistance != 0.01
          ? widget.resistance
          : themeInteraction.resistance ?? widget.resistance,
      hitTestBehavior: widget.stretchHitTestBehavior,
      anchorStretch: widget.anchorStretch != true
          ? widget.anchorStretch
          : themeInteraction.anchorStretch ?? widget.anchorStretch,
      anchorStretchSettings: !identical(
              widget.anchorStretchSettings, const AnchorStretchSettings())
          ? widget.anchorStretchSettings
          : themeInteraction.anchorStretchSettings ??
              widget.anchorStretchSettings,
      child: Semantics(
        button: true,
        label: widget.label.isNotEmpty ? widget.label : null,
        enabled: widget.enabled,
        child: glassWidget,
      ),
    );

    final stretchWidget =
        skipBoundary ? stretchContent : RepaintBoundary(child: stretchContent);

    // Apply opacity when disabled
    final finalWidget = widget.enabled
        ? stretchWidget
        : Opacity(
            opacity: 0.5,
            child: stretchWidget,
          );

    // ---------------------------------------------------------------------------
    // Interaction wrapper: choose between tap-based and pointer-based press
    // tracking depending on persistPressOnDrag.
    //
    // persistPressOnDrag: true  → raw Listener wraps GestureDetector.
    //   The Listener tracks the pointer globally (pointerDown/Up/Cancel)
    //   so the pressed visual persists while the finger is down. The inner
    //   GestureDetector still handles onTap for the callback.
    //
    // persistPressOnDrag: false → GestureDetector handles everything.
    //   onTapDown/Up/Cancel drive the saturation controller, so dragging
    //   away cancels the pressed state (iOS lock screen behavior).
    // ---------------------------------------------------------------------------
    if (widget.persistPressOnDrag) {
      return Listener(
        onPointerDown: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          behavior: HitTestBehavior.opaque,
          child: finalWidget,
        ),
      );
    }

    // Tap-based path (lock screen buttons)
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: finalWidget,
    );
  }
}

/// Clips to a [ShapeBorder]'s outer path, optionally expanded by [expansion]
/// pixels on all sides.
///
/// At rest ([expansion] > 0), the clip is slightly larger than the shape,
/// allowing the glass shader's rim/refraction to extend beyond the strict
/// shape boundary. During stretch interaction ([expansion] → 0), the clip
/// tightens to the exact shape boundary, hiding rasterization artifacts.
class _ExpandedShapeClipper extends CustomClipper<Path> {
  _ExpandedShapeClipper({
    required this.shape,
    this.expansion = 0.0,
  });

  final ShapeBorder shape;
  final double expansion;

  @override
  Path getClip(Size size) {
    if (expansion <= 0) {
      // Tight clip — exact shape boundary.
      return shape.getOuterPath(Offset.zero & size);
    }
    // Expanded clip — inflate the rect so the shape path extends beyond
    // the widget's layout bounds, giving the shader's rim room to render.
    final expandedRect = Rect.fromLTWH(
      -expansion,
      -expansion,
      size.width + expansion * 2,
      size.height + expansion * 2,
    );
    return shape.getOuterPath(expandedRect);
  }

  @override
  bool shouldReclip(_ExpandedShapeClipper oldClipper) =>
      shape != oldClipper.shape || expansion != oldClipper.expansion;
}
