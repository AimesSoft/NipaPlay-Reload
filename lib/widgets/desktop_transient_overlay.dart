import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

typedef DesktopPopupContentBuilder = Widget Function(
  BuildContext context,
  VoidCallback close,
);

/// Hosts a same-engine native popup from an Overlay without inserting its
/// secondary RenderView into the parent window's render tree.
class DesktopTransientOverlay {
  DesktopTransientOverlay._({
    required DesktopPopupWindowController controller,
    required OverlayState overlay,
    required DesktopPopupContentBuilder contentBuilder,
    required bool barrierDismissible,
    VoidCallback? onClosed,
  })  : _controller = controller,
        _overlay = overlay,
        _contentBuilder = contentBuilder,
        _barrierDismissible = barrierDismissible,
        _onClosed = onClosed;

  final DesktopPopupWindowController _controller;
  final OverlayState _overlay;
  final DesktopPopupContentBuilder _contentBuilder;
  final bool _barrierDismissible;
  final VoidCallback? _onClosed;
  OverlayEntry? _entry;
  bool _closed = false;

  static DesktopTransientOverlay? showPopup({
    required BuildContext context,
    required Rect anchorRect,
    required Size size,
    required DesktopPopupContentBuilder contentBuilder,
    DesktopTransientWindowPlacement placement =
        DesktopTransientWindowPlacement.above,
    double gap = 8.0,
    bool barrierDismissible = true,
    VoidCallback? onClosed,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return null;

    late DesktopTransientOverlay surface;
    final controller = DesktopMultiWindow.createPopupWindow(
      context: context,
      anchorRect: anchorRect,
      size: size,
      placement: placement,
      gap: gap,
      onClosed: () => surface._handleNativeClosed(),
    );
    if (controller == null) return null;

    surface = DesktopTransientOverlay._(
      controller: controller,
      overlay: overlay,
      contentBuilder: contentBuilder,
      barrierDismissible: barrierDismissible,
      onClosed: onClosed,
    );
    surface._insert();
    return surface;
  }

  bool get isClosed => _closed;

  void _insert() {
    _entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: ViewAnchor(
          view: DesktopPopupWindow(
            controller: _controller,
            child: _contentBuilder(context, close),
          ),
          child: _barrierDismissible
              ? GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: close,
                  onSecondaryTap: close,
                  child: const ColoredBox(color: Colors.transparent),
                )
              : const IgnorePointer(child: SizedBox.expand()),
        ),
      ),
    );
    _overlay.insert(_entry!);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _entry?.remove();
    _entry = null;
    _controller.close();
    _onClosed?.call();
  }

  void _handleNativeClosed() {
    if (_closed) return;
    _closed = true;
    _entry?.remove();
    _entry = null;
    _onClosed?.call();
  }
}
