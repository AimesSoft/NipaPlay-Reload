import 'package:flutter/widgets.dart';

/// Returns true when an iOS native platform view belongs to the active Flutter
/// route.
///
/// UIKit platform views are real native siblings of Flutter's raster overlay
/// views. When a Flutter modal route is pushed above a page, the underlying
/// native controls can otherwise remain visible or interactive. Checking route
/// visibility avoids guessing from Flutter engine overlay view bounds, which are
/// often full-screen transparent composition surfaces.
bool ios26NativeViewRouteIsCurrent(BuildContext context) {
  final route = ModalRoute.of(context);
  return route == null || route.isCurrent;
}
