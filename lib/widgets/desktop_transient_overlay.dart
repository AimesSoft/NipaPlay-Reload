import 'dart:async';

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
    required BuildContext sourceContext,
    required DesktopPopupContentBuilder contentBuilder,
    required bool barrierDismissible,
    VoidCallback? onClosed,
  })  : _controller = controller,
        _overlay = overlay,
        _sourceContext = sourceContext,
        _contentBuilder = contentBuilder,
        _barrierDismissible = barrierDismissible,
        _onClosed = onClosed;

  final DesktopPopupWindowController _controller;
  final OverlayState _overlay;
  final BuildContext _sourceContext;
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
      sourceContext: context,
      contentBuilder: contentBuilder,
      barrierDismissible: barrierDismissible,
      onClosed: onClosed,
    );
    surface._insert();
    return surface;
  }

  bool get isClosed => _closed;

  void _insert() {
    unawaited(_insertWhenReady());
  }

  Future<void> _insertWhenReady() async {
    await _controller.ready;
    if (_closed) return;
    debugPrint(
      '[DesktopTransientOverlay] mount popup '
      'view=${_controller.flutterView.viewId} '
      'physicalSize='
      '${_controller.flutterView.physicalSize.width.toStringAsFixed(1)}x'
      '${_controller.flutterView.physicalSize.height.toStringAsFixed(1)}',
    );
    DesktopMultiWindow.attachTransientView(
      this,
      DesktopPopupWindow(
        controller: _controller,
        child: DesktopMultiWindow.inheritTransientViewContext(
          _sourceContext,
          _contentBuilder(_sourceContext, close),
        ),
      ),
    );
    if (_barrierDismissible) {
      _entry = OverlayEntry(
        builder: (context) => Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: close,
            onSecondaryTap: close,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
      );
      _overlay.insert(_entry!);
    }
  }

  void close() {
    if (_closed) return;
    debugPrint(
      '[DesktopTransientOverlay] close popup '
      'view=${_controller.flutterView.viewId}',
    );
    _closed = true;
    DesktopMultiWindow.detachTransientView(this);
    _entry?.remove();
    _entry = null;
    _controller.close();
    _onClosed?.call();
  }

  void _handleNativeClosed() {
    if (_closed) return;
    debugPrint(
      '[DesktopTransientOverlay] native closed popup '
      'view=${_controller.flutterView.viewId}',
    );
    _closed = true;
    DesktopMultiWindow.detachTransientView(this);
    _entry?.remove();
    _entry = null;
    _onClosed?.call();
  }
}
