import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NipaplayDirectionalFocusScope extends StatelessWidget {
  const NipaplayDirectionalFocusScope({
    super.key,
    required this.child,
  });

  final Widget child;

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
              if (primaryFocus != null) {
                primaryFocus.focusInDirection(intent.direction);
              } else {
                FocusScope.of(context).nextFocus();
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
