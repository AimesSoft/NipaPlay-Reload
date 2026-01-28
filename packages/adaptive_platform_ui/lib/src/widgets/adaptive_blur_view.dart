import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../platform/platform_info.dart';

/// A widget that applies a platform-specific blur effect to its background
///
/// - On iOS 26+: Uses native UIVisualEffectView with systemUltraThinMaterial
/// - On iOS <26: Uses BackdropFilter with ImageFilter.blur
/// - On Android: Uses BackdropFilter with ImageFilter.blur
class AdaptiveBlurView extends StatelessWidget {
  const AdaptiveBlurView({
    super.key,
    required this.child,
    this.blurStyle = BlurStyle.systemUltraThinMaterial,
    this.borderRadius,
  });

  /// The widget to display on top of the blur effect
  final Widget child;

  /// The blur style (iOS only)
  /// On iOS 26+, uses UIBlurEffect styles
  /// On iOS <26 and Android, uses BackdropFilter
  final BlurStyle blurStyle;

  /// Border radius for the blur view (optional)
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    // iOS 26+ uses native UIVisualEffectView
    if (PlatformInfo.isIOS && PlatformInfo.isIOSVersionInRange(26, 99)) {
      return Ios26NativeBlurView(
        blurStyle: blurStyle,
        borderRadius: borderRadius,
        child: child,
      );
    }

    // iOS <26 and Android use Flutter Liquid Glass effect
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        children: [
          // Background blur layer
          Positioned.fill(
            child: BackdropFilter(
              filter: blurStyle.toImageFilter(),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: _getLiquidGlassGradient(context),
                ),
              ),
            ),
          ),
          // Frosted glass overlay with noise texture effect
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _getGlassOverlayColors(context),
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // Subtle inner glow for depth
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: _getBorderColor(context), width: 0.5),
              ),
            ),
          ),
          // Content on top
          child,
        ],
      ),
    );
  }

  LinearGradient _getLiquidGlassGradient(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    switch (blurStyle) {
      case BlurStyle.systemUltraThinMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.03),
                  Colors.white.withValues(alpha: 0.05),
                  Colors.white.withValues(alpha: 0.03),
                ]
              : [
                  Colors.white.withValues(alpha: 0.25),
                  Colors.white.withValues(alpha: 0.35),
                  Colors.white.withValues(alpha: 0.25),
                ],
        );
      case BlurStyle.systemThinMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.06),
                ]
              : [
                  Colors.white.withValues(alpha: 0.4),
                  Colors.white.withValues(alpha: 0.5),
                  Colors.white.withValues(alpha: 0.4),
                ],
        );
      case BlurStyle.systemMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.1),
                ]
              : [
                  Colors.white.withValues(alpha: 0.6),
                  Colors.white.withValues(alpha: 0.7),
                  Colors.white.withValues(alpha: 0.6),
                ],
        );
      case BlurStyle.systemThickMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.13),
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.13),
                ]
              : [
                  Colors.white.withValues(alpha: 0.75),
                  Colors.white.withValues(alpha: 0.8),
                  Colors.white.withValues(alpha: 0.75),
                ],
        );
      case BlurStyle.systemChromeMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.45),
                ]
              : [
                  Colors.white.withValues(alpha: 0.85),
                  Colors.white.withValues(alpha: 0.9),
                  Colors.white.withValues(alpha: 0.85),
                ],
        );
    }
  }

  List<Color> _getGlassOverlayColors(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    if (isDark) {
      return [
        Colors.white.withValues(alpha: 0.01),
        Colors.transparent,
        Colors.black.withValues(alpha: 0.02),
      ];
    } else {
      return [
        Colors.white.withValues(alpha: 0.15),
        Colors.transparent,
        Colors.white.withValues(alpha: 0.08),
      ];
    }
  }

  Color _getBorderColor(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    switch (blurStyle) {
      case BlurStyle.systemUltraThinMaterial:
      case BlurStyle.systemThinMaterial:
        return isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.5);
      case BlurStyle.systemMaterial:
      case BlurStyle.systemThickMaterial:
        return isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.6);
      case BlurStyle.systemChromeMaterial:
        return isDark
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.7);
    }
  }
}

/// Blur styles matching iOS UIBlurEffect.Style
enum BlurStyle {
  /// Ultra-thin material (iOS 26+ Liquid Glass default)
  systemUltraThinMaterial,

  /// Thin material
  systemThinMaterial,

  /// Regular material
  systemMaterial,

  /// Thick material
  systemThickMaterial,

  /// Chrome material (most opaque)
  systemChromeMaterial,
}

extension BlurStyleExtension on BlurStyle {
  /// Convert to UIBlurEffect.Style string for native iOS
  String toUIBlurEffectStyle() {
    switch (this) {
      case BlurStyle.systemUltraThinMaterial:
        return 'systemUltraThinMaterial';
      case BlurStyle.systemThinMaterial:
        return 'systemThinMaterial';
      case BlurStyle.systemMaterial:
        return 'systemMaterial';
      case BlurStyle.systemThickMaterial:
        return 'systemThickMaterial';
      case BlurStyle.systemChromeMaterial:
        return 'systemChromeMaterial';
    }
  }

  /// Convert to ImageFilter for BackdropFilter (iOS <26 and Android)
  ui.ImageFilter toImageFilter() {
    switch (this) {
      case BlurStyle.systemUltraThinMaterial:
        return ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10);
      case BlurStyle.systemThinMaterial:
        return ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15);
      case BlurStyle.systemMaterial:
        return ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20);
      case BlurStyle.systemThickMaterial:
        return ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25);
      case BlurStyle.systemChromeMaterial:
        return ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30);
    }
  }
}

/// iOS 26+ native blur view using UIVisualEffectView
class Ios26NativeBlurView extends StatefulWidget {
  const Ios26NativeBlurView({
    super.key,
    required this.child,
    required this.blurStyle,
    this.borderRadius,
  });

  final Widget child;
  final BlurStyle blurStyle;
  final BorderRadius? borderRadius;

  @override
  State<Ios26NativeBlurView> createState() => Ios26NativeBlurViewState();
}

class Ios26NativeBlurViewState extends State<Ios26NativeBlurView> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(Ios26NativeBlurView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blurStyle != widget.blurStyle && _channel != null) {
      _updateBlurStyle();
    }
  }

  Future<void> _updateBlurStyle() async {
    try {
      await _channel?.invokeMethod('updateBlurStyle', {
        'blurStyle': widget.blurStyle.toUIBlurEffectStyle(),
      });
    } catch (e) {
      // Ignore errors during blur style update
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: Stack(
        children: [
          // Native blur view in background
          Positioned.fill(
            child: UiKitView(
              viewType: 'adaptive_platform_ui/ios26_blur_view',
              creationParams: {
                'blurStyle': widget.blurStyle.toUIBlurEffectStyle(),
              },
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: (int id) {
                _channel = MethodChannel(
                  'adaptive_platform_ui/ios26_blur_view_$id',
                );
              },
            ),
          ),
          // Child on top
          widget.child,
        ],
      ),
    );
  }
}
