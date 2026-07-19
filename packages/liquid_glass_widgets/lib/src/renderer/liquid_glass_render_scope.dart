import 'package:flutter/widgets.dart';
import 'liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

@internal
class LiquidGlassRenderScope extends InheritedWidget {
  /// Creates a new [LiquidGlassRenderScope].
  const LiquidGlassRenderScope({
    required this.settings,
    required super.child,
    super.key,
  });

  final LiquidGlassSettings settings;

  static LiquidGlassRenderScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    assert(
      scope != null,
      'No liquid glass renderer found in context. '
      'Make sure to wrap your liquid glass widgets in a LiquidGlassLayer.',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! LiquidGlassRenderScope ||
        oldWidget.settings != settings;
  }
}
