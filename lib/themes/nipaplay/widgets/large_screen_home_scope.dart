import 'package:flutter/widgets.dart';

class NipaplayLargeScreenHomeScope extends InheritedWidget {
  const NipaplayLargeScreenHomeScope({
    super.key,
    required super.child,
  });

  static bool isActive(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
            NipaplayLargeScreenHomeScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(covariant NipaplayLargeScreenHomeScope oldWidget) {
    return false;
  }
}
