import 'package:flutter/widgets.dart';

/// Marks the detached player subtree while it is using the compact
/// picture-in-picture chrome.
class DesktopPictureInPictureScope extends InheritedWidget {
  const DesktopPictureInPictureScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool isEnabledOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<DesktopPictureInPictureScope>()
            ?.enabled ??
        false;
  }

  @override
  bool updateShouldNotify(DesktopPictureInPictureScope oldWidget) {
    return enabled != oldWidget.enabled;
  }
}
