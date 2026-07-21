// Flutter's same-engine desktop windowing API is internal in Flutter 3.44.
// This package is intentionally vendored with the app so both sides can be
// upgraded together when that API changes.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' as flutter_features;
import 'package:flutter/src/widgets/_window.dart' as flutter_windowing;
import 'package:flutter/src/widgets/_window_positioner.dart'
    as flutter_window_positioning;
import 'package:flutter/widgets.dart';

typedef DesktopWindowBuilder = Widget Function(
    BuildContext context, WindowController controller);

enum DesktopTransientWindowPlacement {
  above,
  below,
  right,
  pointer,
}

/// Boots the application into the real desktop FlutterView.
///
/// macOS keeps an implicit view 0 in Dart even after the embedder switches to
/// multiview mode. The native main window is a different, non-implicit view;
/// using runApp would render into view 0 and leave the actual window blank.
void runDesktopMultiWindowApp(Widget app) {
  if (!DesktopMultiWindow.isSupported) {
    runApp(app);
    return;
  }

  final binding = WidgetsFlutterBinding.ensureInitialized();
  final dispatcher = binding.platformDispatcher;
  final views = dispatcher.views.toList(growable: false);
  if (views.isEmpty) {
    throw StateError('The desktop embedder did not provide a FlutterView.');
  }

  final implicitView = dispatcher.implicitView;
  final explicitViews = implicitView == null
      ? views
      : views
          .where((view) => view.viewId != implicitView.viewId)
          .toList(growable: false);
  final mainView = _largestView(
    explicitViews.isNotEmpty ? explicitViews : views,
  );

  debugPrint(
    '[DesktopMultiWindow] main FlutterView=${mainView.viewId}, '
    'implicit=${implicitView?.viewId}, '
    'views=${views.map((view) => '${view.viewId}:${view.physicalSize}').join(', ')}',
  );
  runWidget(View(view: mainView, child: app));
}

FlutterView _largestView(List<FlutterView> views) {
  return views.reduce((current, candidate) {
    final currentArea =
        current.physicalSize.width * current.physicalSize.height;
    final candidateArea =
        candidate.physicalSize.width * candidate.physicalSize.height;
    return candidateArea > currentArea ? candidate : current;
  });
}

/// Anchors all secondary [FlutterView]s to the main widget tree.
///
/// Put this below application-wide providers and above the main app so the
/// secondary view inherits the exact same provider instances.
class DesktopMultiWindowHost extends StatelessWidget {
  const DesktopMultiWindowHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DesktopMultiWindow._registry,
      child: child,
      builder: (context, mainView) {
        final windows = DesktopMultiWindow._registry.windows;
        return ViewAnchor(
          view: windows.isEmpty
              ? null
              : ViewCollection(
                  views: windows
                      .map(
                        (entry) => _SecondaryWindowScope(
                          controller: entry.controller,
                          child: View(
                            view: entry.controller.flutterView,
                            child: _PositiveViewSizeGate(
                              child: Builder(
                                builder: (context) =>
                                    entry.builder(context, entry.controller),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
          child: _PositiveViewSizeGate(child: mainView!),
        );
      },
    );
  }
}

/// A newly-added FlutterView reports zero metrics for its first engine frame.
/// Give application content a harmless bootstrap layout so that frame can be
/// produced and native resize synchronization can advance to real metrics.
class _PositiveViewSizeGate extends StatelessWidget {
  const _PositiveViewSizeGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return OverflowBox(
            minWidth: 800,
            maxWidth: 800,
            minHeight: 600,
            maxHeight: 600,
            child: child,
          );
        }
        return child;
      },
    );
  }
}

class DesktopMultiWindow {
  DesktopMultiWindow._();

  static const MethodChannel _hostChannel = MethodChannel(
    'nipaplay/desktop_multi_window_host',
  );
  static final _DesktopWindowRegistry _registry = _DesktopWindowRegistry();
  static int _nextWindowId = 1;

  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Flutter 3.44 currently implements interactive popup windows on macOS.
  static bool get supportsInteractivePopupWindows =>
      isSupported && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get supportsTooltipWindows => isSupported;

  /// Creates a regular native window backed by a new [FlutterView] in the
  /// current engine and isolate.
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
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'Same-engine desktop windows are only supported on macOS, Windows, '
        'and Linux.',
      );
    }

    final binding = WidgetsFlutterBinding.ensureInitialized();
    final previousFeatureState = flutter_features.isWindowingEnabled;
    flutter_features.isWindowingEnabled = true;

    final delegate = _SameEngineWindowDelegate();
    late final flutter_windowing.RegularWindowController nativeController;
    try {
      // Stable Flutter 3.44 ships the windowing implementation but keeps its
      // feature flag reserved for the main channel. Reinstall the real owner
      // while the flag is enabled, then keep window creation contained here.
      binding.windowingOwner = flutter_windowing.createDefaultWindowingOwner();
      nativeController = flutter_windowing.RegularWindowController(
        preferredSize: size,
        preferredConstraints: _constraintsFor(
          minimumSize: minimumSize,
          maximumSize: maximumSize,
        ),
        title: title,
        // Flutter 3.44 throws for `decorated: false` on macOS and Windows.
        // Create a normal host first, then let the vendored native host turn
        // only this secondary window into a resizable frameless window.
        decorated: frameless ? true : decorated,
        delegate: delegate,
      );
    } finally {
      flutter_features.isWindowingEnabled = previousFeatureState;
    }

    final controller = WindowController._(
      windowId: _nextWindowId++,
      nativeController: nativeController,
      onClosed: onClosed,
    );
    delegate.attach(controller);
    _registry.add(
      _DesktopWindowEntry(controller: controller, builder: builder),
    );

    if (frameless || aspectRatio != null || alwaysOnTop) {
      await controller._configureHostWindow(
        frameless: frameless,
        aspectRatio: aspectRatio,
        alwaysOnTop: alwaysOnTop,
        preferredSize: size,
      );
    }

    // The platform window exists as soon as the native controller is created.
    // Wait for its View widget to attach before focusing it.
    await WidgetsBinding.instance.endOfFrame;
    if (!controller.isClosed) {
      controller.show();
    }
    return controller;
  }

  static WindowController? maybeControllerOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<_SecondaryWindowScope>()
        ?.controller;
  }

  static WindowController controllerOf(BuildContext context) {
    final controller = maybeControllerOf(context);
    assert(controller != null, 'The context is not in a secondary window.');
    return controller!;
  }

  static bool isSecondaryWindow(BuildContext context) {
    return maybeControllerOf(context) != null;
  }

  static WindowController? fromWindowId(int windowId) {
    return _registry.byId(windowId)?.controller;
  }

  static List<int> getAllSubWindowIds() {
    return _registry.windows
        .map((entry) => entry.controller.windowId)
        .toList(growable: false);
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
    if (!supportsInteractivePopupWindows) return null;
    final parent = maybeControllerOf(context);
    if (parent == null || parent.isClosed) return null;

    final delegate = _SameEnginePopupWindowDelegate();
    try {
      final nativeController = _withWindowingEnabled(
        () => flutter_windowing.PopupWindowController(
          parent: parent._nativeController,
          anchorRect: anchorRect,
          positioner: _positionerFor(placement, gap),
          preferredConstraints: BoxConstraints.tight(size),
          delegate: delegate,
        ),
      );
      final controller = DesktopPopupWindowController._(
        nativeController: nativeController,
        onClosed: onClosed,
      );
      delegate.attach(controller);
      unawaited(_invokeHostForViewId<void>(
        'configureTransientWindow',
        controller.flutterView.viewId,
        const <String, Object?>{'interactive': true},
      ));
      return controller;
    } on UnimplementedError catch (error) {
      debugPrint('[DesktopMultiWindow] popup windows unimplemented: $error');
      return null;
    } on UnsupportedError catch (error) {
      debugPrint('[DesktopMultiWindow] popup windows unsupported: $error');
      return null;
    }
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
    if (!supportsTooltipWindows) return null;
    final parent = maybeControllerOf(context);
    if (parent == null || parent.isClosed) return null;

    final delegate = _SameEngineTooltipWindowDelegate();
    try {
      final nativeController = _withWindowingEnabled(
        () => flutter_windowing.TooltipWindowController(
          parent: parent._nativeController,
          anchorRect: anchorRect,
          positioner: _positionerFor(placement, gap),
          preferredConstraints: BoxConstraints.tight(size),
          delegate: delegate,
        ),
      );
      final controller = DesktopTooltipWindowController._(
        nativeController: nativeController,
        onClosed: onClosed,
      );
      delegate.attach(controller);
      return controller;
    } on UnimplementedError catch (error) {
      debugPrint('[DesktopMultiWindow] tooltip windows unimplemented: $error');
      return null;
    } on UnsupportedError catch (error) {
      debugPrint('[DesktopMultiWindow] tooltip windows unsupported: $error');
      return null;
    }
  }

  static BoxConstraints? _constraintsFor({
    Size? minimumSize,
    Size? maximumSize,
  }) {
    if (minimumSize == null && maximumSize == null) return null;
    return BoxConstraints(
      minWidth: minimumSize?.width ?? 0,
      minHeight: minimumSize?.height ?? 0,
      maxWidth: maximumSize?.width ?? double.infinity,
      maxHeight: maximumSize?.height ?? double.infinity,
    );
  }

  static void _remove(WindowController controller) {
    _registry.remove(controller.windowId);
  }

  static Future<T?> _invokeHost<T>(
    String method,
    WindowController controller, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    return _invokeHostForViewId<T>(
      method,
      controller.flutterView.viewId,
      arguments,
    );
  }

  static Future<T?> _invokeHostForViewId<T>(
    String method,
    int viewId, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    try {
      return await _hostChannel.invokeMethod<T>(method, <String, Object?>{
        'viewId': viewId,
        ...arguments,
      });
    } on MissingPluginException catch (error) {
      debugPrint('[DesktopMultiWindow] native host unavailable: $error');
      return null;
    } on PlatformException catch (error) {
      debugPrint(
        '[DesktopMultiWindow] native host $method failed: '
        '${error.code} ${error.message}',
      );
      return null;
    }
  }

  static T _withWindowingEnabled<T>(T Function() action) {
    final previousFeatureState = flutter_features.isWindowingEnabled;
    flutter_features.isWindowingEnabled = true;
    try {
      return action();
    } finally {
      flutter_features.isWindowingEnabled = previousFeatureState;
    }
  }

  static flutter_window_positioning.WindowPositioner _positionerFor(
    DesktopTransientWindowPlacement placement,
    double gap,
  ) {
    final adjustment =
        flutter_window_positioning.WindowPositionerConstraintAdjustment(
      flipX: placement != DesktopTransientWindowPlacement.pointer,
      flipY: placement != DesktopTransientWindowPlacement.pointer,
      slideX: true,
      slideY: true,
      resizeX: true,
      resizeY: true,
    );
    return switch (placement) {
      DesktopTransientWindowPlacement.above =>
        flutter_window_positioning.WindowPositioner(
          parentAnchor: flutter_window_positioning.WindowPositionerAnchor.top,
          childAnchor: flutter_window_positioning.WindowPositionerAnchor.bottom,
          offset: Offset(0, -gap),
          constraintAdjustment: adjustment,
        ),
      DesktopTransientWindowPlacement.below =>
        flutter_window_positioning.WindowPositioner(
          parentAnchor:
              flutter_window_positioning.WindowPositionerAnchor.bottom,
          childAnchor: flutter_window_positioning.WindowPositionerAnchor.top,
          offset: Offset(0, gap),
          constraintAdjustment: adjustment,
        ),
      DesktopTransientWindowPlacement.right =>
        flutter_window_positioning.WindowPositioner(
          parentAnchor: flutter_window_positioning.WindowPositionerAnchor.right,
          childAnchor: flutter_window_positioning.WindowPositionerAnchor.left,
          offset: Offset(gap, 0),
          constraintAdjustment: adjustment,
        ),
      DesktopTransientWindowPlacement.pointer =>
        flutter_window_positioning.WindowPositioner(
          parentAnchor:
              flutter_window_positioning.WindowPositionerAnchor.topLeft,
          childAnchor:
              flutter_window_positioning.WindowPositionerAnchor.topLeft,
          offset: Offset(gap, gap),
          constraintAdjustment: adjustment,
        ),
    };
  }
}

class DesktopPopupWindowController {
  DesktopPopupWindowController._({
    required flutter_windowing.PopupWindowController nativeController,
    VoidCallback? onClosed,
  })  : _nativeController = nativeController,
        _onClosed = onClosed;

  final flutter_windowing.PopupWindowController _nativeController;
  final VoidCallback? _onClosed;
  bool _isClosed = false;

  FlutterView get flutterView => _nativeController.rootView;
  bool get isClosed => _isClosed;

  void close() {
    if (_isClosed) return;
    _nativeController.destroy();
  }

  void updatePosition({
    Rect? anchorRect,
    DesktopTransientWindowPlacement? placement,
    double gap = 8.0,
  }) {
    if (_isClosed) return;
    _nativeController.updatePosition(
      anchorRect: anchorRect,
      positioner: placement == null
          ? null
          : DesktopMultiWindow._positionerFor(placement, gap),
    );
  }

  void _handleNativeDestroyed() {
    if (_isClosed) return;
    _isClosed = true;
    _onClosed?.call();
  }
}

class DesktopTooltipWindowController {
  DesktopTooltipWindowController._({
    required flutter_windowing.TooltipWindowController nativeController,
    VoidCallback? onClosed,
  })  : _nativeController = nativeController,
        _onClosed = onClosed;

  final flutter_windowing.TooltipWindowController _nativeController;
  final VoidCallback? _onClosed;
  bool _isClosed = false;

  FlutterView get flutterView => _nativeController.rootView;
  bool get isClosed => _isClosed;

  void close() {
    if (_isClosed) return;
    _nativeController.destroy();
  }

  void updatePosition({
    Rect? anchorRect,
    DesktopTransientWindowPlacement? placement,
    double gap = 8.0,
  }) {
    if (_isClosed) return;
    _nativeController.updatePosition(
      anchorRect: anchorRect,
      positioner: placement == null
          ? null
          : DesktopMultiWindow._positionerFor(placement, gap),
    );
  }

  void _handleNativeDestroyed() {
    if (_isClosed) return;
    _isClosed = true;
    _onClosed?.call();
  }
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
  Widget build(BuildContext context) {
    return DesktopMultiWindow._withWindowingEnabled(
      () => flutter_windowing.PopupWindow(
        controller: controller._nativeController,
        child: child,
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return DesktopMultiWindow._withWindowingEnabled(
      () => flutter_windowing.TooltipWindow(
        controller: controller._nativeController,
        child: child,
      ),
    );
  }
}

class WindowController extends ChangeNotifier {
  WindowController._({
    required this.windowId,
    required flutter_windowing.RegularWindowController nativeController,
    VoidCallback? onClosed,
  })  : _nativeController = nativeController,
        _onClosed = onClosed {
    _nativeController.addListener(_forwardNativeChange);
  }

  final int windowId;
  final flutter_windowing.RegularWindowController _nativeController;
  final VoidCallback? _onClosed;
  bool _isClosed = false;
  bool _closedCallbackSent = false;
  bool _isAlwaysOnTop = false;
  double? _aspectRatio;

  FlutterView get flutterView => _nativeController.rootView;
  bool get isClosed => _isClosed;
  bool get isFullscreen => !_isClosed && _nativeController.isFullscreen;
  bool get isMaximized => !_isClosed && _nativeController.isMaximized;
  bool get isMinimized => !_isClosed && _nativeController.isMinimized;
  bool get isActive => !_isClosed && _nativeController.isActivated;
  bool get isAlwaysOnTop => !_isClosed && _isAlwaysOnTop;
  double? get aspectRatio => _aspectRatio;
  Size get size => _nativeController.contentSize;
  String get title => _nativeController.title;

  Future<void> close() async {
    if (_isClosed) return;
    _nativeController.destroy();
  }

  Future<void> show() async {
    if (_isClosed) return;
    _nativeController.activate();
  }

  Future<void> hide() async {
    if (_isClosed) return;
    _nativeController.setMinimized(true);
  }

  Future<void> setSize(Size size) async {
    if (_isClosed) return;
    _nativeController.setSize(size);
  }

  Future<void> setMinimumSize(Size size) async {
    if (_isClosed) return;
    _nativeController.setConstraints(
      BoxConstraints(minWidth: size.width, minHeight: size.height),
    );
  }

  Future<void> setTitle(String title) async {
    if (_isClosed) return;
    _nativeController.setTitle(title);
  }

  Future<void> setFullscreen(bool fullscreen) async {
    if (_isClosed) return;
    _nativeController.setFullscreen(fullscreen);
  }

  Future<void> setMaximized(bool maximized) async {
    if (_isClosed) return;
    _nativeController.setMaximized(maximized);
  }

  Future<void> setMinimized(bool minimized) async {
    if (_isClosed) return;
    _nativeController.setMinimized(minimized);
  }

  /// Starts the platform's normal interactive window move operation.
  ///
  /// Call this directly from a pointer-down callback so AppKit/Win32/GTK can
  /// reuse the current mouse event.
  Future<void> startDragging() async {
    if (_isClosed) return;
    await DesktopMultiWindow._invokeHost<void>('startDragging', this);
  }

  Future<void> updateDragging() async {
    if (_isClosed) return;
    await DesktopMultiWindow._invokeHost<void>('updateDragging', this);
  }

  Future<void> endDragging() async {
    if (_isClosed) return;
    await DesktopMultiWindow._invokeHost<void>('endDragging', this);
  }

  Future<void> setAspectRatio(double? aspectRatio) async {
    if (_isClosed) return;
    final normalized =
        aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0
            ? aspectRatio
            : null;
    _aspectRatio = normalized;
    await DesktopMultiWindow._invokeHost<void>(
      'setAspectRatio',
      this,
      <String, Object?>{'aspectRatio': normalized},
    );
    notifyListeners();
  }

  Future<void> setAlwaysOnTop(bool alwaysOnTop) async {
    if (_isClosed) return;
    final applied = await DesktopMultiWindow._invokeHost<bool>(
      'setAlwaysOnTop',
      this,
      <String, Object?>{'alwaysOnTop': alwaysOnTop},
    );
    _isAlwaysOnTop = applied ?? alwaysOnTop;
    notifyListeners();
  }

  Future<void> toggleAlwaysOnTop() => setAlwaysOnTop(!isAlwaysOnTop);

  Future<void> _configureHostWindow({
    required bool frameless,
    required double? aspectRatio,
    required bool alwaysOnTop,
    required Size? preferredSize,
  }) async {
    _aspectRatio = aspectRatio;
    final preferredContentSize = preferredSize ?? size;
    final applied = await DesktopMultiWindow._invokeHost<bool>(
      'configureWindow',
      this,
      <String, Object?>{
        'frameless': frameless,
        'aspectRatio': aspectRatio,
        'alwaysOnTop': alwaysOnTop,
        'width': preferredContentSize.width,
        'height': preferredContentSize.height,
      },
    );
    _isAlwaysOnTop = applied ?? alwaysOnTop;
    notifyListeners();
  }

  void _forwardNativeChange() {
    if (!_isClosed) notifyListeners();
  }

  void _handleNativeDestroyed() {
    if (_isClosed) return;
    _isClosed = true;
    _nativeController.removeListener(_forwardNativeChange);
    DesktopMultiWindow._remove(this);
    notifyListeners();
    if (!_closedCallbackSent) {
      _closedCallbackSent = true;
      _onClosed?.call();
    }
  }

  @override
  void dispose() {
    _nativeController.removeListener(_forwardNativeChange);
    super.dispose();
  }
}

class _SameEngineWindowDelegate
    with flutter_windowing.RegularWindowControllerDelegate {
  WindowController? _controller;

  void attach(WindowController controller) {
    _controller = controller;
  }

  @override
  void onWindowCloseRequested(
    flutter_windowing.RegularWindowController controller,
  ) {
    controller.destroy();
  }

  @override
  void onWindowDestroyed() {
    _controller?._handleNativeDestroyed();
  }
}

class _SameEnginePopupWindowDelegate
    with flutter_windowing.PopupWindowControllerDelegate {
  DesktopPopupWindowController? _controller;

  void attach(DesktopPopupWindowController controller) {
    _controller = controller;
  }

  @override
  void onWindowDestroyed() {
    _controller?._handleNativeDestroyed();
  }
}

class _SameEngineTooltipWindowDelegate
    with flutter_windowing.TooltipWindowControllerDelegate {
  DesktopTooltipWindowController? _controller;

  void attach(DesktopTooltipWindowController controller) {
    _controller = controller;
  }

  @override
  void onWindowDestroyed() {
    _controller?._handleNativeDestroyed();
  }
}

class _DesktopWindowEntry {
  const _DesktopWindowEntry({required this.controller, required this.builder});

  final WindowController controller;
  final DesktopWindowBuilder builder;
}

class _DesktopWindowRegistry extends ChangeNotifier {
  final List<_DesktopWindowEntry> _windows = <_DesktopWindowEntry>[];

  List<_DesktopWindowEntry> get windows =>
      List<_DesktopWindowEntry>.unmodifiable(_windows);

  void add(_DesktopWindowEntry entry) {
    _windows.add(entry);
    notifyListeners();
  }

  void remove(int windowId) {
    final oldLength = _windows.length;
    _windows.removeWhere((entry) => entry.controller.windowId == windowId);
    if (_windows.length != oldLength) notifyListeners();
  }

  _DesktopWindowEntry? byId(int windowId) {
    for (final entry in _windows) {
      if (entry.controller.windowId == windowId) return entry;
    }
    return null;
  }
}

class _SecondaryWindowScope extends InheritedWidget {
  const _SecondaryWindowScope({required this.controller, required super.child});

  final WindowController controller;

  @override
  bool updateShouldNotify(_SecondaryWindowScope oldWidget) {
    return controller != oldWidget.controller;
  }
}
