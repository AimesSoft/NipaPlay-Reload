import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KeyboardActivatable extends StatelessWidget {
  final Widget child;
  final VoidCallback onActivate;
  final ValueChanged<bool>? onFocusChange;
  final bool enabled;
  final MouseCursor mouseCursor;

  const KeyboardActivatable({
    super.key,
    required this.child,
    required this.onActivate,
    this.onFocusChange,
    this.enabled = true,
    this.mouseCursor = SystemMouseCursors.click,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: mouseCursor,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (enabled) {
              onActivate();
            }
            return null;
          },
        ),
      },
      onShowFocusHighlight: onFocusChange,
      child: child,
    );
  }
}
