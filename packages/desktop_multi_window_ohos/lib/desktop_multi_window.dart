import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

typedef DesktopWindowBuilder = Widget Function(
  BuildContext context,
  WindowController controller,
);

enum DesktopTransientWindowPlacement {
  above,
  below,
  right,
  pointer,
}

/// Flutter 3.35 compatibility facade used by the HarmonyOS build.
///
/// Same-engine desktop windows depend on private APIs introduced in Flutter
/// 3.44. The rest of the application already checks [DesktopMultiWindow.isSupported]
/// before creating one, so the older SDK can safely expose an unavailable
/// implementation while retaining the public types used by shared UI code.
void runDesktopMultiWindowApp(Widget app) => runApp(app);

class DesktopMultiWindowHost extends StatelessWidget {
  const DesktopMultiWindowHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class DesktopMultiWindow {
  DesktopMultiWindow._();

  static bool get isSupported => false;
  static bool get supportsInteractivePopupWindows => false;
  static bool get supportsTooltipWindows => false;

  static Future<WindowController> createWindow({
    required DesktopWindowBuilder builder,
    String? title,
    Size? size,
    Size? minimumSize,
    Size? maximumSize,
    bool decorated = true,
    bool frameless = false,
    double? aspectRatio,
    bool alwaysOnTop = false,
    VoidCallback? onClosed,
  }) {
    return Future<WindowController>.error(
      UnsupportedError(
        'Same-engine desktop windows require Flutter 3.44 or newer.',
      ),
    );
  }

  static WindowController? maybeControllerOf(BuildContext context) => null;

  static WindowController controllerOf(BuildContext context) {
    throw StateError('The context is not in a secondary window.');
  }

  static bool isSecondaryWindow(BuildContext context) => false;
  static WindowController? fromWindowId(int windowId) => null;
  static List<int> getAllSubWindowIds() => const <int>[];

  static void attachTransientView(Object owner, Widget view) {}
  static void detachTransientView(Object owner) {}

  static Widget inheritTransientViewContext(
    BuildContext sourceContext,
    Widget child,
  ) {
    return child;
  }

  static DesktopPopupWindowController? createPopupWindow({
    required BuildContext context,
    required Rect anchorRect,
    required Size size,
    DesktopTransientWindowPlacement placement =
        DesktopTransientWindowPlacement.above,
    double gap = 8.0,
    VoidCallback? onClosed,
  }) {
    return null;
  }

  static DesktopTooltipWindowController? createTooltipWindow({
    required BuildContext context,
    required Rect anchorRect,
    required Size size,
    DesktopTransientWindowPlacement placement =
        DesktopTransientWindowPlacement.above,
    double gap = 8.0,
    VoidCallback? onClosed,
  }) {
    return null;
  }
}

abstract class _UnavailableTransientWindowController {
  bool get isClosed => true;
  Future<void> get ready => Future<void>.value();

  FlutterView get flutterView {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      throw StateError('The platform did not provide a FlutterView.');
    }
    return views.first;
  }

  void close() {}

  void updatePosition({
    Rect? anchorRect,
    DesktopTransientWindowPlacement? placement,
    double gap = 8.0,
  }) {}
}

class DesktopPopupWindowController
    extends _UnavailableTransientWindowController {
  DesktopPopupWindowController._();
}

class DesktopTooltipWindowController
    extends _UnavailableTransientWindowController {
  DesktopTooltipWindowController._();
}

class DesktopPopupWindow extends StatelessWidget {
  const DesktopPopupWindow({
    super.key,
    required this.controller,
    required this.child,
  });

  final DesktopPopupWindowController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class DesktopTooltipWindow extends StatelessWidget {
  const DesktopTooltipWindow({
    super.key,
    required this.controller,
    required this.child,
  });

  final DesktopTooltipWindowController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class WindowController extends ChangeNotifier {
  WindowController._();

  final int windowId = -1;
  bool isClosed = true;
  bool isFullscreen = false;
  bool isMaximized = false;
  bool isMinimized = false;
  bool isActive = false;
  bool isAlwaysOnTop = false;
  double? aspectRatio;
  Size size = Size.zero;
  String title = '';

  FlutterView get flutterView {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      throw StateError('The platform did not provide a FlutterView.');
    }
    return views.first;
  }

  Future<void> close() async {}
  Future<void> show() async {}
  Future<void> hide() async {}

  Future<void> setSize(Size value) async {
    size = value;
    notifyListeners();
  }

  Future<void> setMinimumSize(Size value) async {}

  Future<void> setTitle(String value) async {
    title = value;
    notifyListeners();
  }

  Future<void> setFullscreen(bool value) async {
    isFullscreen = value;
    notifyListeners();
  }

  Future<void> setMaximized(bool value) async {
    isMaximized = value;
    notifyListeners();
  }

  Future<void> setMinimized(bool value) async {
    isMinimized = value;
    notifyListeners();
  }

  Future<void> startDragging() async {}
  Future<void> updateDragging() async {}
  Future<void> endDragging() async {}

  Future<void> setAspectRatio(double? value) async {
    aspectRatio = value;
    notifyListeners();
  }

  Future<void> setAlwaysOnTop(bool value) async {
    isAlwaysOnTop = value;
    notifyListeners();
  }

  Future<void> toggleAlwaysOnTop() => setAlwaysOnTop(!isAlwaysOnTop);

  Future<void> setPictureInPictureMode({
    required bool enabled,
    required double aspectRatio,
    required String placement,
    double margin = 16,
  }) async {}
}
