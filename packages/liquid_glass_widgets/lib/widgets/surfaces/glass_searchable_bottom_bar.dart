import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../../src/renderer/liquid_glass_renderer.dart';
import '../../src/types/glass_interaction_behavior.dart';
import '../../types/glass_quality.dart';
import 'glass_bottom_bar.dart'
    show
        GlassTabBarExtraButton,
        GlassBottomBarTab,
        GlassTabPillAnchor,
        MaskingQuality;
import 'shared/glass_search_bar_config.dart';
import 'shared/tab_bar_searchable_controller.dart';
import 'shared/tab_bar_searchable_layout.dart';

export 'shared/glass_search_bar_config.dart';

// =============================================================================
// Public Widget — GlassSearchableBottomBar
// =============================================================================

/// A glass bottom navigation bar with a morphing search pill.
///
/// Visually identical to [GlassBottomBar] but adds a search pill that shares
/// the **same** [AdaptiveLiquidGlassLayer] as the tab pill. This means the
/// two pills correctly liquid-merge at their edges — the same organic blending
/// that makes the tab-bar + extra-button coupling feel native to iOS 26.
///
/// When [isSearchActive] is `false` the widget looks exactly like
/// [GlassBottomBar] with a compact search icon pill at the right edge.
///
/// When [isSearchActive] is `true`:
/// - The tab pill collapses to [GlassSearchBarConfig.collapsedTabWidth].
/// - The search pill expands to fill all remaining space.
/// - Both widths are calculated with [LayoutBuilder] — real pixel values — so
///   Both widths animate with iOS-accurate [SpringSimulation] physics — no null/intrinsic hacks.
///
/// All parameters mirror [GlassBottomBar] exactly, with the additions of
/// [isSearchActive] and [searchConfig].
/// **Deprecated:** Use [GlassTabBar.searchable] instead.
///
/// [GlassSearchableBottomBar] is a zero-logic shim that will be removed in v1.0.
/// Migrate by replacing `GlassSearchableBottomBar(` with `GlassTabBar.searchable(`.
/// All parameters are identical. Replace any `GlassBottomBarTab(` with `GlassSegment(`.
///
/// ```dart
/// // BEFORE
/// GlassSearchableBottomBar(tabs: [...], searchConfig: ..., ...)
/// // AFTER
/// GlassTabBar.searchable(tabs: [...], searchConfig: ..., ...)
/// ```
@Deprecated('Use GlassTabBar.searchable() instead. '
    'GlassSearchableBottomBar will be removed in v1.0. '
    'Migration: replace GlassSearchableBottomBar( with GlassTabBar.searchable(.')
class GlassSearchableBottomBar extends StatelessWidget {
  /// Creates a glass bottom bar with a morphing search pill.
  const GlassSearchableBottomBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.searchConfig,
    super.key,
    this.controller,
    this.isSearchActive = false,
    this.extraButton,
    this.spacing = 8,
    this.horizontalPadding = 20,
    this.verticalPadding = 20,
    this.barHeight = 64,
    this.searchBarHeight = 50,
    this.barBorderRadius = _kDefaultBorderRadius,
    this.tabPadding = const EdgeInsets.symmetric(horizontal: 4),
    this.iconLabelSpacing = 4,
    this.enableBlend = true,
    this.blendAmount = 10,
    this.settings,
    this.showIndicator = true,
    this.indicatorColor,
    this.indicatorSettings,
    this.indicatorPinchStrength = 0.4,
    this.selectedIconColor,
    this.unselectedIconColor,
    this.selectedLabelColor,
    this.unselectedLabelColor,
    this.selectedLabelStyle,
    this.unselectedLabelStyle,
    this.iconSize = 24,
    this.labelFontSize = 11,
    this.textStyle,
    this.glowDuration = const Duration(milliseconds: 300),
    this.glowBlurRadius = 32,
    this.glowSpreadRadius = 8,
    this.glowOpacity = 0.6,
    this.interactionGlowColor,
    this.interactionGlowRadius = 1.5,
    this.quality,
    this.magnification = 1.15,
    this.innerBlur = 0.0,
    this.platformViewBackdrop = false,
    this.maskingQuality = MaskingQuality.high,
    this.backgroundKey,
    this.springDescription,
    this.tabPillAnchor = GlassTabPillAnchor.start,
    // ── Interaction ──────────────────────────────────────────────────────────
    this.interactionBehavior = GlassInteractionBehavior.full,
    this.pressScale = 1.04,
    this.tabWidth,
    this.indicatorBorderRadius,
    this.indicatorExpansion =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.onBarTap,
    // ── Whiten-at-bottom (light-mode legibility) ─────────────────────────────
    this.whitenAtBottom = true,
    this.whitenBottomThreshold = 45.0,
    this.whitenAtBottomTarget = 1.0,
    this.scrollController,
    // ── Content-aware brightness ─────────────────────────────────────────────
    this.adaptiveBrightness = false,
    this.onBrightnessChanged,
    this.brightnessOverride,
  })  : assert(tabs.length > 0,
            'GlassSearchableBottomBar requires at least one tab'),
        assert(
          selectedIndex >= 0 && selectedIndex < tabs.length,
          'selectedIndex must be between 0 and tabs.length - 1',
        ),
        assert(
          tabWidth == null || tabWidth > 0,
          'tabWidth must be positive, or null to use expand (full-width) mode.',
        );

  // ignore: public_member_api_docs
  static const double _kDefaultBorderRadius = 32.0;

  // ── Search ──────────────────────────────────────────────────────────────────
  /// Optional controller to manage the search bar state machine externally.
  ///
  /// When provided, the widget uses this controller's state instead of
  /// creating its own. Useful for programmatic open/close of search,
  /// or for unit testing the layout computation independently.
  ///
  /// The caller owns the controller's lifecycle — [dispose] it when done.
  final SearchableBottomBarController? controller;

  /// Configuration for the morphing search bar behaviour.
  final GlassSearchBarConfig searchConfig;

  /// Custom spring physics for the pill morph animation.
  ///
  /// When null, uses the built-in iOS 26-style spring (stiffness 350, damping 30).
  /// Override to create slower, faster, or more/less bouncy transitions:
  ///
  /// ```dart
  /// springDescription: const SpringDescription(
  ///   mass: 1, stiffness: 200, damping: 40, // slower, minimal overshoot
  /// ),
  /// ```
  final SpringDescription? springDescription;

  /// How the tab pill is anchored horizontally during the morph animation.
  ///
  /// - [GlassTabPillAnchor.start] (default) — the tab pill is pinned to the
  ///   leading edge; the right edge retracts as the pill collapses. This
  ///   matches the default iOS News / Safari behaviour.
  /// - [GlassTabPillAnchor.center] — the tab pill scales symmetrically from
  ///   its centre; both edges collapse inward and expand outward together,
  ///   giving a more balanced look. The search pill will be slightly narrower
  ///   while searching because it starts after the (now centred) collapsed tab.
  final GlassTabPillAnchor tabPillAnchor;

  /// Whether the search bar is currently expanded.
  ///
  /// When `true`, the tab pill collapses and the search pill expands.
  /// Animated using [AnimatedContainer] with iOS spring physics.
  final bool isSearchActive;

  // ── Tab configuration ────────────────────────────────────────────────────────
  /// List of tabs. At least one tab is required.
  final List<GlassBottomBarTab> tabs;

  /// Index of the currently selected tab (0-based).
  final int selectedIndex;

  /// Callback fired when a tab is selected or the draggable indicator is released.
  final ValueChanged<int> onTabSelected;

  // ── Extra button (optional) ──────────────────────────────────────────────────
  /// Optional extra action button shown between the tab pill and the search pill.
  final GlassTabBarExtraButton? extraButton;

  // ── Layout ───────────────────────────────────────────────────────────────────
  /// Spacing between adjacent pills. Defaults to 8.
  final double spacing;

  /// Horizontal padding around the full bar content. Defaults to 20.
  final double horizontalPadding;

  /// Vertical padding (top + bottom) around the bar content. Defaults to 20.
  final double verticalPadding;

  /// Height of the tab pill and search pill. Defaults to 64.
  final double barHeight;

  /// Height of the pills when search is active. Defaults to `50.0`.
  ///
  /// In iOS 26 Apple News the search bar is noticeably shorter than the full
  /// tab bar (which must accommodate icon + label). This default of `50`
  /// replicates that compact, native feel. If you want the bar to remain
  /// the same height, explicitly set this to match your [barHeight].
  ///
  /// The transition is animated with the same easeOut curve used for all
  /// other bar morphs.
  final double searchBarHeight;

  /// Corner radius of both pills. Defaults to 32 (full pill shape).
  final double barBorderRadius;

  /// Internal padding within the tab pill. Defaults to 4 px horizontal.
  final EdgeInsetsGeometry tabPadding;

  /// Vertical spacing between icon and label. Defaults to 4.
  final double iconLabelSpacing;

  /// Whether to enable organic liquid blending between the tab pill,
  /// search pill, and extra button.
  ///
  /// When `true` (default), adjacent glass surfaces merge organically —
  /// a premium "beyond native" effect. When `false`, each element renders
  /// as a fully independent glass surface, matching Apple's native iOS 26
  /// tab bar behavior.
  ///
  /// When disabled, [blendAmount] is ignored.
  final bool enableBlend;

  /// Liquid-glass blend amount for the shared [AdaptiveLiquidGlassLayer].
  ///
  /// Higher values increase the organic blending between adjacent pills.
  /// Only effective when [enableBlend] is `true`.
  /// Defaults to 10.
  final double blendAmount;

  // ── Glass ────────────────────────────────────────────────────────────────────
  /// Custom glass settings. Falls back to identical defaults as [GlassBottomBar].
  final LiquidGlassSettings? settings;

  // ── Whiten-at-bottom (light-mode legibility) ───────────────────────────────
  /// When true (default), the bar lifts its whitening toward
  /// [whitenAtBottomTarget] as the scrolled content nears the bottom of the
  /// page, so a light page stays readable through the bar. Light-mode only;
  /// set false to opt out.
  ///
  /// Inert unless a [scrollController] is provided (the bar needs a scroll
  /// position to watch), so the defaults change nothing for existing callers.
  final bool whitenAtBottom;

  /// Distance (logical px) from the scroll bottom within which the bar is
  /// considered "at the bottom" and whitens. Defaults to 45.
  final double whitenBottomThreshold;

  /// Whiten value the bar lifts to at the bottom. Defaults to 1.0
  /// (fully white).
  final double whitenAtBottomTarget;

  /// Scroll controller for the page beneath the bar. Null (the default)
  /// disables the whiten-at-bottom effect — there is no scroll position to
  /// watch.
  final ScrollController? scrollController;

  // ── Content-aware brightness ────────────────────────────────────────────────
  /// Whether the bar adapts its light/dark appearance to the content
  /// scrolling underneath it, like the iOS 26 system bars.
  ///
  /// Requires an enclosing [GlassContentAwareScope] with the scrolling
  /// content wrapped in a [GlassContentAwareContent]; without one the bar
  /// keeps its ambient appearance. When the scope's contrast vote flips the
  /// verdict, the bar cross-fades between the [GlassTheme] light and dark
  /// variants — themed glass settings, glow palette and the default
  /// icon/label colors all swap automatically.
  ///
  /// Defaults to false.
  final bool adaptiveBrightness;

  /// Called when the content-aware verdict flips (not for the initial
  /// value).
  ///
  /// Use this to restyle elements the bar cannot see — page scrims, status
  /// bar icons, custom-painted tab icons.
  final ValueChanged<Brightness>? onBrightnessChanged;

  /// External brightness source that bypasses the content sampler entirely.
  ///
  /// When non-null, the bar follows this listenable instead of registering
  /// with the [GlassContentAwareScope] — the escape hatch for bars floating
  /// over content that cannot be captured (iOS PlatformViews such as maps;
  /// see [platformViewBackdrop]). Drive it from your own signal, e.g. the
  /// active map style. Implies the adaptive behavior regardless of
  /// [adaptiveBrightness].
  final ValueListenable<Brightness>? brightnessOverride;

  /// Rendering quality. Inherits from parent or defaults to [GlassQuality.premium].
  final GlassQuality? quality;

  // ── Indicator ────────────────────────────────────────────────────────────────
  /// Whether to show the draggable indicator. Defaults to `true`.
  final bool showIndicator;

  /// Base color of the glass indicator. Falls back to theme or a translucent white.
  final Color? indicatorColor;

  /// Custom glass settings for the indicator element.
  final LiquidGlassSettings? indicatorSettings;

  /// Maximum concave lens pinch strength for the draggable indicator pill.
  ///
  /// - `1.0` (default) — full Apple-calibrated pinch
  /// - `0.0` — pinch fully disabled
  final double indicatorPinchStrength;

  // ── Tab style ────────────────────────────────────────────────────────────────
  /// Icon color when a tab is selected. Defaults to dynamic label color.
  final Color? selectedIconColor;

  /// Icon color when a tab is unselected. Defaults to dynamic label color.
  final Color? unselectedIconColor;

  /// Label color for selected tab.
  final Color? selectedLabelColor;

  /// Label color for unselected tabs.
  final Color? unselectedLabelColor;

  /// Per-state label text style, merged over the base label style — overrides
  /// font / weight / letter-spacing while keeping the resolved label color.
  final TextStyle? selectedLabelStyle;

  /// See [selectedLabelStyle].
  final TextStyle? unselectedLabelStyle;

  /// Size of tab icons. Defaults to 24.
  final double iconSize;

  /// Font size for tab labels.
  ///
  /// Only applies when [textStyle] is null. Mirrors [iconSize] as a dedicated
  /// sizing knob so color and weight are still managed automatically.
  ///
  /// Defaults to 11. Reduce to 10 for bars with 4+ tabs or longer labels
  /// such as "Following".
  final double labelFontSize;

  /// Text style for tab labels. Uses 11 pt w600/w500 when null.
  final TextStyle? textStyle;

  // ── Glow ─────────────────────────────────────────────────────────────────────
  /// Duration of the tab glow animation. Defaults to 300 ms.
  final Duration glowDuration;

  /// Blur radius of the glow. Defaults to 32.
  final double glowBlurRadius;

  /// Spread radius of the glow. Defaults to 8.
  final double glowSpreadRadius;

  /// Opacity of the glow at full intensity. Defaults to 0.6.
  final double glowOpacity;

  /// The color of the directional glow effect when interacting with the bar.
  ///
  /// Set to [Colors.transparent] to disable the glow effect.
  final Color? interactionGlowColor;

  /// The radius spread of the directional glow effect when interacting with the bar.
  ///
  /// Defaults to 1.5.
  final double interactionGlowRadius;

  // ── Interaction ───────────────────────────────────────────────────────────────

  /// Controls which physical interaction effects are active when the user
  /// presses the bar.
  ///
  /// Defaults to [GlassInteractionBehavior.full] — directional glow + spring
  /// scale, matching native iOS 26 Apple News / Safari behaviour.
  final GlassInteractionBehavior interactionBehavior;

  /// Peak scale factor applied to the bar at maximum press depth.
  ///
  /// Only active when [interactionBehavior] includes scale
  /// (i.e. [GlassInteractionBehavior.scaleOnly] or [GlassInteractionBehavior.full]).
  ///
  /// Defaults to 1.04 (4% growth — matches iOS 26 Apple News pill).
  final double pressScale;

  // ── Advanced ─────────────────────────────────────────────────────────────────
  /// Magnification factor for the selected indicator lens effect.
  ///
  /// Values > 1.0 zoom in the selected tab's icon and label, creating the
  /// iOS 26 "lens" effect where the active tab appears slightly larger than
  /// its neighbours.
  ///
  /// - `1.15` (default) — matches Apple News / Safari selected-tab scale.
  /// - `1.0` — no magnification; all tabs render at the same size.
  final double magnification;

  /// Blur amount inside the selected indicator. Defaults to 0.0.
  final double innerBlur;

  /// Set true when the bar sits over an iOS PlatformView (e.g. a map). The bar
  /// background renders via live `BackdropFilter` (the premium shader can't
  /// capture a PlatformView), while the premium indicator refracts the bar's
  /// own icons — so premium animations survive over the PlatformView with no
  /// quality swap. Defaults to false.
  ///
  /// Known limitation: the premium indicator refracts the icon layer via
  /// `toImageSync`, which asserts the captured boundary is clean. While the
  /// indicator animates, that layer repaints every frame, so a mid-animation
  /// capture can fail and the indicator briefly flashes dark. Negligible at
  /// [magnification] ~1.0 (the default) but grows with magnification. Keep
  /// magnification near 1.0 over a PlatformView. (The PlatformView itself
  /// can't be captured, so it can't be refracted directly.)
  final bool platformViewBackdrop;

  /// Rendering quality for the liquid masking effect. Defaults to [MaskingQuality.high].
  final MaskingQuality maskingQuality;

  /// Background key for Skia/web refraction. Optional.
  final GlobalKey? backgroundKey;

  // Note: interactionBehavior and pressScale fields are declared earlier in the Interaction section.

  // ── Tab sizing ───────────────────────────────────────────────────────────────

  /// Width of each tab slot in the tab pill.
  ///
  /// Controls the total width of the tab pill:
  /// `pill width = tabWidth × tab count`, clamped to the maximum
  /// available space.
  ///
  /// **Default: `88.0`** — matches the iOS 26 compact tab slot that
  /// comfortably fits an icon + short label. This gives a 2-tab bar a
  /// 176 px pill and a 3-tab bar a 264 px pill, leaving the rest of the
  /// available width for the search pill to animate into.
  ///
  /// Set to `null` to expand the tab pill across all available space
  /// (the legacy behaviour). Useful when you always have 4–5 tabs and
  /// want them to fill the bar.
  ///
  /// ```dart
  /// // Compact (default) — 2 tabs = 176 px pill
  /// tabWidth: 88.0,
  ///
  /// // Wider slots for longer labels ("Following", "Discover")
  /// tabWidth: 110.0,
  ///
  /// // Legacy expand — fills all space left of the search button
  /// tabWidth: null,
  /// ```
  final double? tabWidth;

  /// Override border radius for the indicator pill. Null = inherits from
  /// [barBorderRadius]. Use a higher value (e.g. 100) for a fully round
  /// indicator on a more subtly curved bar.
  final double? indicatorBorderRadius;

  /// How far the jelly indicator's leading and trailing edges expand
  /// past the tab boundary as the indicator translates between tabs.
  /// Higher values give a more dramatic "puff" stretch; lower values
  /// produce a tighter, more iOS-native feel. Defaults to `14` —
  /// matches the pre-existing visual.
  final EdgeInsetsGeometry indicatorExpansion;

  /// Called when the user taps anywhere on the bar.
  ///
  /// Fires via a translucent [GestureDetector] that wraps the entire bar,
  /// so internal tap handlers (tab selection, search toggle, indicator drag)
  /// all continue to work normally.
  ///
  /// **Primary use-case — tap-to-restore after scroll-to-hide:**
  /// ```dart
  /// GlassSearchableBottomBar(
  ///   onBarTap: () => setState(() => _barVisible = true),
  ///   ...
  /// )
  /// ```
  final VoidCallback? onBarTap;

  @override
  Widget build(BuildContext context) => TabBarSearchableLayout(
        tabs: tabs,
        selectedIndex: selectedIndex,
        onTabSelected: onTabSelected,
        searchConfig: searchConfig,
        controller: controller,
        isSearchActive: isSearchActive,
        extraButton: extraButton,
        spacing: spacing,
        horizontalPadding: horizontalPadding,
        verticalPadding: verticalPadding,
        barHeight: barHeight,
        searchBarHeight: searchBarHeight,
        barBorderRadius: barBorderRadius,
        tabPadding: tabPadding,
        iconLabelSpacing: iconLabelSpacing,
        enableBlend: enableBlend,
        blendAmount: blendAmount,
        settings: settings,
        showIndicator: showIndicator,
        indicatorColor: indicatorColor,
        indicatorSettings: indicatorSettings,
        indicatorPinchStrength: indicatorPinchStrength,
        selectedIconColor: selectedIconColor,
        unselectedIconColor: unselectedIconColor,
        selectedLabelColor: selectedLabelColor,
        unselectedLabelColor: unselectedLabelColor,
        selectedLabelStyle: selectedLabelStyle,
        unselectedLabelStyle: unselectedLabelStyle,
        iconSize: iconSize,
        labelFontSize: labelFontSize,
        textStyle: textStyle,
        glowDuration: glowDuration,
        glowBlurRadius: glowBlurRadius,
        glowSpreadRadius: glowSpreadRadius,
        glowOpacity: glowOpacity,
        interactionBehavior: interactionBehavior,
        pressScale: pressScale,
        interactionGlowColor: interactionGlowColor,
        interactionGlowRadius: interactionGlowRadius,
        quality: quality,
        magnification: magnification,
        innerBlur: innerBlur,
        platformViewBackdrop: platformViewBackdrop,
        maskingQuality: maskingQuality,
        backgroundKey: backgroundKey,
        springDescription: springDescription,
        tabPillAnchor: tabPillAnchor,
        tabWidth: tabWidth,
        indicatorBorderRadius: indicatorBorderRadius,
        indicatorExpansion: indicatorExpansion,
        onBarTap: onBarTap,
        whitenAtBottom: whitenAtBottom,
        whitenBottomThreshold: whitenBottomThreshold,
        whitenAtBottomTarget: whitenAtBottomTarget,
        scrollController: scrollController,
        adaptiveBrightness: adaptiveBrightness,
        onBrightnessChanged: onBrightnessChanged,
        brightnessOverride: brightnessOverride,
      );
}
