import 'package:flutter/material.dart';

import 'context_menu_widgets.dart';

class OverlayContextMenuController {
  OverlayEntry? _entry;

  bool get isShowing => _entry != null;

  void showActionsMenu({
    required BuildContext context,
    required Offset globalPosition,
    required ContextMenuStyle style,
    required List<ContextMenuAction> actions,
    double screenPadding = 12,
  }) {
    if (actions.isEmpty) {
      hide();
      return;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    hide();

    final renderBox = overlay.context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final Size overlaySize = renderBox.size;
    final Offset overlayPosition = renderBox.globalToLocal(globalPosition);

    final Size menuSize = style.menuSize(actions.length);

    double left = overlayPosition.dx;
    double top = overlayPosition.dy;

    final double maxLeftRaw = overlaySize.width - menuSize.width - screenPadding;
    final double maxTopRaw = overlaySize.height - menuSize.height - screenPadding;
    final double maxLeft = maxLeftRaw < screenPadding ? screenPadding : maxLeftRaw;
    final double maxTop = maxTopRaw < screenPadding ? screenPadding : maxTopRaw;

    left = left.clamp(screenPadding, maxLeft);
    top = top.clamp(screenPadding, maxTop);

    _entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: hide,
              onSecondaryTap: hide,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: ContextMenu(
              style: style,
              actions: actions,
              onDismiss: hide,
            ),
          ),
        ],
      ),
    );

    overlay.insert(_entry!);
  }

  void hide() {
    _entry?.remove();
    _entry = null;
  }

  void dispose() {
    hide();
  }
}
