import 'package:flutter/widgets.dart';

class NipaplayLargeScreenPlayerMenuScope extends InheritedWidget {
  const NipaplayLargeScreenPlayerMenuScope({
    super.key,
    required this.onMenuPressed,
    required super.child,
  });

  final VoidCallback onMenuPressed;

  static bool maybeHandleMenuPress(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<NipaplayLargeScreenPlayerMenuScope>();
    if (scope == null) {
      return false;
    }
    scope.onMenuPressed();
    return true;
  }

  @override
  bool updateShouldNotify(NipaplayLargeScreenPlayerMenuScope oldWidget) {
    return onMenuPressed != oldWidget.onMenuPressed;
  }
}
