// Flutter's same-engine desktop windowing API remains internal in Flutter
// 3.47. This Linux-only package is vendored with the app so both sides can be
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
  BuildContext context,
  WindowController controller,
);

enum DesktopTransientWindowPlacement { above, below, right, pointer }

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

  // WindowScope, PopupWindow, and TooltipWindow check this flag again when
  // their widgets build, not only when their native controllers are created.
  // Keep it enabled for the lifetime of this deliberately multi-view app.
  flutter_features.isWindowingEnabled = true;
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.windowingOwner = flutter_windowing.createDefaultWindowingOwner();
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
        final transientViews = DesktopMultiWindow._registry.transientViews;
        return ViewAnchor(
          view: windows.isEmpty && transientViews.isEmpty
              ? null
              : ViewCollection(
                  views: <Widget>[
                    ...windows.map(
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
                    ),
                    ...transientViews,
                  ],
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

  /// Disabled for NipaPlay's detached player.
  ///
  /// Flutter creates the native popup/tooltip window, but its FlutterView
  /// remains at 0x0 even after AppKit applies a positive content size. Rendering
  /// therefore never starts. Callers deliberately fall back to their existing
  /// in-window Overlay implementations until Flutter's windowing API is stable.
  static bool get supportsInteractivePopupWindows => false;

  static bool get supportsTooltipWindows => false;

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
      // Flutter keeps the windowing feature flag reserved for the main channel.
      // Reinstall the real owner while the flag is enabled, then keep window
      // creation contained here.
      binding.windowingOwner = flutter_windowing.createDefaultWindowingOwner();
      // Flutter 3.47 renamed preferredSize/preferredConstraints to
      // size/constraints and dropped `decorated` (framing is configured via
      // the vendored native host afterwards, as before).
      nativeController = flutter_windowing.RegularWindowController(
        // 3.47 requires a non-null size; 1280x720 matches the detached
        // player's default content size when callers pass none.
        size: size ?? const Size(1280, 720),
        constraints: _constraintsFor(
          minimumSize: minimumSize,
          maximumSize: maximumSize,
        ),
        title: title,
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

  /// Mounts a popup or tooltip View beside regular secondary windows.
  ///
  /// Flutter Views must be siblings in the root [ViewCollection]. Nesting a
  /// popup View inside the detached player's View prevents it from rendering,
  /// while mounting it in an Overlay causes the Overlay slot-type crash.
  static void attachTransientView(Object owner, Widget view) {
    _registry.attachTransientView(owner, view);
  }

  static void detachTransientView(Object owner) {
    _registry.detachTransientView(owner);
  }

  /// Copies the app-level inherited presentation context into a root-level
  /// transient View.
  ///
  /// The root [ViewCollection] sits above MaterialApp, so popup children do not
  /// otherwise inherit Directionality, MediaQuery, Localizations, or themes
  /// from the detached player's route.
  static Widget inheritTransientViewContext(
    BuildContext sourceContext,
    Widget child,
  ) {
    Widget result = InheritedTheme.captureAll(sourceContext, child);
    result = Localizations.override(context: sourceContext, child: result);
    result = Directionality(
      textDirection: Directionality.of(sourceContext),
      child: result,
    );
    final mediaQuery = MediaQuery.maybeOf(sourceContext);
    if (mediaQuery != null) {
      result = MediaQuery(data: mediaQuery, child: result);
    }
    return result;
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

    debugPrint(
      '[DesktopMultiWindow][Popup] create '
      'parentView=${parent.flutterView.viewId} '
      'anchor=${_describeRect(anchorRect)} size=${_describeSize(size)} '
      'placement=$placement gap=$gap',
    );

    final delegate = _SameEnginePopupWindowDelegate();
    try {
      final nativeController = _withWindowingEnabled(
        () => flutter_windowing.PopupWindowController(
          parent: parent._nativeController,
          anchorRect: anchorRect,
          positioner: _positionerFor(placement, gap),
          constraints: BoxConstraints.tight(size),
          delegate: delegate,
        ),
      );
      final controller = DesktopPopupWindowController._(
        nativeController: nativeController,
        onClosed: onClosed,
      );
      delegate.attach(controller);
      debugPrint(
        '[DesktopMultiWindow][Popup] native-created '
        'view=${controller.flutterView.viewId} '
        'physicalSize=${_describeSize(controller.flutterView.physicalSize)}',
      );
      unawaited(() async {
        await _invokeHostForViewId<void>(
          'configureTransientWindow',
          controller.flutterView.viewId,
          <String, Object?>{
            'interactive': true,
            'width': size.width,
            'height': size.height,
          },
        );
        await _waitForPositiveViewMetrics(
          kind: 'Popup',
          view: controller.flutterView,
        );
        debugPrint(
          '[DesktopMultiWindow][Popup] native-configured '
          'view=${controller.flutterView.viewId} closed=${controller.isClosed} '
          'physicalSize=${_describeSize(controller.flutterView.physicalSize)}',
        );
        if (!controller.isClosed) controller.updatePosition();
        controller._markReady();
      }());
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

    debugPrint(
      '[DesktopMultiWindow][Tooltip] create '
      'parentView=${parent.flutterView.viewId} '
      'anchor=${_describeRect(anchorRect)} size=${_describeSize(size)} '
      'placement=$placement gap=$gap',
    );

    final delegate = _SameEngineTooltipWindowDelegate();
    try {
      final nativeController = _withWindowingEnabled(
        () => flutter_windowing.TooltipWindowController(
          parent: parent._nativeController,
          anchorRect: anchorRect,
          positioner: _positionerFor(placement, gap),
          constraints: BoxConstraints.tight(size),
          delegate: delegate,
        ),
      );
      final controller = DesktopTooltipWindowController._(
        nativeController: nativeController,
        onClosed: onClosed,
      );
      delegate.attach(controller);
      debugPrint(
        '[DesktopMultiWindow][Tooltip] native-created '
        'view=${controller.flutterView.viewId} '
        'physicalSize=${_describeSize(controller.flutterView.physicalSize)}',
      );
      unawaited(() async {
        await _invokeHostForViewId<void>(
          'configureTransientWindow',
          controller.flutterView.viewId,
          <String, Object?>{
            'interactive': false,
            'width': size.width,
            'height': size.height,
          },
        );
        await _waitForPositiveViewMetrics(
          kind: 'Tooltip',
          view: controller.flutterView,
        );
        debugPrint(
          '[DesktopMultiWindow][Tooltip] native-configured '
          'view=${controller.flutterView.viewId} closed=${controller.isClosed} '
          'physicalSize=${_describeSize(controller.flutterView.physicalSize)}',
        );
        if (!controller.isClosed) controller.updatePosition();
        controller._markReady();
      }());
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

  static Future<void> _waitForPositiveViewMetrics({
    required String kind,
    required FlutterView view,
  }) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final size = view.physicalSize;
      if (size.width > 0 && size.height > 0) {
        debugPrint(
          '[DesktopMultiWindow][$kind] metrics-ready '
          'view=${view.viewId} physicalSize=${_describeSize(size)} '
          'attempt=$attempt',
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    debugPrint(
      '[DesktopMultiWindow][$kind] metrics-timeout '
      'view=${view.viewId} physicalSize=${_describeSize(view.physicalSize)}',
    );
  }

  static String _describeSize(Size size) =>
      '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';

  static String _describeRect(Rect rect) =>
      '(${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},'
      '${rect.width.toStringAsFixed(1)}x${rect.height.toStringAsFixed(1)})';

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
  }) : _nativeController = nativeController,
       _onClosed = onClosed;

  final flutter_windowing.PopupWindowController _nativeController;
  final VoidCallback? _onClosed;
  final Completer<void> _readyCompleter = Completer<void>();
  bool _isClosed = false;

  FlutterView get flutterView => _nativeController.rootView;
  bool get isClosed => _isClosed;
  Future<void> get ready => _readyCompleter.future;

  void _markReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

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
  }) : _nativeController = nativeController,
       _onClosed = onClosed;

  final flutter_windowing.TooltipWindowController _nativeController;
  final VoidCallback? _onClosed;
  final Completer<void> _readyCompleter = Completer<void>();
  bool _isClosed = false;

  FlutterView get flutterView => _nativeController.rootView;
  bool get isClosed => _isClosed;
  Future<void> get ready => _readyCompleter.future;

  void _markReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

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
        child: _PositiveViewSizeGate(child: child),
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
        child: _PositiveViewSizeGate(child: child),
      ),
    );
  }
}

class WindowController extends ChangeNotifier {
  WindowController._({
    required this.windowId,
    required flutter_windowing.RegularWindowController nativeController,
    VoidCallback? onClosed,
  }) : _nativeController = nativeController,
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

  /// Lets the platform resize and dock this secondary window against the
  /// visible work area of the screen that currently contains it.
  Future<void> setPictureInPictureMode({
    required bool enabled,
    required double aspectRatio,
    required String placement,
    double margin = 16,
  }) async {
    if (_isClosed) return;
    await DesktopMultiWindow._invokeHost<void>(
      'setPictureInPictureMode',
      this,
      <String, Object?>{
        'enabled': enabled,
        'aspectRatio': aspectRatio,
        'placement': placement,
        'margin': margin,
      },
    );
  }

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
  final Map<Object, Widget> _transientViews = <Object, Widget>{};

  List<_DesktopWindowEntry> get windows =>
      List<_DesktopWindowEntry>.unmodifiable(_windows);

  List<Widget> get transientViews => _transientViews.entries
      .map(
        (entry) => KeyedSubtree(key: ObjectKey(entry.key), child: entry.value),
      )
      .toList(growable: false);

  void add(_DesktopWindowEntry entry) {
    _windows.add(entry);
    notifyListeners();
  }

  void remove(int windowId) {
    final oldLength = _windows.length;
    _windows.removeWhere((entry) => entry.controller.windowId == windowId);
    if (_windows.length != oldLength) notifyListeners();
  }

  void attachTransientView(Object owner, Widget view) {
    _transientViews[owner] = view;
    debugPrint(
      '[DesktopMultiWindow][Transient] attach '
      'owner=${owner.runtimeType} view=${view.runtimeType} '
      'count=${_transientViews.length}',
    );
    notifyListeners();
  }

  void detachTransientView(Object owner) {
    if (_transientViews.remove(owner) != null) {
      debugPrint(
        '[DesktopMultiWindow][Transient] detach '
        'owner=${owner.runtimeType} count=${_transientViews.length}',
      );
      notifyListeners();
    }
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
