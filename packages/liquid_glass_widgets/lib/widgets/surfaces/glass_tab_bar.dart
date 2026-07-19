// ignore_for_file: deprecated_member_use_from_same_package
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../../src/renderer/liquid_glass_renderer.dart';

import '../../src/types/glass_interaction_behavior.dart';
import '../../types/glass_quality.dart';
import '../shared/inherited_liquid_glass.dart';
import 'glass_bottom_bar.dart'
    show
        GlassBottomBar,
        GlassTabBarExtraButton,
        GlassBottomBarTab,
        GlassTabPillAnchor,
        MaskingQuality;
import 'glass_searchable_bottom_bar.dart' show GlassSearchableBottomBar;
import 'shared/glass_search_bar_config.dart';
import 'shared/tab_bar_searchable_controller.dart';
import 'shared/tab_bar_bottom_layout.dart';
import 'shared/tab_bar_searchable_layout.dart';

export 'shared/glass_search_bar_config.dart';

/// The iOS 26 structural navigation bar widget.
///
/// [GlassTabBar] covers three placement contexts via named constructors:
///
/// - **[GlassTabBar.bottom]** — floating glass pill at the bottom of the screen.
///   Mirrors Apple's `UITabBarController`.
/// - **[GlassTabBar.searchable]** — bottom pill that morphs into a search bar.
/// - **[GlassTabBar.inline]** — compact, in-page glass tab bar with a refracting
///   `AdaptiveGlass.grouped` track. Use this when you need a glass-backed content
///   switcher (e.g. Apple Music-style section picker). For a flat native-fidelity
///   filter control, use [GlassSegmentedControl] instead.
///
/// ## Constructors
///
/// | Constructor | iOS equivalent | Use-case |
/// |---|---|---|
/// | [GlassTabBar.bottom] | `UITabBar` | App-level bottom navigation |
/// | [GlassTabBar.searchable] | `UITabBar` + search | Bottom nav + morphing search bar |
/// | [GlassTabBar.inline] | Glass-backed `UISegmentedControl` / inline `UITabBar` | In-page content switcher with glass track |
///
/// ## Usage
///
/// ### Bottom navigation bar
/// ```dart
/// GlassTabBar.bottom(
///   tabs: [
///     GlassTab(icon: Icon(Icons.home),   label: 'Home'),
///     GlassTab(icon: Icon(Icons.search), label: 'Search'),
///     GlassTab(icon: Icon(Icons.person), label: 'Profile'),
///   ],
///   selectedIndex: _selectedIndex,
///   onTabSelected: (i) => setState(() => _selectedIndex = i),
/// )
/// ```
///
/// ### With morphing search bar
/// ```dart
/// GlassTabBar.searchable(
///   tabs: [
///     GlassTab(icon: Icon(Icons.home),   label: 'Home'),
///     GlassTab(icon: Icon(Icons.search), label: 'Search'),
///   ],
///   selectedIndex: _selectedIndex,
///   onTabSelected: (i) => setState(() => _selectedIndex = i),
///   searchBarConfig: GlassSearchBarConfig(hintText: 'Search...'),
///   controller: _controller,
/// )
/// ```
///
/// ### Inline / in-page tab switching
/// ```dart
/// // ✅ Glass-backed track with jelly indicator — Apple Music style
/// GlassTabBar.inline(
///   tabs: const [
///     GlassTab(label: 'Timeline'),
///     GlassTab(label: 'Mentions'),
///   ],
///   selectedIndex: _selectedIndex,
///   onTabSelected: (i) => setState(() => _selectedIndex = i),
/// )
///
/// // ✅ Flat native UISegmentedControl fidelity — filter/mode selection
/// GlassSegmentedControl(
///   segments: const [
///     GlassSegment(label: 'Timeline'),
///     GlassSegment(label: 'Mentions'),
///   ],
///   selectedIndex: _selectedIndex,
///   onSegmentSelected: (i) => setState(() => _selectedIndex = i),
/// )
/// ```
// ---------------------------------------------------------------------------
// Placement discriminant — private, drives constructor dispatch
// ---------------------------------------------------------------------------
enum _GlassTabBarPlacement { bottom, searchable, inline }

/// The iOS 26 structural bottom navigation bar.
///
/// Two named constructors cover the two `UITabBarController` use-cases:
///
/// - **[GlassTabBar.bottom]** — floating pill at the screen bottom with safe
///   area handling, jelly physics, and optional extra action button.
///   Replaces the deprecated [GlassBottomBar].
///
/// - **[GlassTabBar.searchable]** — bottom pill that morphs into a search bar.
///   Replaces the deprecated [GlassSearchableBottomBar].
///
/// For in-page / inline tab switching, use [GlassSegmentedControl] instead.
///
/// ## Migration from v0.17.x
///
/// ```dart
/// // BEFORE
/// GlassBottomBar(tabs: [...], ...)
/// GlassSearchableBottomBar(tabs: [...], searchConfig: ..., ...)
///
/// // AFTER
/// GlassTabBar.bottom(tabs: [...], ...)
/// GlassTabBar.searchable(tabs: [...], searchConfig: ..., ...)
/// ```
///
/// The old widgets still work — they are zero-logic deprecation shims.
class GlassTabBar extends StatefulWidget {
  // ─── Bottom constructor ────────────────────────────────────────────────────

  /// Creates a floating bottom tab bar — the iOS 26 `UITabBarController` equivalent.
  ///
  /// This constructor replaces the deprecated [GlassBottomBar] with identical
  /// parameter names and defaults. Existing [GlassBottomBar] code migrates by
  /// search-replacing `GlassBottomBar(` → `GlassTabBar.bottom(` and
  /// `GlassBottomBarTab(` → `GlassTab(`.
  ///
  /// ## Play-pill / mini-player accessory
  ///
  /// Place persistent overlays (mini-player, Now Playing) above the bar using
  /// [GlassScaffold.bodyOverlays] + [AnimatedPositioned] — not inside this
  /// widget. That is the equivalent of Apple's `tabViewBottomAccessory`.
  const GlassTabBar.bottom({
    required List<GlassTab> tabs,
    required int selectedIndex,
    required ValueChanged<int> onTabSelected,
    Key? key,
    GlassTabBarExtraButton? extraButton,
    double spacing = 8,
    double horizontalPadding = 20,
    double verticalPadding = 20,
    double barHeight = 64,
    double barBorderRadius = _kDefaultBottomBorderRadius,
    EdgeInsetsGeometry tabPadding = const EdgeInsets.symmetric(horizontal: 4),
    double iconLabelSpacing = 4,
    bool enableBlend = true,
    double blendAmount = 10,
    LiquidGlassSettings? settings,
    bool showIndicator = true,
    Color? indicatorColor,
    LiquidGlassSettings? indicatorSettings,
    double indicatorPinchStrength = 0.4,
    Color? selectedIconColor,
    Color? unselectedIconColor,
    Color? selectedLabelColor,
    Color? unselectedLabelColor,
    TextStyle? selectedLabelStyle,
    TextStyle? unselectedLabelStyle,
    double iconSize = 24,
    double labelFontSize = 11,
    TextStyle? textStyle,
    Duration glowDuration = const Duration(milliseconds: 300),
    double glowBlurRadius = 32,
    double glowSpreadRadius = 8,
    double glowOpacity = 0.6,
    GlassQuality? quality,
    double magnification = 1.15,
    double innerBlur = 0.0,
    MaskingQuality maskingQuality = MaskingQuality.high,
    GlobalKey? backgroundKey,
    double? tabWidth,
    double? indicatorBorderRadius,
    EdgeInsetsGeometry indicatorExpansion =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    Color? interactionGlowColor,
    double interactionGlowRadius = 1.5,
    GlassInteractionBehavior interactionBehavior =
        GlassInteractionBehavior.full,
    double pressScale = 1.04,
    bool platformViewBackdrop = false,
    bool adaptiveBrightness = false,
    ValueChanged<Brightness>? onBrightnessChanged,
    ValueListenable<Brightness>? brightnessOverride,
  }) : this._(
          key: key,
          placement: _GlassTabBarPlacement.bottom,
          tabs: tabs,
          selectedIndex: selectedIndex,
          onTabSelected: onTabSelected,
          extraButton: extraButton,
          spacing: spacing,
          horizontalPadding: horizontalPadding,
          verticalPadding: verticalPadding,
          barHeight: barHeight,
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
          quality: quality,
          magnification: magnification,
          innerBlur: innerBlur,
          maskingQuality: maskingQuality,
          backgroundKey: backgroundKey,
          tabWidth: tabWidth,
          indicatorBorderRadius: indicatorBorderRadius,
          indicatorExpansion: indicatorExpansion,
          interactionGlowColor: interactionGlowColor,
          interactionGlowRadius: interactionGlowRadius,
          interactionBehavior: interactionBehavior,
          pressScale: pressScale,
          platformViewBackdrop: platformViewBackdrop,
          adaptiveBrightness: adaptiveBrightness,
          onBrightnessChanged: onBrightnessChanged,
          brightnessOverride: brightnessOverride,
        );

  // ─── Inline constructor ────────────────────────────────────────────────────

  /// Creates a compact, in-page glass tab bar with a refracting glass track.
  ///
  /// Use this when you need a **glass-backed** content switcher embedded inside
  /// a page — e.g. an Apple Music-style section picker or a search results
  /// segment bar that sits on a glass surface.
  ///
  /// The track refracts the background behind it via `AdaptiveGlass.grouped`,
  /// and the indicator uses the same jelly-physics spring as [GlassTabBar.bottom].
  ///
  /// For a flat, native-fidelity filter/mode control (matching the default
  /// `UISegmentedControl` appearance), use [GlassSegmentedControl] instead.
  ///
  /// ## Usage
  ///
  /// ```dart
  /// GlassTabBar.inline(
  ///   tabs: const [
  ///     GlassTab(label: 'For You'),
  ///     GlassTab(label: 'Following'),
  ///     GlassTab(label: 'New'),
  ///   ],
  ///   selectedIndex: _selectedIndex,
  ///   onTabSelected: (i) => setState(() => _selectedIndex = i),
  /// )
  /// ```
  const GlassTabBar.inline({
    required List<GlassTab> tabs,
    required int selectedIndex,
    required ValueChanged<int> onTabSelected,
    Key? key,
    // Compact defaults suited for inline placement
    double horizontalPadding = 0,
    double verticalPadding = 0,
    double barHeight = 40,
    double barBorderRadius = 100,
    double labelFontSize = 13,
    double iconSize = 18,
    EdgeInsetsGeometry tabPadding = const EdgeInsets.symmetric(horizontal: 8),
    EdgeInsetsGeometry indicatorExpansion =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    // No magnification for compact label-centric layout
    double magnification = 1.0,
    double innerBlur = 0.0,
    // Standard shared params
    double spacing = 4,
    double blendAmount = 10,
    bool enableBlend = true,
    bool showIndicator = true,
    Color? indicatorColor,
    LiquidGlassSettings? indicatorSettings,
    double indicatorPinchStrength = 0.4,
    double? indicatorBorderRadius,
    Color? selectedIconColor,
    Color? unselectedIconColor,
    Color? selectedLabelColor,
    Color? unselectedLabelColor,
    TextStyle? selectedLabelStyle,
    TextStyle? unselectedLabelStyle,
    TextStyle? textStyle,
    double? tabWidth,
    LiquidGlassSettings? settings,
    GlassQuality? quality,
    MaskingQuality maskingQuality = MaskingQuality.high,
    GlobalKey? backgroundKey,
    double iconLabelSpacing = 4,
    Duration glowDuration = const Duration(milliseconds: 300),
    double glowBlurRadius = 20,
    double glowSpreadRadius = 4,
    double glowOpacity = 0.5,
    GlassInteractionBehavior interactionBehavior =
        GlassInteractionBehavior.full,
    double pressScale = 1.02,
    Color? interactionGlowColor,
    double interactionGlowRadius = 1.0,
    bool platformViewBackdrop = false,
    bool adaptiveBrightness = false,
    ValueChanged<Brightness>? onBrightnessChanged,
    ValueListenable<Brightness>? brightnessOverride,
    // Indicator snap spring — null keeps the shared default. Exposed so
    // inline hosts can match a reference feel (e.g. Apple Music's snappier
    // settle) without forking the physics.
    SpringDescription? springDescription,
  }) : this._(
          key: key,
          placement: _GlassTabBarPlacement.inline,
          springDescription: springDescription,
          tabs: tabs,
          selectedIndex: selectedIndex,
          onTabSelected: onTabSelected,
          horizontalPadding: horizontalPadding,
          verticalPadding: verticalPadding,
          barHeight: barHeight,
          barBorderRadius: barBorderRadius,
          labelFontSize: labelFontSize,
          iconSize: iconSize,
          tabPadding: tabPadding,
          indicatorExpansion: indicatorExpansion,
          magnification: magnification,
          innerBlur: innerBlur,
          spacing: spacing,
          blendAmount: blendAmount,
          enableBlend: enableBlend,
          showIndicator: showIndicator,
          indicatorColor: indicatorColor,
          indicatorSettings: indicatorSettings,
          indicatorPinchStrength: indicatorPinchStrength,
          indicatorBorderRadius: indicatorBorderRadius ?? barBorderRadius,
          selectedIconColor: selectedIconColor,
          unselectedIconColor: unselectedIconColor,
          selectedLabelColor: selectedLabelColor,
          unselectedLabelColor: unselectedLabelColor,
          selectedLabelStyle: selectedLabelStyle,
          unselectedLabelStyle: unselectedLabelStyle,
          textStyle: textStyle,
          tabWidth: tabWidth,
          settings: settings,
          quality: quality,
          maskingQuality: maskingQuality,
          backgroundKey: backgroundKey,
          iconLabelSpacing: iconLabelSpacing,
          glowDuration: glowDuration,
          glowBlurRadius: glowBlurRadius,
          glowSpreadRadius: glowSpreadRadius,
          glowOpacity: glowOpacity,
          interactionBehavior: interactionBehavior,
          pressScale: pressScale,
          interactionGlowColor: interactionGlowColor,
          interactionGlowRadius: interactionGlowRadius,
          platformViewBackdrop: platformViewBackdrop,
          adaptiveBrightness: adaptiveBrightness,
          onBrightnessChanged: onBrightnessChanged,
          brightnessOverride: brightnessOverride,
        );

  // ─── Searchable constructor ────────────────────────────────────────────────

  /// Creates a bottom bar with a morphing search pill.
  ///
  /// This constructor replaces the deprecated [GlassSearchableBottomBar].
  /// All parameters are identical to that widget. Migrate by replacing
  /// `GlassSearchableBottomBar(` → `GlassTabBar.searchable(`.
  const GlassTabBar.searchable({
    required List<GlassTab> tabs,
    required int selectedIndex,
    required ValueChanged<int> onTabSelected,
    required GlassSearchBarConfig searchConfig,
    Key? key,
    SearchableBottomBarController? controller,
    bool isSearchActive = false,
    GlassTabBarExtraButton? extraButton,
    double spacing = 8,
    double horizontalPadding = 20,
    double verticalPadding = 20,
    double barHeight = 64,
    double searchBarHeight = 50,
    double barBorderRadius = _kDefaultBottomBorderRadius,
    EdgeInsetsGeometry tabPadding = const EdgeInsets.symmetric(horizontal: 4),
    double iconLabelSpacing = 4,
    bool enableBlend = true,
    double blendAmount = 10,
    LiquidGlassSettings? settings,
    bool showIndicator = true,
    Color? indicatorColor,
    LiquidGlassSettings? indicatorSettings,
    double indicatorPinchStrength = 0.4,
    Color? selectedIconColor,
    Color? unselectedIconColor,
    Color? selectedLabelColor,
    Color? unselectedLabelColor,
    TextStyle? selectedLabelStyle,
    TextStyle? unselectedLabelStyle,
    double iconSize = 24,
    double labelFontSize = 11,
    TextStyle? textStyle,
    Duration glowDuration = const Duration(milliseconds: 300),
    double glowBlurRadius = 32,
    double glowSpreadRadius = 8,
    double glowOpacity = 0.6,
    GlassInteractionBehavior interactionBehavior =
        GlassInteractionBehavior.full,
    double pressScale = 1.04,
    Color? interactionGlowColor,
    double interactionGlowRadius = 1.5,
    GlassQuality? quality,
    double magnification = 1.15,
    double innerBlur = 0.0,
    bool platformViewBackdrop = false,
    MaskingQuality maskingQuality = MaskingQuality.high,
    GlobalKey? backgroundKey,
    SpringDescription? springDescription,
    GlassTabPillAnchor tabPillAnchor = GlassTabPillAnchor.start,
    double? tabWidth,
    double? indicatorBorderRadius,
    EdgeInsetsGeometry indicatorExpansion =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    VoidCallback? onBarTap,
    bool whitenAtBottom = true,
    double whitenBottomThreshold = 45.0,
    double whitenAtBottomTarget = 1.0,
    ScrollController? scrollController,
    bool adaptiveBrightness = false,
    ValueChanged<Brightness>? onBrightnessChanged,
    ValueListenable<Brightness>? brightnessOverride,
  }) : this._(
          key: key,
          placement: _GlassTabBarPlacement.searchable,
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

  // ─── Private unified constructor (delegate target) ─────────────────────────

  const GlassTabBar._(
      {required this.tabs,
      required this.selectedIndex,
      required this.onTabSelected,
      required _GlassTabBarPlacement placement,
      super.key,
      // Shared styling
      this.indicatorColor,
      this.selectedIconColor,
      this.unselectedIconColor,
      this.selectedLabelColor,
      this.unselectedLabelColor,
      this.selectedLabelStyle,
      this.unselectedLabelStyle,
      this.iconSize = 24.0,
      this.settings,
      this.quality,
      this.indicatorSettings,
      this.indicatorPinchStrength = 0.4,
      this.indicatorExpansion =
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      this.backgroundKey,
      this.maskingQuality = MaskingQuality.high,
      // Bottom / searchable shared
      this.spacing = 8,
      this.horizontalPadding = 20,
      this.verticalPadding = 20,
      this.barHeight = 64,
      this.barBorderRadius = _kDefaultBottomBorderRadius,
      this.tabPadding = const EdgeInsets.symmetric(horizontal: 4),
      this.iconLabelSpacing = 4,
      this.enableBlend = true,
      this.blendAmount = 10,
      this.showIndicator = true,
      this.magnification = 1.15,
      this.innerBlur = 0.0,
      this.glowDuration = const Duration(milliseconds: 300),
      this.glowBlurRadius = 32,
      this.glowSpreadRadius = 8,
      this.glowOpacity = 0.6,
      this.labelFontSize = 11,
      this.textStyle,
      this.tabWidth,
      this.indicatorBorderRadius,
      this.extraButton,
      this.interactionBehavior = GlassInteractionBehavior.full,
      this.pressScale = 1.04,
      this.interactionGlowColor,
      this.interactionGlowRadius = 1.5,
      this.platformViewBackdrop = false,
      this.adaptiveBrightness = false,
      this.onBrightnessChanged,
      this.brightnessOverride,
      // Searchable-only
      this.searchConfig,
      this.controller,
      this.isSearchActive = false,
      this.searchBarHeight = 50,
      this.springDescription,
      this.tabPillAnchor = GlassTabPillAnchor.start,
      this.onBarTap,
      this.whitenAtBottom = true,
      this.whitenBottomThreshold = 45.0,
      this.whitenAtBottomTarget = 1.0,
      this.scrollController})
      : _placement = placement,
        assert(tabs.length >= 1, 'GlassTabBar requires at least 1 tab'),
        assert(
          selectedIndex >= 0 && selectedIndex < tabs.length,
          'selectedIndex must be within bounds of tabs list',
        );

  /// List of tabs to display.
  final List<GlassTab> tabs;

  /// Index of the currently selected tab.
  final int selectedIndex;

  /// Called when a tab is selected.
  final ValueChanged<int> onTabSelected;

  /// Color of the pill indicator.
  final Color? indicatorColor;

  /// Icon color for selected tab.
  final Color? selectedIconColor;

  /// Icon color for unselected tabs.
  final Color? unselectedIconColor;

  /// Label color for selected tab.
  final Color? selectedLabelColor;

  /// Label color for unselected tabs.
  final Color? unselectedLabelColor;

  /// Per-state label text style, merged over the base label style — overrides
  /// font / weight / letter-spacing while keeping the resolved label color
  /// unless the style sets its own. Null leaves existing behavior unchanged.
  final TextStyle? selectedLabelStyle;

  /// See [selectedLabelStyle].
  final TextStyle? unselectedLabelStyle;

  /// Size of the icons.
  final double iconSize;

  /// Glass effect settings.
  final LiquidGlassSettings? settings;

  /// Rendering quality for the glass effect.
  ///
  /// If null, inherits from parent [InheritedLiquidGlass] or defaults to
  /// [GlassQuality.standard].
  final GlassQuality? quality;

  /// Controls indicator clipping quality.
  ///
  /// - [MaskingQuality.high] (default): Full jelly-bloom physics — the
  ///   indicator expands 8 px beyond its pill bounds for the iOS 26 spring
  ///   effect. Uses a dual-layer [GlassBottomBarClipper] path.
  /// - [MaskingQuality.off]: Simple clipping with no jelly expansion.
  ///   Cheaper on GPU; useful for low-end devices or accessibility modes.
  ///
  /// Mirrors the same parameter on [GlassBottomBar] for a consistent API.
  final MaskingQuality maskingQuality;

  /// Glass settings for the sliding indicator.
  final LiquidGlassSettings? indicatorSettings;

  /// Maximum concave lens pinch strength for the sliding indicator pill.
  ///
  /// - `1.0` (default) — full Apple-calibrated pinch
  /// - `0.0` — pinch fully disabled
  /// Maximum concave lens pinch strength. Forwarded to [AnimatedGlassIndicator].
  ///
  /// Defaults to `0.4` — the iOS 26-calibrated gentle concave lens warp.
  /// Set to `0.0` to disable the effect entirely, or `1.0` to restore the
  /// original full-strength warp.
  final double indicatorPinchStrength;

  /// Expansion padding applied to the active indicator pill during interaction.
  ///
  /// The pill grows by this amount beyond its cell boundary as the user drags,
  /// creating the iOS 26 "jelly" overshoot. Defaults to
  /// `EdgeInsets.symmetric(horizontal: 12, vertical: 8)` which matches
  /// [GlassBottomBar] for a consistent look across all indicator widgets.
  final EdgeInsetsGeometry indicatorExpansion;

  /// Optional background key for Skia/Web refraction.
  final GlobalKey? backgroundKey;

  // ---------------------------------------------------------------------------
  // Internal placement discriminant
  // ---------------------------------------------------------------------------
  final _GlassTabBarPlacement _placement;

  // ---------------------------------------------------------------------------
  // Default border radius for bottom/searchable constructors
  // ---------------------------------------------------------------------------
  static const double _kDefaultBottomBorderRadius = 32.0;

  // ---------------------------------------------------------------------------
  // Bottom / searchable fields (all have defaults — safe for inline too)
  // ---------------------------------------------------------------------------

  /// Spacing between adjacent pills (bottom/searchable only). Defaults to 8.
  final double spacing;

  /// Horizontal padding around the full bar content. Defaults to 20.
  final double horizontalPadding;

  /// Vertical padding (top + bottom) around the bar content. Defaults to 20.
  final double verticalPadding;

  /// Height of the pill (bottom/searchable). Defaults to 64.
  final double barHeight;

  /// Corner radius of the pill (bottom/searchable). Defaults to 32.
  final double barBorderRadius;

  /// Internal padding within the tab pill. Defaults to 4 px horizontal.
  final EdgeInsetsGeometry tabPadding;

  /// Vertical spacing between icon and label. Defaults to 4.
  final double iconLabelSpacing;

  /// Enables organic liquid blending between adjacent pills. Defaults to true.
  final bool enableBlend;

  /// Blend amount for the shared glass layer. Defaults to 10.
  final double blendAmount;

  /// Whether to show the draggable indicator. Defaults to true.
  final bool showIndicator;

  /// Selected-icon magnification inside the indicator (bottom/searchable).
  final double magnification;

  /// Blur applied to content inside the indicator (bottom/searchable).
  final double innerBlur;

  /// Duration of the per-tab glow animation. Defaults to 300 ms.
  final Duration glowDuration;

  /// Blur radius of the tab glow effect. Defaults to 32.
  final double glowBlurRadius;

  /// Spread radius of the tab glow effect. Defaults to 8.
  final double glowSpreadRadius;

  /// Opacity of the tab glow effect. Defaults to 0.6.
  final double glowOpacity;

  /// Font size for tab labels (bottom/searchable). Defaults to 11.
  final double labelFontSize;

  /// Text style for tab labels (bottom/searchable). Overrides [labelFontSize].
  final TextStyle? textStyle;

  /// Fixed width per tab slot. Null = fill all available space.
  final double? tabWidth;

  /// Override border radius for the indicator. Null = inherits from barBorderRadius.
  final double? indicatorBorderRadius;

  /// Optional extra action button (bottom/searchable only).
  final GlassTabBarExtraButton? extraButton;

  /// Which physical interaction effects are active. Defaults to [GlassInteractionBehavior.full].
  final GlassInteractionBehavior interactionBehavior;

  /// Peak scale applied at maximum press depth. Defaults to 1.04.
  final double pressScale;

  /// Directional glow color on press. Null = theme default.
  final Color? interactionGlowColor;

  /// Spread radius of the directional glow. Defaults to 1.5.
  final double interactionGlowRadius;

  /// Forces BackdropFilter rendering over iOS PlatformViews. Defaults to false.
  final bool platformViewBackdrop;

  /// Adapts brightness to content scrolling underneath. Defaults to false.
  final bool adaptiveBrightness;

  /// Called when the content-aware brightness verdict flips.
  final ValueChanged<Brightness>? onBrightnessChanged;

  /// External brightness source that bypasses the content sampler.
  final ValueListenable<Brightness>? brightnessOverride;

  // ---------------------------------------------------------------------------
  // Searchable-only fields
  // ---------------------------------------------------------------------------

  /// Configuration for the morphing search bar. Required for [GlassTabBar.searchable].
  final GlassSearchBarConfig? searchConfig;

  /// Optional external controller for the search state machine.
  final SearchableBottomBarController? controller;

  /// Whether the search bar is currently expanded (searchable only).
  final bool isSearchActive;

  /// Height of the pills while search is active. Defaults to 50.
  final double searchBarHeight;

  /// Custom spring for the pill morph animation. Null = iOS 26 default.
  final SpringDescription? springDescription;

  /// How the tab pill is anchored during the morph animation.
  final GlassTabPillAnchor tabPillAnchor;

  /// Optional tap callback for the whole bar (searchable only).
  final VoidCallback? onBarTap;

  /// Whiten glass at page bottom in light mode. Defaults to true.
  final bool whitenAtBottom;

  /// Scroll offset at which whitening begins. Defaults to 45.0.
  final double whitenBottomThreshold;

  /// Maximum whitening amount. Defaults to 1.0.
  final double whitenAtBottomTarget;

  /// Scroll controller wired for whitening + minimize behaviour.
  final ScrollController? scrollController;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> {
  @override
  void didUpdateWidget(GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    // Dispatch to the correct rendering engine based on placement.
    switch (widget._placement) {
      case _GlassTabBarPlacement.bottom:
        return _buildBottom(context);
      case _GlassTabBarPlacement.searchable:
        return _buildSearchable(context);
      case _GlassTabBarPlacement.inline:
        return _buildInline(context);
    }
  }

  /// Dispatches to [TabBarBottomLayout] — the iOS 26-style bottom placement engine.
  Widget _buildBottom(BuildContext context) {
    final tabs = widget.tabs
        .map((t) => GlassBottomBarTab(
              icon: t.icon ?? const SizedBox.shrink(),
              label: t.label,
              activeIcon: t.activeIcon,
              glowColor: t.glowColor,
              thickness: t.thickness,
            ))
        .toList();
    return TabBarBottomLayout(
      tabs: tabs,
      selectedIndex: widget.selectedIndex,
      onTabSelected: widget.onTabSelected,
      extraButton: widget.extraButton,
      spacing: widget.spacing,
      horizontalPadding: widget.horizontalPadding,
      verticalPadding: widget.verticalPadding,
      barHeight: widget.barHeight,
      barBorderRadius: widget.barBorderRadius,
      tabPadding: widget.tabPadding,
      iconLabelSpacing: widget.iconLabelSpacing,
      enableBlend: widget.enableBlend,
      blendAmount: widget.blendAmount,
      settings: widget.settings,
      showIndicator: widget.showIndicator,
      indicatorColor: widget.indicatorColor,
      indicatorSettings: widget.indicatorSettings,
      indicatorPinchStrength: widget.indicatorPinchStrength,
      selectedIconColor: widget.selectedIconColor,
      unselectedIconColor: widget.unselectedIconColor,
      selectedLabelColor: widget.selectedLabelColor,
      unselectedLabelColor: widget.unselectedLabelColor,
      selectedLabelStyle: widget.selectedLabelStyle,
      unselectedLabelStyle: widget.unselectedLabelStyle,
      iconSize: widget.iconSize,
      labelFontSize: widget.labelFontSize,
      textStyle: widget.textStyle,
      glowDuration: widget.glowDuration,
      glowBlurRadius: widget.glowBlurRadius,
      glowSpreadRadius: widget.glowSpreadRadius,
      glowOpacity: widget.glowOpacity,
      quality: widget.quality,
      magnification: widget.magnification,
      innerBlur: widget.innerBlur,
      maskingQuality: widget.maskingQuality,
      backgroundKey: widget.backgroundKey,
      tabWidth: widget.tabWidth,
      indicatorBorderRadius: widget.indicatorBorderRadius,
      indicatorExpansion: widget.indicatorExpansion,
      interactionGlowColor: widget.interactionGlowColor,
      interactionGlowRadius: widget.interactionGlowRadius,
      interactionBehavior: widget.interactionBehavior,
      pressScale: widget.pressScale,
      platformViewBackdrop: widget.platformViewBackdrop,
      adaptiveBrightness: widget.adaptiveBrightness,
      onBrightnessChanged: widget.onBrightnessChanged,
      brightnessOverride: widget.brightnessOverride,
      springDescription: widget.springDescription,
    );
  }

  /// Dispatches to [TabBarBottomLayout] with inline-appropriate defaults —
  /// compact height, no floating margins, no icon magnification.
  ///
  /// The track glass comes from [AdaptiveGlass.grouped] inside [TabBarBottomLayout]
  /// exactly as in the bottom placement — no new rendering path needed.
  Widget _buildInline(BuildContext context) {
    final tabs = widget.tabs
        .map((t) => GlassBottomBarTab(
              icon: t.icon ?? const SizedBox.shrink(),
              label: t.label,
              activeIcon: t.activeIcon,
              glowColor: t.glowColor,
              thickness: t.thickness,
            ))
        .toList();
    return TabBarBottomLayout(
      tabs: tabs,
      selectedIndex: widget.selectedIndex,
      onTabSelected: widget.onTabSelected,
      spacing: widget.spacing,
      horizontalPadding: widget.horizontalPadding,
      verticalPadding: widget.verticalPadding,
      barHeight: widget.barHeight,
      barBorderRadius: widget.barBorderRadius,
      tabPadding: widget.tabPadding,
      iconLabelSpacing: widget.iconLabelSpacing,
      enableBlend: widget.enableBlend,
      blendAmount: widget.blendAmount,
      settings: widget.settings,
      showIndicator: widget.showIndicator,
      indicatorColor: widget.indicatorColor,
      indicatorSettings: widget.indicatorSettings,
      indicatorPinchStrength: widget.indicatorPinchStrength,
      selectedIconColor: widget.selectedIconColor,
      unselectedIconColor: widget.unselectedIconColor,
      selectedLabelColor: widget.selectedLabelColor,
      unselectedLabelColor: widget.unselectedLabelColor,
      selectedLabelStyle: widget.selectedLabelStyle,
      unselectedLabelStyle: widget.unselectedLabelStyle,
      iconSize: widget.iconSize,
      labelFontSize: widget.labelFontSize,
      textStyle: widget.textStyle,
      glowDuration: widget.glowDuration,
      glowBlurRadius: widget.glowBlurRadius,
      glowSpreadRadius: widget.glowSpreadRadius,
      glowOpacity: widget.glowOpacity,
      quality: widget.quality,
      magnification: widget.magnification,
      innerBlur: widget.innerBlur,
      maskingQuality: widget.maskingQuality,
      backgroundKey: widget.backgroundKey,
      tabWidth: widget.tabWidth,
      indicatorBorderRadius: widget.indicatorBorderRadius,
      indicatorExpansion: widget.indicatorExpansion,
      interactionGlowColor: widget.interactionGlowColor,
      interactionGlowRadius: widget.interactionGlowRadius,
      interactionBehavior: widget.interactionBehavior,
      pressScale: widget.pressScale,
      platformViewBackdrop: widget.platformViewBackdrop,
      adaptiveBrightness: widget.adaptiveBrightness,
      onBrightnessChanged: widget.onBrightnessChanged,
      brightnessOverride: widget.brightnessOverride,
      springDescription: widget.springDescription,
      // No extra button in inline placement
    );
  }

  /// Dispatches to [TabBarSearchableLayout] — the iOS 26-style searchable placement engine.
  Widget _buildSearchable(BuildContext context) {
    final tabs = widget.tabs
        .map((t) => GlassBottomBarTab(
              icon: t.icon ?? const SizedBox.shrink(),
              label: t.label,
              activeIcon: t.activeIcon,
              glowColor: t.glowColor,
              thickness: t.thickness,
            ))
        .toList();
    return TabBarSearchableLayout(
      tabs: tabs,
      selectedIndex: widget.selectedIndex,
      onTabSelected: widget.onTabSelected,
      searchConfig: widget.searchConfig!,
      controller: widget.controller,
      isSearchActive: widget.isSearchActive,
      extraButton: widget.extraButton,
      spacing: widget.spacing,
      horizontalPadding: widget.horizontalPadding,
      verticalPadding: widget.verticalPadding,
      barHeight: widget.barHeight,
      searchBarHeight: widget.searchBarHeight,
      barBorderRadius: widget.barBorderRadius,
      tabPadding: widget.tabPadding,
      iconLabelSpacing: widget.iconLabelSpacing,
      enableBlend: widget.enableBlend,
      blendAmount: widget.blendAmount,
      settings: widget.settings,
      showIndicator: widget.showIndicator,
      indicatorColor: widget.indicatorColor,
      indicatorSettings: widget.indicatorSettings,
      indicatorPinchStrength: widget.indicatorPinchStrength,
      selectedIconColor: widget.selectedIconColor,
      unselectedIconColor: widget.unselectedIconColor,
      selectedLabelColor: widget.selectedLabelColor,
      unselectedLabelColor: widget.unselectedLabelColor,
      selectedLabelStyle: widget.selectedLabelStyle,
      unselectedLabelStyle: widget.unselectedLabelStyle,
      iconSize: widget.iconSize,
      labelFontSize: widget.labelFontSize,
      textStyle: widget.textStyle,
      glowDuration: widget.glowDuration,
      glowBlurRadius: widget.glowBlurRadius,
      glowSpreadRadius: widget.glowSpreadRadius,
      glowOpacity: widget.glowOpacity,
      interactionBehavior: widget.interactionBehavior,
      pressScale: widget.pressScale,
      interactionGlowColor: widget.interactionGlowColor,
      interactionGlowRadius: widget.interactionGlowRadius,
      quality: widget.quality,
      magnification: widget.magnification,
      innerBlur: widget.innerBlur,
      platformViewBackdrop: widget.platformViewBackdrop,
      maskingQuality: widget.maskingQuality,
      backgroundKey: widget.backgroundKey,
      springDescription: widget.springDescription,
      tabPillAnchor: widget.tabPillAnchor,
      tabWidth: widget.tabWidth,
      indicatorBorderRadius: widget.indicatorBorderRadius,
      indicatorExpansion: widget.indicatorExpansion,
      onBarTap: widget.onBarTap,
      whitenAtBottom: widget.whitenAtBottom,
      whitenBottomThreshold: widget.whitenBottomThreshold,
      whitenAtBottomTarget: widget.whitenAtBottomTarget,
      scrollController: widget.scrollController,
      adaptiveBrightness: widget.adaptiveBrightness,
      onBrightnessChanged: widget.onBrightnessChanged,
      brightnessOverride: widget.brightnessOverride,
    );
  }
}

// =============================================================================
// GlassSegment — configuration for a single segment in GlassSegmentedControl
// =============================================================================

/// Configuration for a single segment in [GlassSegmentedControl].
///
/// [GlassSegment] is the item type for [GlassSegmentedControl] — the iOS 26
/// `UISegmentedControl` equivalent. It intentionally carries **only** fields
/// that make sense for a segmented control item:
///
/// - [label] — the text label
/// - [icon] — the leading icon (before the label)
/// - [tooltip] — tooltip shown on long-press
/// - [semanticLabel] — overrides the accessibility announcement
/// - [enabled] — whether this segment can be selected
///
/// ## Why not [GlassTab]?
///
/// [GlassTab] is the navigation-tab type for [GlassTabBar.bottom] and
/// [GlassTabBar.searchable]. It carries fields like [GlassTab.glowColor],
/// [GlassTab.activeIcon], and [GlassTab.thickness] that are navigation-specific
/// and have no effect in a segmented control. [GlassSegment] is the correct,
/// minimal API for [GlassSegmentedControl].
///
/// ## Usage
///
/// ```dart
/// GlassSegmentedControl(
///   segments: [
///     GlassSegment(label: 'All'),
///     GlassSegment(label: 'Photos', icon: Icon(CupertinoIcons.photo)),
///     GlassSegment(label: 'Videos', icon: Icon(CupertinoIcons.video_camera)),
///   ],
///   selectedIndex: _index,
///   onSegmentSelected: (i) => setState(() => _index = i),
/// )
/// ```
///
/// ## Icon-only segments
///
/// ```dart
/// GlassSegment(icon: Icon(CupertinoIcons.list_bullet))
/// GlassSegment(icon: Icon(CupertinoIcons.square_grid_2x2))
/// ```
///
/// ## Disabled segment
///
/// ```dart
/// GlassSegment(label: 'Pro Only', enabled: false)
/// ```
class GlassSegment {
  /// Creates a segment configuration.
  ///
  /// At least one of [icon] or [label] must be provided.
  const GlassSegment({
    this.icon,
    this.label,
    this.tooltip,
    this.semanticLabel,
    this.enabled = true,
  }) : assert(
          icon != null || label != null,
          'GlassSegment must have either an icon or a label.',
        );

  /// Icon widget to display before the label (or alone, if [label] is null).
  ///
  /// Standard [Icon] widgets automatically pick up the correct color and size
  /// from the parent [IconTheme]. Typically a [CupertinoIcons] icon.
  final Widget? icon;

  /// Text label for this segment.
  ///
  /// If null, [icon] is used alone. If both are provided, the icon is shown
  /// above the label (same layout as iOS `UISegmentedControl` with images).
  final String? label;

  /// Tooltip shown on long-press (optional).
  ///
  /// Useful for icon-only segments where the meaning may not be obvious.
  final String? tooltip;

  /// Overrides the default accessibility announcement.
  ///
  /// If null, falls back to [label] (or an empty string for icon-only segments).
  final String? semanticLabel;

  /// Whether this segment can be selected.
  ///
  /// When `false`, the segment renders at reduced opacity and ignores taps.
  /// Defaults to `true`.
  final bool enabled;
}

// =============================================================================
// GlassTab — unified tab configuration type for GlassTabBar
// =============================================================================

/// Configuration for a tab in [GlassTabBar] (all constructors).
///
/// [GlassTab] is the item type for [GlassTabBar.bottom] and
/// [GlassTabBar.searchable] — the iOS 26 `UITab` / `UITabBarItem` equivalent.
///
/// For [GlassSegmentedControl], use [GlassSegment] instead. [GlassSegment] is
/// a focused type that only carries fields relevant to a segmented control.
///
/// ## Key fields
///
/// - [icon] — shown in unselected state (and selected state if [activeIcon] is null)
/// - [activeIcon] — shown in selected state (optional)
/// - [label] — text label
/// - [glowColor] — per-tab glow colour for the selected indicator
/// - [thickness] — icon shadow halo intensity
///
/// ## Usage
///
/// ```dart
/// GlassTabBar.bottom(
///   tabs: [
///     GlassTab(
///       icon: Icon(CupertinoIcons.home),
///       activeIcon: Icon(CupertinoIcons.house_fill),
///       label: 'Home',
///       glowColor: Colors.blue,
///     ),
///     GlassTab(
///       icon: Icon(CupertinoIcons.search),
///       label: 'Search',
///     ),
///   ],
///   ...
/// )
/// ```
///
/// ## Migration from [GlassBottomBarTab]
///
/// ```dart
/// // BEFORE
/// GlassBottomBarTab(icon: Icon(Icons.home), activeIcon: Icon(Icons.home_fill), label: 'Home', glowColor: Colors.blue)
/// // AFTER
/// GlassTab(icon: Icon(Icons.home), activeIcon: Icon(Icons.home_fill), label: 'Home', glowColor: Colors.blue)
/// ```
class GlassTab {
  /// Creates a tab configuration.
  ///
  /// At least one of [icon] or [label] must be provided.
  const GlassTab({
    this.icon,
    this.activeIcon,
    this.label,
    this.semanticLabel,
    this.glowColor,
    this.thickness,
  }) : assert(
          icon != null || label != null,
          'GlassTab must have either an icon or label',
        );

  /// Icon widget displayed when the tab is **not** selected.
  ///
  /// Also used when selected if [activeIcon] is not provided.
  /// Standard [Icon] widgets automatically pick up the correct color and size
  /// from the parent [IconTheme].
  final Widget? icon;

  /// Icon widget displayed when the tab **is** selected.
  ///
  /// If null, [icon] is used for both selected and unselected states.
  /// Standard [Icon] widgets automatically pick up the correct color and size
  /// from the parent [IconTheme].
  ///
  /// Only used by [GlassTabBar.bottom] and [GlassTabBar.searchable].
  final Widget? activeIcon;

  /// Label text to display in the tab.
  final String? label;

  /// Semantic label for accessibility.
  final String? semanticLabel;

  /// Color of the animated glow effect when this tab is selected.
  ///
  /// If null, no glow effect is shown for this tab.
  /// Only used by [GlassTabBar.bottom] and [GlassTabBar.searchable].
  final Color? glowColor;

  /// Thickness of the icon shadow halo effect.
  ///
  /// When provided, creates a shadow halo around unselected icons for emphasis.
  /// Typical values are between 0.5 and 2.0.
  /// Only used by [GlassTabBar.bottom] and [GlassTabBar.searchable].
  final double? thickness;
}

// =============================================================================
// DividerSettings — configuration for inter-tab dividers
// =============================================================================

/// Configuration for optional vertical dividers between tabs in [GlassTabBar].
///
/// Dividers are rendered as thin vertical lines between tab items and can
/// automatically hide themselves adjacent to the active tab.
class DividerSettings {
  /// Top indent of the divider line.
  final double indent;

  /// Bottom indent of the divider line.
  final double endIndent;

  /// Width (thickness) of the divider line.
  final double thickness;

  /// Optional custom decoration. Defaults to a white 20% opacity line.
  final BoxDecoration? decoration;

  /// Duration of the show/hide animation. Defaults to 200ms.
  final Duration? duration;

  /// Curve of the show/hide animation. Defaults to [Curves.easeInOut].
  final Curve? curve;

  /// When true, dividers adjacent to the selected tab are hidden automatically.
  final bool isHideAutomatically;

  const DividerSettings({
    this.indent = 0,
    this.endIndent = 0,
    this.thickness = 1,
    this.decoration,
    this.duration,
    this.curve,
    this.isHideAutomatically = true,
  });

  @override
  bool operator ==(Object other) {
    return other is DividerSettings &&
        indent == other.indent &&
        endIndent == other.endIndent &&
        thickness == other.thickness &&
        decoration == other.decoration &&
        duration == other.duration &&
        curve == other.curve &&
        isHideAutomatically == other.isHideAutomatically;
  }

  @override
  int get hashCode => Object.hashAll([
        indent,
        endIndent,
        thickness,
        decoration,
        duration,
        curve,
        isHideAutomatically,
      ]);

  /// Returns a copy of this [DividerSettings] with the given fields replaced.
  DividerSettings copyWith({
    double? indent,
    double? endIndent,
    double? thickness,
    BoxDecoration? decoration,
    Duration? duration,
    Curve? curve,
    bool? isHideAutomatically,
  }) {
    return DividerSettings(
      indent: indent ?? this.indent,
      endIndent: endIndent ?? this.endIndent,
      thickness: thickness ?? this.thickness,
      decoration: decoration ?? this.decoration,
      duration: duration ?? this.duration,
      curve: curve ?? this.curve,
      isHideAutomatically: isHideAutomatically ?? this.isHideAutomatically,
    );
  }
}
