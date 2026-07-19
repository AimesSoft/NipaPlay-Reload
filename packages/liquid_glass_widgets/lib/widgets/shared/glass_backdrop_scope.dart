import 'package:flutter/widgets.dart';

/// **Deprecated** — this widget is now a no-op. Remove it from your tree.
///
/// Prior to 0.14.0, this widget installed a shared [BackdropGroup] that all
/// glass surfaces used for GPU blur-sharing. Each [LiquidGlassLayer] now
/// manages its own isolated [BackdropGroup], which:
///
/// - **Fixes visual corruption** on Impeller when multiple layers shared one
///   [BackdropGroup] (e.g. app bar backgrounds disappearing).
/// - **Reduces GPU bandwidth** — each layer captures only its own clipped
///   bounding box instead of a full-screen texture.
/// - **Eliminates ghost artefacts** on route transitions — no stale texture
///   from the previous page can bleed through.
///
/// `GlassPage` handles backdrop isolation automatically. If you were using
/// `GlassBackdropScope` manually, simply remove it.
@Deprecated(
  'Backdrop isolation is now handled automatically by GlassPage and individual '
  'glass layers. This widget is a no-op and can be safely removed. '
  'Deprecated in v0.14.0',
)
class GlassBackdropScope extends StatelessWidget {
  /// Creates a [GlassBackdropScope].
  ///
  /// This widget is now a no-op and returns its child directly.
  const GlassBackdropScope({
    super.key,
    required this.child,
  });

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // BackdropGroup is no longer used at the root level because Impeller
    // crashes when multiple RepaintBoundarys (LiquidGlassLayers) try to share
    // the same BackdropId.
    // Instead, each LiquidGlassLayer now creates its own isolated BackdropGroup.
    // This widget is retained as a no-op to avoid breaking user code.
    return child;
  }
}
