import 'package:flutter/widgets.dart';

class NipaplayLargeScreenModeScope extends InheritedWidget {
  const NipaplayLargeScreenModeScope({
    super.key,
    required this.isActive,
    required super.child,
  });

  final bool isActive;

  static bool isActiveOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<NipaplayLargeScreenModeScope>()
            ?.isActive ==
        true;
  }

  @override
  bool updateShouldNotify(covariant NipaplayLargeScreenModeScope oldWidget) {
    return isActive != oldWidget.isActive;
  }
}
