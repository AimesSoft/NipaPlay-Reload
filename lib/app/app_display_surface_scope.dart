import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_display_surface.dart';

class AppDisplaySurfaceScope extends InheritedWidget {
  const AppDisplaySurfaceScope({
    super.key,
    required this.surface,
    required super.child,
  });

  final AppDisplaySurface surface;

  static AppDisplaySurface of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AppDisplaySurfaceScope>()
            ?.surface ??
        AppDisplaySurface.desktopTablet;
  }

  @override
  bool updateShouldNotify(AppDisplaySurfaceScope oldWidget) {
    return surface != oldWidget.surface;
  }
}
