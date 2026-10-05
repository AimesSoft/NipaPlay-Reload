import 'package:flutter/widgets.dart';

/// Lets content dismiss its native popup and parent-view input barrier before
/// presenting a route on the parent navigator.
class DesktopTransientOverlayScope extends InheritedWidget {
  const DesktopTransientOverlayScope({
    super.key,
    required this.close,
    required super.child,
  });

  final VoidCallback close;

  static VoidCallback? closeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<DesktopTransientOverlayScope>()
      ?.close;

  @override
  bool updateShouldNotify(DesktopTransientOverlayScope oldWidget) =>
      close != oldWidget.close;
}
