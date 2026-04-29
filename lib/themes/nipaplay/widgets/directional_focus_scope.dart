import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef NipaplayFocusBoundaryCallback = void Function(
    TraversalDirection direction);

class NipaplayDirectionalFocusScope extends StatelessWidget {
  const NipaplayDirectionalFocusScope({
    super.key,
    required this.child,
    this.onBoundaryReached,
  });

  final Widget child;
  final NipaplayFocusBoundaryCallback? onBoundaryReached;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowUp):
            DirectionalFocusIntent(TraversalDirection.up),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            DirectionalFocusIntent(TraversalDirection.down),
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            DirectionalFocusIntent(TraversalDirection.left),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            DirectionalFocusIntent(TraversalDirection.right),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
            onInvoke: (intent) {
              final primaryFocus = FocusManager.instance.primaryFocus;
              bool moved = false;
              if (primaryFocus != null) {
                moved = primaryFocus.focusInDirection(intent.direction);
              } else {
                moved = FocusScope.of(context).nextFocus();
              }
              if (!moved &&
                  (intent.direction == TraversalDirection.up ||
                      intent.direction == TraversalDirection.down)) {
                onBoundaryReached?.call(intent.direction);
              }
              return null;
            },
          ),
        },
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: FocusScope(
            autofocus: true,
            child: child,
          ),
        ),
      ),
    );
  }
}
