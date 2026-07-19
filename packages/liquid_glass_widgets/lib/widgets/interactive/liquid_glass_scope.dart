import 'package:flutter/widgets.dart';

/// A scope that provides infrastructure for glass refraction on Skia and Web.
///
/// Place [LiquidGlassScope] at the root of a stack or page.
/// Descendant [GlassEffect] widgets (used by [GlassSegmentedControl],
/// [GlassTabBar], [GlassBottomBar]) will automatically find and sample the
/// capture surface marked by [GlassRefractionSource].
///
/// On Impeller, [LiquidGlassScope] is not needed — `GlassQuality.premium`
/// uses the native scene graph for refraction.
///
/// Usage:
/// ```dart
/// LiquidGlassScope(
///   child: Stack(
///     children: [
///       // 1. Mark the capture surface
///       GlassRefractionSource(
///         child: Image.asset('wallpaper.jpg'),
///       ),
///
///       // 2. Glass widgets sample it automatically
///       Center(child: GlassSegmentedControl(...)),
///     ],
///   ),
/// )
/// ```
class LiquidGlassScope extends StatefulWidget {
  const LiquidGlassScope({
    required this.child,
    super.key,
  });

  /// Convenience constructor for the common pattern of a background behind content.
  ///
  /// This eliminates the boilerplate of manually creating a Stack with Positioned.fill
  /// widgets. It's equivalent to:
  ///
  /// ```dart
  /// LiquidGlassScope(
  ///   child: Stack(
  ///     children: [
  ///       Positioned.fill(
  ///         child: GlassBackgroundSource(child: background),
  ///       ),
  ///       Positioned.fill(child: content),
  ///     ],
  ///   ),
  /// )
  /// ```
  ///
  /// Example:
  /// ```dart
  /// LiquidGlassScope.stack(
  ///   background: Image.asset('wallpaper.jpg', fit: BoxFit.cover),
  ///   content: Scaffold(
  ///     body: MyContent(),
  ///     bottomNavigationBar: GlassBottomBar(...),
  ///   ),
  /// )
  /// ```
  @Deprecated(
    'Use GlassPage instead. GlassPage automatically handles Scaffold transparency '
    'and adaptive quality degradation. This factory will be removed in 1.0.0.',
  )
  factory LiquidGlassScope.stack({
    Key? key,
    required Widget background,
    required Widget content,
  }) {
    return LiquidGlassScope(
      key: key,
      child: Stack(
        children: [
          Positioned.fill(
            child: GlassBackgroundSource(child: background),
          ),
          content, // Don't wrap in Positioned - let it naturally fill
        ],
      ),
    );
  }

  final Widget child;

  /// Returns the background key from the nearest ancestor scope.
  static GlobalKey? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_InheritedLiquidGlassScope>()
        ?.backgroundKey;
  }

  @override
  State<LiquidGlassScope> createState() => _LiquidGlassScopeState();
}

class _LiquidGlassScopeState extends State<LiquidGlassScope> {
  // Create the key ONCE and keep it stable across rebuilds
  final GlobalKey _backgroundKey =
      GlobalKey(debugLabel: 'LiquidGlassBackground');

  @override
  Widget build(BuildContext context) {
    return _InheritedLiquidGlassScope(
      backgroundKey: _backgroundKey,
      child: widget.child,
    );
  }
}

/// Marks a widget as the texture capture source for the nearest [LiquidGlassScope].
///
/// Wraps [child] in a [RepaintBoundary] tagged with the scope's [GlobalKey].
/// Descendant [GlassEffect] widgets (e.g. [GlassCard], [GlassSegmentedControl])
/// will sample this boundary every frame to produce real background colour absorption
/// on Skia and Web paths, simulating true physical glass.
///
/// On Impeller with `GlassQuality.premium`, this is not needed — the native
/// scene graph handles color absorption and refraction without a captured boundary.
///
/// If [enabled] is false, the widget will not inject a [RepaintBoundary] and
/// will simply return its child, allowing [GlassAdaptiveScope] to disable
/// sampling gracefully during high GPU load.
///
/// Typically you do not use this directly. Use [GlassPage] at the root of your route.
///
/// ```dart
/// GlassPage(
///   background: Image.asset('wallpaper.jpg', fit: BoxFit.cover),
///   child: Scaffold(...),
/// )
/// ```
///
/// Or manually, for granular control:
///
/// ```dart
/// GlassBackgroundSource(
///   enabled: true,
///   child: Image.asset('wallpaper.jpg'),
/// )
/// ```
class GlassBackgroundSource extends StatelessWidget {
  const GlassBackgroundSource({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// Whether the background should be captured into a texture.
  /// If false, glass surfaces will fall back to a synthetic frosted tint.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final key = LiquidGlassScope.of(context);

    assert(() {
      if (key == null) {
        debugPrint(
          'ℹ️ [GlassBackgroundSource] No LiquidGlassScope found in the widget tree.\n'
          '   The background will render normally but glass will use\n'
          '   synthetic frost instead of real background colour sampling.\n'
          '   Use GlassPage or wrap your widget tree with LiquidGlassScope to enable sampling.',
        );
      }
      return true;
    }());

    // If no scope is found, render the child normally — no silent failures.
    if (key == null) return child;

    return RepaintBoundary(
      key: key,
      child: child,
    );
  }
}

/// Deprecated: use [GlassBackgroundSource] instead.
///
/// [GlassRefractionSource] was renamed to [GlassBackgroundSource] in 0.11.0
/// to better reflect its purpose for absorbing background colors, not just refraction.
@Deprecated(
  'Use GlassBackgroundSource instead. '
  'GlassRefractionSource was renamed in 0.11.0 for clarity. '
  'This alias will be removed in 1.0.0.',
)
typedef GlassRefractionSource = GlassBackgroundSource;

/// Deprecated: use [GlassBackgroundSource] instead.
@Deprecated(
  'Use GlassBackgroundSource instead. '
  'This alias will be removed in 1.0.0.',
)
typedef LiquidGlassBackground = GlassBackgroundSource;

class _InheritedLiquidGlassScope extends InheritedWidget {
  const _InheritedLiquidGlassScope({
    required this.backgroundKey,
    required super.child,
  });

  final GlobalKey backgroundKey;

  @override
  bool updateShouldNotify(_InheritedLiquidGlassScope oldWidget) {
    return backgroundKey != oldWidget.backgroundKey;
  }
}
