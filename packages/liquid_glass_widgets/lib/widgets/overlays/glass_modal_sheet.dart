import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../src/renderer/liquid_glass_renderer.dart';
import '../../theme/glass_theme_helpers.dart';
import '../../theme/glass_theme.dart';
import '../../types/glass_quality.dart';
import '../shared/adaptive_glass.dart';
import '../../src/renderer/internal/interaction_notification.dart';
import 'shared/glass_sheet_defaults.dart';

part 'shared/glass_modal_sheet_mechanics.dart';
part 'shared/glass_modal_sheet_internal.dart';
part 'shared/glass_modal_sheet_state.dart';

/// A high-fidelity, liquid glass modal sheet inspired by iOS 18+ design patterns.
///
/// [GlassModalSheet] provides a fluid, multi-state modal experience (peek, half, full)
/// with advanced glass morphism effects, interactive scaling, and physics-based gestures.
class GlassModalSheet extends StatefulWidget {
  // ===========================================================================
  // Content Properties
  // ===========================================================================

  /// The primary content widget displayed inside the glass sheet.
  final Widget child;

  // ===========================================================================
  // Geometry Properties
  // ===========================================================================

  /// Height in the 'half' state (0.0 - 1.0 fraction or absolute pixels). Default: 0.45.
  final double halfSize;

  /// Maximum sheet height in 'full' state.
  ///
  /// - If 0.0 < value <= 1.0: Treated as fraction of screen height.
  /// - If value > 1.0: Treated as absolute pixels.
  /// - If null: Defaults to screen height minus 90px (iOS Page Sheet style).
  final double? fullSize;

  /// Height in the 'peek' state. Default: 90.0.
  final double peekSize;

  /// Internal padding for the sheet content.
  final EdgeInsetsGeometry? padding;

  /// Initial state when the sheet is first shown.
  final GlassSheetState initialState;

  // ===========================================================================
  // Appearance Properties
  // ===========================================================================

  /// If null, it will be automatically resolved based on the device's
  /// physical geometry (adaptive radius).
  final double? topBorderRadius;

  /// If null, it will be automatically resolved based on the device's
  /// physical geometry (adaptive radius).
  final double? bottomBorderRadius;

  /// Corner radius of the top edges when fully expanded (full).
  final double? fullTopBorderRadius;

  /// Corner radius of the bottom edges when fully expanded (full).
  final double? fullBottomBorderRadius;

  /// Corner radius specifically for the 'peek' state.
  final double? peekTopBorderRadius;

  /// Corner radius specifically for the 'peek' state.
  final double? peekBottomRadius;

  /// Horizontal padding between the sheet and the screen edges.
  final double horizontalMargin;

  /// Horizontal padding specifically for the 'peek' state.
  /// If null, [horizontalMargin] is used.
  final double? peekHorizontalMargin;

  /// Bottom padding from the screen edge.
  final double bottomMargin;

  /// Bottom padding specifically for the 'peek' state.
  /// If null, [bottomMargin] is used.
  final double? peekBottomMargin;

  /// Fixed width for the 'peek' state.
  /// If provided, the sheet will morph from this width to full width.
  final double? peekWidth;

  /// Color/Saturation transition mode when expanding to full state.
  final GlassFillTransition fillTransition;

  /// Threshold (0.0 - 1.0) at which the sheet starts turning into a solid color.
  final double fillThreshold;

  /// Glass morphism effect settings (blur, thickness, lighting).
  final LiquidGlassSettings? settings;

  /// Background color used when the sheet is fully expanded and opaque.
  final Color? expandedColor;

  /// Rendering quality (BackdropFilter vs Shader). Defaults to standard.
  final GlassQuality? quality;

  /// When true (typically over an iOS PlatformView), forces the BackdropFilter
  /// fallback render path so premium glass renders cleanly over the
  /// PlatformView instead of as a solid slab. Forwarded to the sheet's
  /// underlying [AdaptiveGlass]. Defaults to false.
  final bool platformViewBackdrop;

  // ===========================================================================
  // Physics & Interaction Properties
  // ===========================================================================

  /// Scale factor applied during interaction for tactile feedback. Default: 1.01.
  final double interactionScale;

  /// Whether to show glow/glare on touch for tactile feedback. Default: true.
  final bool enableInteractionGlow;

  /// Whether to pulse saturation/lighting of the whole sheet on touch. Default: true.
  final bool enableSaturationGlow;

  /// Optional state-specific settings that override the base [settings].
  final LiquidGlassSettings? peekSettings;
  final LiquidGlassSettings? halfSettings;
  final LiquidGlassSettings? fullSettings;

  /// Liquid stretch multiplier for over-scroll/drag effects. Default: 0.5.
  final double stretch;

  /// Resistance factor when dragging beyond bounds. Default: 0.08.
  final double resistance;

  /// Snap progress threshold (0.0 - 1.0). Default: 0.4.
  final double snapThreshold;

  /// Velocity threshold for flick gestures (pixels/sec). Default: 700.0.
  final double velocityThreshold;

  /// Custom color for the touch interaction glow.
  final Color? glowColor;

  /// Radius of the touch interaction glow. Default: 1.5.
  final double glowRadius;

  /// Whether to prevent sheet scaling when interacting with children. Default: false.
  final bool suppressInteractionOnChildren;

  /// Controller for programmatic sheet control (snap, animate).
  final GlassModalSheetController? controller;

  /// Callback triggered when the sheet snaps to a new state.
  final ValueChanged<GlassSheetState>? onStateChanged;

  /// Interaction mode (dismissible vs persistent).
  final GlassSheetMode mode;

  /// Whether the 'peek' state is enabled.
  ///
  /// If null, it defaults to false for [GlassSheetMode.dismissible] and true for
  /// [GlassSheetMode.persistent].
  final bool? enablePeek;

  // ===========================================================================
  // Drag Indicator Properties
  // ===========================================================================

  /// Whether to show the iOS-style drag handle at the top. Default: true.
  final bool showDragIndicator;

  /// Custom color for the drag handle.
  final Color? dragIndicatorColor;

  /// Width of the drag handle pill in logical pixels. Defaults to 36
  /// (iOS native). Bump higher (e.g. 64) for sheets where the handle
  /// reads as the primary affordance and the thinner default feels
  /// too subtle relative to the rest of the sheet's content.
  final double dragIndicatorWidth;

  /// Whether to enable a gradient fade effect at the top of the sheet.
  final bool enableTopFade;

  /// The height of the top fade effect in pixels. Default: 40.0.
  final double topFadeHeight;

  /// Whether to maintain high glass vibrancy for content even when the sheet is solid (full state).
  final bool maintainContentGlass;

  /// Custom glass settings for content specifically for the 'full' state.
  final LiquidGlassSettings? fullStateContentSettings;

  const GlassModalSheet({
    super.key,
    required this.child,
    this.halfSize = 0.45,
    this.fullSize,
    this.initialState = GlassSheetState.half,
    this.topBorderRadius = 56,
    this.bottomBorderRadius,
    this.fullTopBorderRadius = 46,
    this.fullBottomBorderRadius,
    this.horizontalMargin = 5.0,
    this.bottomMargin = 6.0,
    this.fillThreshold = 0.60,
    this.interactionScale = 1.01,
    this.enableInteractionGlow = true,
    this.enableSaturationGlow = true,
    this.peekSettings,
    this.halfSettings,
    this.fullSettings,
    this.stretch = 0.5,
    this.resistance = 0.08,
    this.snapThreshold = 0.4,
    this.velocityThreshold = 700.0,
    this.settings,
    this.quality,
    this.platformViewBackdrop = false,
    this.expandedColor,
    this.controller,
    this.onStateChanged,
    this.mode = GlassSheetMode.dismissible,
    this.peekSize = 90.0,
    this.fillTransition = GlassFillTransition.instant,
    this.showDragIndicator = true,
    this.dragIndicatorColor,
    this.dragIndicatorWidth = 36,
    this.glowColor,
    this.glowRadius = 1.5,
    this.suppressInteractionOnChildren = false,
    this.padding,
    this.enableTopFade = false,
    this.topFadeHeight = 40.0,
    this.maintainContentGlass = true,
    this.fullStateContentSettings,
    this.enablePeek,
    this.peekHorizontalMargin,
    this.peekBottomMargin,
    this.peekWidth,
    this.peekTopBorderRadius,
    this.peekBottomRadius,
  });

  /// Shows a high-fidelity glass modal sheet.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    double halfSize = 0.45,
    double? fullSize,
    GlassSheetState initialState = GlassSheetState.half,
    double fillThreshold = 0.60,
    LiquidGlassSettings? settings,
    Color? expandedColor,
    ValueChanged<GlassSheetState>? onStateChanged,
    GlassSheetMode mode = GlassSheetMode.dismissible,
    double peekSize = 90.0,
    GlassQuality? quality,
    bool platformViewBackdrop = false,
    Color barrierColor = Colors.black54,
    bool isDismissible = true,
    bool useRootNavigator = false,
    double interactionScale = 1.01,
    bool enableInteractionGlow = true,
    bool enableSaturationGlow = true,
    LiquidGlassSettings? peekSettings,
    LiquidGlassSettings? halfSettings,
    LiquidGlassSettings? fullSettings,
    double stretch = 0.5,
    GlassModalSheetController? controller,
    GlassFillTransition fillTransition = GlassFillTransition.instant,
    bool showDragIndicator = true,
    Color? dragIndicatorColor,
    double dragIndicatorWidth = 36,
    double? topBorderRadius = 56,
    double? bottomBorderRadius,
    double? fullTopBorderRadius = 46,
    double? fullBottomBorderRadius,
    double horizontalMargin = 8.0,
    double bottomMargin = 8.0,
    double resistance = 0.08,
    double snapThreshold = 0.4,
    double velocityThreshold = 700.0,
    Color? glowColor,
    double glowRadius = 1.5,
    bool suppressInteractionOnChildren = false,
    EdgeInsetsGeometry? padding,
    bool enableTopFade = false,
    double topFadeHeight = 40.0,
    bool maintainContentGlass = true,
    LiquidGlassSettings? fullStateContentSettings,
    bool? enablePeek,
    double? peekHorizontalMargin,
    double? peekBottomMargin,
    double? peekWidth,
    double? peekTopBorderRadius,
    double? peekBottomRadius,
  }) {
    assert(() {
      if (mode == GlassSheetMode.persistent &&
          barrierColor == Colors.transparent) {
        debugPrint(
          '[GlassModalSheet] WARNING: show() with persistent mode and '
          'transparent barrier does NOT provide true hit-through interaction. '
          'Use GlassModalSheetScaffold directly for maps-style hit-through UI.',
        );
      }
      return true;
    }());

    final effectiveController = controller ?? GlassModalSheetController();
    bool isClosing = false;

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierLabel: 'Dismiss',
      barrierColor: barrierColor,
      useRootNavigator: useRootNavigator,
      transitionDuration: const Duration(milliseconds: 500),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
          ),
          child: child,
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return GlassModalSheetScaffold(
          controller: effectiveController,
          halfSize: halfSize,
          fullSize: fullSize,
          initialState: initialState,
          fillThreshold: fillThreshold,
          settings: settings,
          expandedColor: expandedColor,
          mode: mode,
          peekSize: peekSize,
          quality: quality,
          platformViewBackdrop: platformViewBackdrop,
          interactionScale: interactionScale,
          enableInteractionGlow: enableInteractionGlow,
          enableSaturationGlow: enableSaturationGlow,
          peekSettings: peekSettings,
          halfSettings: halfSettings,
          fullSettings: fullSettings,
          stretch: stretch,
          fillTransition: fillTransition,
          showDragIndicator: showDragIndicator,
          dragIndicatorColor: dragIndicatorColor,
          dragIndicatorWidth: dragIndicatorWidth,
          topBorderRadius: topBorderRadius,
          bottomBorderRadius: bottomBorderRadius,
          fullTopBorderRadius: fullTopBorderRadius,
          fullBottomBorderRadius: fullBottomBorderRadius,
          horizontalMargin: horizontalMargin,
          bottomMargin: bottomMargin,
          resistance: resistance,
          snapThreshold: snapThreshold,
          velocityThreshold: velocityThreshold,
          glowColor: glowColor,
          glowRadius: glowRadius,
          suppressInteractionOnChildren: suppressInteractionOnChildren,
          padding: padding,
          enableTopFade: enableTopFade,
          topFadeHeight: topFadeHeight,
          maintainContentGlass: maintainContentGlass,
          fullStateContentSettings: fullStateContentSettings,
          enablePeek: enablePeek,
          peekHorizontalMargin: peekHorizontalMargin,
          peekBottomMargin: peekBottomMargin,
          peekWidth: peekWidth,
          peekTopBorderRadius: peekTopBorderRadius,
          peekBottomRadius: peekBottomRadius,
          onStateChanged: (state) {
            onStateChanged?.call(state);
            if (state == GlassSheetState.hidden && !isClosing) {
              isClosing = true;
              Navigator.of(context).pop();
            }
          },
          body: const SizedBox.shrink(),
          sheet: builder(context),
        );
      },
    );
  }

  @override
  State<GlassModalSheet> createState() => _GlassModalSheetState();
}
