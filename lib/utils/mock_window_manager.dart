// lib/utils/mock_window_manager.dart

// 模拟 window_manager 包，用于 Web 平台编译

class WindowManager {
  Future<void> ensureInitialized() async {}
  Future<void> waitUntilReadyToShow(WindowOptions? options, Function callback) async {
    callback();
  }
  Future<void> setMinimumSize(dynamic size) async {}
  Future<void> maximize() async {}
  Future<void> show() async {}
  Future<void> focus() async {}
  Future<void> addListener(dynamic listener) async {}
  Future<void> removeListener(dynamic listener) async {}
  Future<void> startDragging() async {}
  Future<bool> isMaximized() async => false;
  Future<void> unmaximize() async {}
  Future<void> minimize() async {}
  Future<void> close() async {}
}

final windowManager = WindowManager();

class WindowOptions {
  final bool skipTaskbar;
  final TitleBarStyle titleBarStyle;
  final String title;

  const WindowOptions({
    this.skipTaskbar = false,
    this.titleBarStyle = TitleBarStyle.hidden,
    this.title = "NipaPlay",
  });
}

enum TitleBarStyle {
  normal,
  hidden,
}

class WindowListener {} 