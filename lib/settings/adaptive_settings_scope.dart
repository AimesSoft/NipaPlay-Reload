import 'package:flutter/widgets.dart';

enum AdaptiveSettingsStyle {
  nipaplay,
  cupertino,
}

class AdaptiveSettingsScope extends InheritedWidget {
  const AdaptiveSettingsScope({
    super.key,
    required this.style,
    required super.child,
  });

  final AdaptiveSettingsStyle style;

  static AdaptiveSettingsStyle styleOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AdaptiveSettingsScope>()
            ?.style ??
        AdaptiveSettingsStyle.nipaplay;
  }

  static bool isCupertino(BuildContext context) {
    return styleOf(context) == AdaptiveSettingsStyle.cupertino;
  }

  @override
  bool updateShouldNotify(AdaptiveSettingsScope oldWidget) {
    return style != oldWidget.style;
  }
}
