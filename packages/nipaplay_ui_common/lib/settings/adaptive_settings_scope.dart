import 'package:flutter/widgets.dart';

enum AdaptiveSettingsStyle {
  desktopTablet,
  phone,
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
        AdaptiveSettingsStyle.desktopTablet;
  }

  static bool isPhoneLayout(BuildContext context) {
    return styleOf(context) == AdaptiveSettingsStyle.phone;
  }

  @override
  bool updateShouldNotify(AdaptiveSettingsScope oldWidget) {
    return style != oldWidget.style;
  }
}
