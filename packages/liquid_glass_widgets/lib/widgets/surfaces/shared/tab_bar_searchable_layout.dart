// ignore_for_file: deprecated_member_use
// Internal layout engine for [GlassTabBar] searchable placement.
//
// Extracted from the old _GlassSearchableBottomBarState so that [GlassTabBar]
// is the single owner of all rendering logic. The deprecated
// [GlassSearchableBottomBar] shim simply calls [GlassTabBar.searchable()]
// which dispatches here.
//
// Do NOT import this file directly — use [GlassTabBar.searchable()] instead.

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import '../../../src/renderer/liquid_glass_renderer.dart';
import '../../../src/types/glass_interaction_behavior.dart';
import '../../../types/glass_quality.dart';
import '../../shared/adaptive_liquid_glass_layer.dart';
import '../../shared/glass_content_aware_scope.dart';
import '../../../theme/glass_theme_data.dart';
import '../../../theme/glass_theme.dart';
import '../../../theme/glass_theme_helpers.dart';
import '../glass_bottom_bar.dart'
    show
        GlassExtraButtonPosition,
        GlassTabBarExtraButton,
        GlassBottomBarTab,
        GlassTabPillAnchor,
        MaskingQuality;
import 'tab_bar_bottom_internal.dart'
    show
        BottomBarExtraBtn,
        BottomBarTabItem,
        kBottomBarGlassDefaults,
        resolveBarLabelColor;
import 'glass_search_bar_config.dart';
import 'tab_bar_searchable_controller.dart';
import 'tab_bar_searchable_internal.dart'
    show DismissPill, SearchPill, SearchableTabIndicator;

/// Internal [StatefulWidget] that owns the searchable-placement rendering engine.
///
/// Created by [GlassTabBar._buildSearchable()] when
/// [_GlassTabBarPlacement.searchable] is active. Not part of the public API.
class TabBarSearchableLayout extends StatefulWidget {
  const TabBarSearchableLayout({
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
    this.interactionBehavior = GlassInteractionBehavior.full,
    this.pressScale = 1.04,
    this.tabWidth,
    this.indicatorBorderRadius,
    this.indicatorExpansion =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.onBarTap,
    this.whitenAtBottom = true,
    this.whitenBottomThreshold = 45.0,
    this.whitenAtBottomTarget = 1.0,
    this.scrollController,
    this.adaptiveBrightness = false,
    this.onBrightnessChanged,
    this.brightnessOverride,
  });

  static const double _kDefaultBorderRadius = 32.0;

  /// iOS 26-style spring for the pill morph animations.
  static const _kSpring =
      SpringDescription(mass: 1.0, stiffness: 350.0, damping: 30.0);

  final List<GlassBottomBarTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final GlassSearchBarConfig searchConfig;
  final SearchableBottomBarController? controller;
  final bool isSearchActive;
  final GlassTabBarExtraButton? extraButton;
  final double spacing;
  final double horizontalPadding;
  final double verticalPadding;
  final double barHeight;
  final double searchBarHeight;
  final double barBorderRadius;
  final EdgeInsetsGeometry tabPadding;
  final double iconLabelSpacing;
  final bool enableBlend;
  final double blendAmount;
  final LiquidGlassSettings? settings;
  final bool showIndicator;
  final Color? indicatorColor;
  final LiquidGlassSettings? indicatorSettings;
  final double indicatorPinchStrength;
  final Color? selectedIconColor;
  final Color? unselectedIconColor;
  final Color? selectedLabelColor;
  final Color? unselectedLabelColor;
  final TextStyle? selectedLabelStyle;
  final TextStyle? unselectedLabelStyle;
  final double iconSize;
  final double labelFontSize;
  final TextStyle? textStyle;
  final Duration glowDuration;
  final double glowBlurRadius;
  final double glowSpreadRadius;
  final double glowOpacity;
  final Color? interactionGlowColor;
  final double interactionGlowRadius;
  final GlassQuality? quality;
  final double magnification;
  final double innerBlur;
  final bool platformViewBackdrop;
  final MaskingQuality maskingQuality;
  final GlobalKey? backgroundKey;
  final SpringDescription? springDescription;
  final GlassTabPillAnchor tabPillAnchor;
  final GlassInteractionBehavior interactionBehavior;
  final double pressScale;
  final double? tabWidth;
  final double? indicatorBorderRadius;
  final EdgeInsetsGeometry indicatorExpansion;
  final VoidCallback? onBarTap;
  final bool whitenAtBottom;
  final double whitenBottomThreshold;
  final double whitenAtBottomTarget;
  final ScrollController? scrollController;
  final bool adaptiveBrightness;
  final ValueChanged<Brightness>? onBrightnessChanged;
  final ValueListenable<Brightness>? brightnessOverride;

  @override
  State<TabBarSearchableLayout> createState() => _TabBarSearchableLayoutState();
}

class _TabBarSearchableLayoutState extends State<TabBarSearchableLayout>
    with TickerProviderStateMixin {
  static const _defaultGlassSettings = kBottomBarGlassDefaults;

  late SearchableBottomBarController _controller;
  bool _ownsController = false;

  // Stable identity for the tab indicator. Without it the indicator's State is
  // torn down + recreated on every rebuild — which orphans a live press-hold
  // gesture mid-flight and freezes the bar (reproduced at standard/minimal over
  // an iOS PlatformView; the premium render path happens to avoid the churn). A
  // GlobalKey preserves the State across rebuilds AND across the
  // AdaptiveLiquidGlassLayer wrapper's quality-path reparenting.
  final GlobalKey _indicatorKey = GlobalKey();

  void _onControllerChanged() => setState(() {});

  // D1: whitenBoostCtrl still uses setState — it fires at most once per scroll-to-bottom
  // (200 ms easeOut, not a 120 Hz spring). Full rebuild cost is acceptable here.
  // The three spring controllers (_tabWCtrl, _searchLeftCtrl, _searchWCtrl) drive
  // ListenableBuilder widgets directly — no setState on spring ticks.
  void _onWhitenTick() => setState(() {});

  late AnimationController _tabWCtrl;
  late AnimationController _searchLeftCtrl;
  late AnimationController _searchWCtrl;
  late AnimationController _whitenBoostCtrl;
  double _whitenTarget = 0.0;

  // D1: hoisted — avoids allocating a new _MergedListenable on every LayoutBuilder call.
  late Listenable _searchPillListenable;

  @override
  void initState() {
    super.initState();
    assert(
      widget.searchConfig.collapsedTabWidth == null ||
          widget.searchConfig.collapsedTabWidth! > 0,
      'GlassSearchBarConfig.collapsedTabWidth must be positive',
    );
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = SearchableBottomBarController();
      _ownsController = true;
    }
    _controller.addListener(_onControllerChanged);

    // D1: no addListener — these controllers drive ListenableBuilder widgets directly.
    // Spring ticks rebuild only the single Positioned child they animate, not the
    // full State.build(). See the Stack children in _buildBar.
    _tabWCtrl = AnimationController(
      vsync: this,
      lowerBound: double.negativeInfinity,
      upperBound: double.infinity,
    );
    _searchLeftCtrl = AnimationController(
      vsync: this,
      lowerBound: double.negativeInfinity,
      upperBound: double.infinity,
    );
    _searchWCtrl = AnimationController(
      vsync: this,
      lowerBound: double.negativeInfinity,
      upperBound: double.infinity,
    );
    _whitenBoostCtrl = AnimationController(vsync: this)
      ..addListener(_onWhitenTick);
    // D1: create once — the controllers never change after initState.
    _searchPillListenable = Listenable.merge([_searchLeftCtrl, _searchWCtrl]);
    widget.scrollController?.addListener(_onScrollMaybeWhiten);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScrollMaybeWhiten();
    });
  }

  @override
  void didUpdateWidget(covariant TabBarSearchableLayout old) {
    super.didUpdateWidget(old);
    if (widget.controller != old.controller) {
      _controller.removeListener(_onControllerChanged);
      if (_ownsController) _controller.dispose();
      if (widget.controller != null) {
        _controller = widget.controller!;
        _ownsController = false;
      } else {
        _controller = SearchableBottomBarController();
        _ownsController = true;
      }
      _controller.addListener(_onControllerChanged);
    }
    if (widget.scrollController != old.scrollController) {
      old.scrollController?.removeListener(_onScrollMaybeWhiten);
      widget.scrollController?.addListener(_onScrollMaybeWhiten);
      _onScrollMaybeWhiten();
    }
    if (widget.whitenAtBottom != old.whitenAtBottom) {
      _onScrollMaybeWhiten();
    }
    _controller.onSearchActiveChanged(
      wasActive: old.isSearchActive,
      isActive: widget.isSearchActive,
    );
  }

  @override
  void dispose() {
    _tabWCtrl.dispose();
    _searchLeftCtrl.dispose();
    _searchWCtrl.dispose();
    widget.scrollController?.removeListener(_onScrollMaybeWhiten);
    _whitenBoostCtrl.dispose();
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onFocusLost() => _controller.onFocusChanged(false);

  void _onScrollMaybeWhiten() {
    final c = widget.scrollController;
    final atBottom = widget.whitenAtBottom &&
        c != null &&
        c.hasClients &&
        c.position.maxScrollExtent > 0 &&
        (c.position.maxScrollExtent - c.position.pixels) <=
            widget.whitenBottomThreshold;
    final target = atBottom ? 1.0 : 0.0;
    if (_whitenTarget != target) {
      _whitenTarget = target;
      _whitenBoostCtrl.animateTo(target,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  LiquidGlassSettings _applyWhiten(LiquidGlassSettings s, bool isLight) {
    final base = s.whitenStrength;
    final t = (widget.whitenAtBottom && isLight) ? _whitenBoostCtrl.value : 0.0;
    final eff = (base + (widget.whitenAtBottomTarget - base) * t)
        .clamp(0.0, 1.0)
        .toDouble();
    return s.copyWith(whitenStrength: eff);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.adaptiveBrightness && widget.brightnessOverride == null) {
      return _buildBar(context, null);
    }
    return GlassContentAwareBrightness(
      brightnessOverride: widget.brightnessOverride,
      onBrightnessChanged: widget.onBrightnessChanged,
      builder: (context, brightness, darkAmount) =>
          _buildBar(context, darkAmount),
    );
  }

  Widget _buildBar(BuildContext context, double? darkAmount) {
    final effectiveQuality = GlassThemeHelpers.resolveQuality(
      context,
      widgetQuality: widget.quality,
      fallback: GlassQuality.premium,
    );

    final resolvedGlowColors =
        GlassThemeData.of(context).glowColorsFor(context);
    final effectiveInteractionGlowColor =
        widget.interactionGlowColor ?? resolvedGlowColors.primary;

    final dynamicLabelColor = resolveBarLabelColor(context, darkAmount);
    final resolvedSelectedIconColor =
        widget.selectedIconColor ?? dynamicLabelColor;
    final resolvedUnselectedIconColor =
        widget.unselectedIconColor ?? dynamicLabelColor;

    final effectiveGlowBlurRadius = resolvedGlowColors.glowBlurRadius;
    final effectiveGlowSpreadRadius = resolvedGlowColors.glowSpreadRadius;
    final effectiveGlowOpacity = resolvedGlowColors.glowOpacity;

    final bool isLight = GlassTheme.brightnessOf(context) == Brightness.light;
    final effectiveSettings =
        _applyWhiten(widget.settings ?? _defaultGlassSettings, isLight);
    final searching = widget.isSearchActive;

    final barContent = TweenAnimationBuilder<double>(
      tween: Tween<double>(
          end: searching ? widget.searchBarHeight : widget.barHeight),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, animH, child) {
        return AdaptiveLiquidGlassLayer(
          settings: effectiveSettings,
          quality: effectiveQuality,
          platformViewBackdrop: widget.platformViewBackdrop,
          blendAmount: widget.enableBlend ? widget.blendAmount : 0,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.horizontalPadding,
              vertical: widget.verticalPadding,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalW = constraints.maxWidth;

                final keyboardH = MediaQuery.viewInsetsOf(context).bottom;
                final keyboardPresent = keyboardH > 0;
                final hasDismiss = widget.searchConfig.showsCancelButton;
                final isKeyboardActive =
                    _controller.searchFocused && keyboardPresent;
                final dismissVisible = searching &&
                    _controller.searchFocused &&
                    hasDismiss &&
                    keyboardPresent;

                final extraPos = widget.extraButton?.position ??
                    GlassExtraButtonPosition.beforeSearch;
                final extraFullW = widget.extraButton?.size ?? 0.0;
                final extraCollapsesOnSearch =
                    widget.extraButton?.collapseOnSearchFocus ?? true;

                final layout = _controller.computeLayout(
                  totalW: totalW,
                  searching: widget.isSearchActive,
                  expandWhenActive: widget.searchConfig.expandWhenActive,
                  barHeight: widget.barHeight,
                  searchBarHeight: widget.searchBarHeight,
                  spacing: widget.spacing,
                  hasDismiss: hasDismiss,
                  dismissVisible: dismissVisible,
                  collapsedTabWidth: widget.searchConfig.collapsedTabWidth,
                  tabPillAnchor: widget.tabPillAnchor,
                  extraFullW: extraFullW,
                  extraPos: extraPos,
                  extraCollapsesOnSearch: extraCollapsesOnSearch,
                  isKeyboardActive: isKeyboardActive,
                  keyboardH: keyboardH,
                  tabCount: widget.tabs.length,
                  perTabWidth: widget.tabWidth,
                );

                final targetTabW = layout.targetTabW;
                final targetSearchLeft = layout.targetSearchLeft;
                final targetSearchW = layout.targetSearchW;
                final targetH =
                    searching ? widget.searchBarHeight : widget.barHeight;
                final extraTargetW = layout.extraTargetW;
                final extraWLeft = (extraFullW > 0 &&
                        extraPos == GlassExtraButtonPosition.beforeSearch)
                    ? (extraTargetW + widget.spacing)
                    : 0.0;
                final doCollapseLayout =
                    isKeyboardActive && extraCollapsesOnSearch;
                final targetDismissReserve = layout.dismissReserve;
                final centeredTab =
                    widget.tabPillAnchor == GlassTabPillAnchor.center;
                final maxTabW = totalW -
                    targetH -
                    widget.spacing -
                    (extraFullW > 0 &&
                            extraPos == GlassExtraButtonPosition.beforeSearch
                        ? extraFullW + widget.spacing
                        : 0.0) -
                    (extraFullW > 0 &&
                            extraPos == GlassExtraButtonPosition.afterSearch
                        ? extraFullW + widget.spacing
                        : 0.0);

                if (!_controller.pillsInitialized &&
                    !_controller.pillsInitScheduled) {
                  _controller.markInitScheduled(totalW: totalW);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _tabWCtrl.value = targetTabW;
                    _searchLeftCtrl.value = targetSearchLeft;
                    _searchWCtrl.value = targetSearchW;
                    _controller.initializePills(
                      tabW: targetTabW,
                      searchLeft: targetSearchLeft,
                      searchW: targetSearchW,
                    );
                  });
                } else if (_controller.pillsInitialized) {
                  final retarget = _controller.checkRetarget(layout);
                  if (retarget.any) {
                    final fromTabW = _tabWCtrl.value;
                    final fromLeft = _searchLeftCtrl.value;
                    final fromSearchW = _searchWCtrl.value;
                    final toTabW = targetTabW;
                    final toLeft = targetSearchLeft;
                    final toSearchW = targetSearchW;

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final spring = widget.springDescription ??
                          TabBarSearchableLayout._kSpring;
                      if (retarget.tabW) {
                        _tabWCtrl.animateWith(
                            SearchableBottomBarController.makeSpring(
                                spring: spring, from: fromTabW, to: toTabW));
                      }
                      if (retarget.searchLeft) {
                        _searchLeftCtrl.animateWith(
                            SearchableBottomBarController.makeSpring(
                                spring: spring, from: fromLeft, to: toLeft));
                      }
                      if (retarget.searchW) {
                        _searchWCtrl.animateWith(
                            SearchableBottomBarController.makeSpring(
                                spring: spring,
                                from: fromSearchW,
                                to: toSearchW));
                      }
                    });
                  }
                  if (totalW != _controller.cachedTotalW) {
                    _controller.cachedTotalW = totalW;
                  }
                }

                // D1: curTabW, curTabLeft, curSearchLeft, curSearchW are now computed
                // inside their respective ListenableBuilder builders below, so each
                // Positioned child reads a fresh controller value on its own tick
                // without involving the enclosing LayoutBuilder or State.build().

                final floatY = layout.floatY;
                final totalH = animH + floatY;

                return SizedBox(
                  width: totalW,
                  height: totalH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1. Search pill — D1: rebuilt only when position/width tick.
                      ListenableBuilder(
                        listenable: _searchPillListenable,
                        builder: (context, _) {
                          final curSearchLeft = (_controller.pillsInitialized
                                  ? _searchLeftCtrl.value
                                  : targetSearchLeft)
                              .clamp(0.0, totalW);
                          final curSearchW = (_controller.pillsInitialized
                                  ? _searchWCtrl.value
                                  : targetSearchW)
                              .clamp(0.0, totalW);
                          return Positioned(
                            left: curSearchLeft,
                            bottom: floatY,
                            width: math.max(0.01, curSearchW),
                            height: animH,
                            child: SearchPill(
                              config: widget.searchConfig,
                              isActive: searching,
                              barBorderRadius: widget.barBorderRadius,
                              quality: effectiveQuality,
                              platformViewBackdrop: widget.platformViewBackdrop,
                              enableBackgroundAnimation:
                                  widget.interactionBehavior.hasScale,
                              backgroundPressScale: widget.pressScale,
                              iconColor: resolvedUnselectedIconColor,
                              interactionGlowColor:
                                  widget.interactionBehavior.hasGlow
                                      ? effectiveInteractionGlowColor
                                      : const Color(0x00000000),
                              interactionGlowRadius:
                                  widget.interactionGlowRadius,
                              interactionGlowBlurRadius:
                                  effectiveGlowBlurRadius,
                              interactionGlowSpreadRadius:
                                  effectiveGlowSpreadRadius,
                              interactionGlowOpacity: effectiveGlowOpacity,
                              onFocusChanged: (focused) {
                                if (focused) {
                                  _controller.onFocusChanged(true);
                                } else {
                                  _onFocusLost();
                                }
                                widget.searchConfig.onSearchFocusChanged
                                    ?.call(focused);
                              },
                            ),
                          );
                        },
                      ),

                      // 2. Optional extra button — D1: left position tracks _searchLeftCtrl.
                      if (widget.extraButton != null)
                        ListenableBuilder(
                          listenable: _searchLeftCtrl,
                          builder: (context, _) {
                            final curSearchLeft = (_controller.pillsInitialized
                                    ? _searchLeftCtrl.value
                                    : targetSearchLeft)
                                .clamp(0.0, totalW);
                            return Positioned(
                              left: extraPos ==
                                      GlassExtraButtonPosition.beforeSearch
                                  ? curSearchLeft - extraWLeft
                                  : null,
                              right: extraPos ==
                                      GlassExtraButtonPosition.afterSearch
                                  ? (dismissVisible
                                      ? targetDismissReserve
                                      : 0.0)
                                  : null,
                              bottom: extraCollapsesOnSearch ? 0 : floatY,
                              width: doCollapseLayout
                                  ? math.min(extraTargetW, animH)
                                  : extraTargetW,
                              height: animH,
                              child: AnimatedOpacity(
                                opacity: (searching && extraCollapsesOnSearch)
                                    ? 0.0
                                    : 1.0,
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                child: IgnorePointer(
                                  ignoring: searching && extraCollapsesOnSearch,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: BottomBarExtraBtn(
                                      config: widget.extraButton!,
                                      quality: effectiveQuality,
                                      iconColor:
                                          widget.extraButton!.iconColor ??
                                              resolvedUnselectedIconColor,
                                      enableBlend: widget.enableBlend,
                                      borderRadius: widget.barBorderRadius ==
                                              TabBarSearchableLayout
                                                  ._kDefaultBorderRadius
                                          ? null
                                          : widget.barBorderRadius,
                                      platformViewBackdrop:
                                          widget.platformViewBackdrop,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                      // 3. Tab pill — D1: rebuilt only when _tabWCtrl ticks.
                      //    childUnselected is passed as ListenableBuilder.child so the
                      //    unselected row is built once and reused across spring ticks.
                      ListenableBuilder(
                        listenable: _tabWCtrl,
                        child: _buildTabRow(
                          selected: false,
                          resolvedSelectedIconColor: resolvedSelectedIconColor,
                          resolvedUnselectedIconColor:
                              resolvedUnselectedIconColor,
                        ),
                        builder: (context, child) {
                          final curTabW = (_controller.pillsInitialized
                                  ? _tabWCtrl.value
                                  : targetTabW)
                              .clamp(0.0, totalW);
                          final curTabLeft = centeredTab
                              ? ((maxTabW - curTabW) / 2).clamp(0.0, maxTabW)
                              : 0.0;
                          return Positioned(
                            left: curTabLeft,
                            bottom: 0,
                            width: math.max(0.01, curTabW),
                            height: animH,
                            child: SearchableTabIndicator(
                              key: _indicatorKey,
                              quality: effectiveQuality,
                              visible: widget.showIndicator && !searching,
                              tabIndex: widget.selectedIndex,
                              tabCount: widget.tabs.length,
                              onTabChanged: widget.onTabSelected,
                              barHeight: animH,
                              barBorderRadius: widget.barBorderRadius,
                              indicatorBorderRadius:
                                  widget.indicatorBorderRadius,
                              tabPadding: widget.tabPadding,
                              maskingQuality: widget.maskingQuality,
                              magnification: widget.magnification,
                              innerBlur: widget.innerBlur,
                              indicatorColor: widget.indicatorColor,
                              indicatorExpansion: widget.indicatorExpansion,
                              indicatorSettings: widget.indicatorSettings,
                              indicatorPinchStrength:
                                  widget.indicatorPinchStrength,
                              backgroundKey: widget.backgroundKey,
                              platformViewBackdrop: widget.platformViewBackdrop,
                              isSearchActive: searching,
                              interactionGlowColor:
                                  widget.interactionBehavior.hasGlow
                                      ? effectiveInteractionGlowColor
                                      : const Color(0x00000000),
                              interactionGlowRadius:
                                  widget.interactionGlowRadius,
                              interactionGlowBlurRadius:
                                  effectiveGlowBlurRadius,
                              interactionGlowSpreadRadius:
                                  effectiveGlowSpreadRadius,
                              interactionGlowOpacity: effectiveGlowOpacity,
                              enableBackgroundAnimation:
                                  widget.interactionBehavior.hasScale,
                              backgroundPressScale: widget.pressScale,
                              collapsedLogoBuilder:
                                  widget.searchConfig.collapsedLogoBuilder ??
                                      (context) {
                                        final currentTab =
                                            widget.tabs[widget.selectedIndex];
                                        return Center(
                                          child: IconTheme(
                                            data: IconThemeData(
                                              color: widget.unselectedIconColor,
                                              size: widget.iconSize,
                                            ),
                                            child: currentTab.activeIcon ??
                                                currentTab.icon,
                                          ),
                                        );
                                      },
                              onDismissSearch: () =>
                                  widget.searchConfig.onSearchToggle(false),
                              childUnselected: child!,
                              selectedTabBuilder: (ctx, intensity, alignment) =>
                                  _buildTabRow(
                                selected: true,
                                intensity: intensity,
                                alignment: alignment,
                                resolvedSelectedIconColor:
                                    resolvedSelectedIconColor,
                                resolvedUnselectedIconColor:
                                    resolvedUnselectedIconColor,
                              ),
                            ),
                          );
                        },
                      ),

                      // 4. Dismiss × pill
                      if (hasDismiss && dismissVisible)
                        Positioned(
                          right: 0,
                          bottom: floatY,
                          width: animH,
                          height: animH,
                          child: DismissPill(
                            onTap: () {
                              widget.searchConfig.onCancelTap?.call();
                              FocusManager.instance.primaryFocus?.unfocus();
                            },
                            pillSize: animH,
                            barBorderRadius: widget.barBorderRadius,
                            quality: effectiveQuality,
                            indicatorColor: widget.indicatorColor,
                            settings: widget.settings,
                            cancelButtonColor:
                                widget.searchConfig.cancelButtonColor,
                            cancelIcon: widget.searchConfig.cancelIcon,
                            cancelIconSize: widget.searchConfig.cancelIconSize,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (widget.onBarTap == null) return barContent;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onBarTap,
      child: barContent,
    );
  }

  Widget _buildTabRow({
    required bool selected,
    required Color resolvedSelectedIconColor,
    required Color resolvedUnselectedIconColor,
    double intensity = 0,
    Alignment alignment = Alignment.center,
  }) {
    if (selected) {
      final scale = ui.lerpDouble(1.0, widget.magnification, intensity) ?? 1.0;
      final currentTabFloat = ((alignment.x + 1) / 2) * widget.tabs.length;
      final aStart =
          (currentTabFloat - 1).floor().clamp(0, widget.tabs.length - 1);
      final aEnd =
          (currentTabFloat + 1).ceil().clamp(0, widget.tabs.length - 1);

      return Row(
        children: [
          for (var i = 0; i < widget.tabs.length; i++)
            Expanded(
              child: (i >= aStart && i <= aEnd)
                  ? Transform.scale(
                      scale: scale,
                      child: BottomBarTabItem(
                        tab: widget.tabs[i],
                        selected: true,
                        selectedIconColor: resolvedSelectedIconColor,
                        unselectedIconColor: resolvedUnselectedIconColor,
                        selectedLabelColor: widget.selectedLabelColor,
                        unselectedLabelColor: widget.unselectedLabelColor,
                        selectedLabelStyle: widget.selectedLabelStyle,
                        unselectedLabelStyle: widget.unselectedLabelStyle,
                        iconSize: widget.iconSize,
                        labelFontSize: widget.labelFontSize,
                        textStyle: widget.textStyle,
                        iconLabelSpacing: widget.iconLabelSpacing,
                        glowDuration: widget.glowDuration,
                        glowBlurRadius: widget.glowBlurRadius,
                        glowSpreadRadius: widget.glowSpreadRadius,
                        glowOpacity: widget.glowOpacity,
                        onTap: null,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < widget.tabs.length; i++)
          Expanded(
            child: BottomBarTabItem(
              tab: widget.tabs[i],
              selected: false,
              selectedIconColor: resolvedSelectedIconColor,
              unselectedIconColor: resolvedUnselectedIconColor,
              selectedLabelColor: widget.selectedLabelColor,
              unselectedLabelColor: widget.unselectedLabelColor,
              selectedLabelStyle: widget.selectedLabelStyle,
              unselectedLabelStyle: widget.unselectedLabelStyle,
              iconSize: widget.iconSize,
              labelFontSize: widget.labelFontSize,
              textStyle: widget.textStyle,
              iconLabelSpacing: widget.iconLabelSpacing,
              glowDuration: widget.glowDuration,
              glowBlurRadius: widget.glowBlurRadius,
              glowSpreadRadius: widget.glowSpreadRadius,
              glowOpacity: widget.glowOpacity,
              onTap: null,
            ),
          ),
      ],
    );
  }
}
