import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/pages/external_player_console_page.dart';
import 'package:nipaplay/pages/external_player_console_window.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:screen_retriever/screen_retriever.dart';

class ExternalPlayerConsoleWindowService extends ChangeNotifier {
  ExternalPlayerConsoleWindowService._() {
    ExternalPlayerConsoleService.sessionAvailability.addListener(
      _handleSessionAvailabilityChanged,
    );
  }

  static final ExternalPlayerConsoleWindowService instance =
      ExternalPlayerConsoleWindowService._();

  static bool get isSupported =>
      ExternalPlayerConsoleService.isSupportedPlatform &&
      DesktopMultiWindow.isSupported;

  WindowController? _controlsWindow;
  WindowController? _danmakuListWindow;
  bool _creatingControlsWindow = false;
  bool _creatingDanmakuListWindow = false;

  WindowController? get controlsWindow => _controlsWindow;
  WindowController? get danmakuListWindow => _danmakuListWindow;

  Future<void> showControlsWindow() async {
    if (!isSupported || !ExternalPlayerConsoleService.hasActiveSession) return;
    final existing = _controlsWindow;
    if (existing != null && !existing.isClosed) {
      await existing.show();
      return;
    }
    if (_creatingControlsWindow) return;

    _creatingControlsWindow = true;
    try {
      final size = await _preferredPortraitSize();
      debugPrint(
        '[ExternalPlayerConsoleWindow] 创建控制窗口: '
        '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}',
      );
      final window = await DesktopMultiWindow.createWindow(
        title: 'NipaPlay 弹幕控制台',
        size: size,
        minimumSize: _minimumSizeFor(size),
        frameless: true,
        aspectRatio: 0.5,
        builder: (context, controller) => ExternalPlayerConsoleWindow(
          controller: controller,
          pane: ExternalPlayerConsolePane.controls,
          onShowDanmakuList: () => unawaited(showDanmakuListWindow()),
          onClose: () => unawaited(closeControlsWindow()),
        ),
        onClosed: _handleControlsWindowClosed,
      );
      if (!window.isClosed) _controlsWindow = window;
    } catch (error, stackTrace) {
      debugPrint(
        '[ExternalPlayerConsoleWindow] 创建控制窗口失败: '
        '$error\n$stackTrace',
      );
    } finally {
      _creatingControlsWindow = false;
      notifyListeners();
    }
  }

  Future<void> showDanmakuListWindow() async {
    if (!isSupported || !ExternalPlayerConsoleService.hasActiveSession) return;
    final existing = _danmakuListWindow;
    if (existing != null && !existing.isClosed) {
      await existing.show();
      return;
    }
    if (_creatingDanmakuListWindow) return;

    _creatingDanmakuListWindow = true;
    try {
      final size = await _preferredPortraitSize();
      debugPrint(
        '[ExternalPlayerConsoleWindow] 创建弹幕列表窗口: '
        '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}',
      );
      final window = await DesktopMultiWindow.createWindow(
        title: 'NipaPlay 弹幕列表',
        size: size,
        minimumSize: _minimumSizeFor(size),
        frameless: true,
        aspectRatio: 0.5,
        builder: (context, controller) => ExternalPlayerConsoleWindow(
          controller: controller,
          pane: ExternalPlayerConsolePane.danmakuList,
          onClose: () => unawaited(closeDanmakuListWindow()),
        ),
        onClosed: _handleDanmakuListWindowClosed,
      );
      if (!window.isClosed) _danmakuListWindow = window;
    } catch (error, stackTrace) {
      debugPrint(
        '[ExternalPlayerConsoleWindow] 创建弹幕列表窗口失败: '
        '$error\n$stackTrace',
      );
    } finally {
      _creatingDanmakuListWindow = false;
      notifyListeners();
    }
  }

  Future<void> closeControlsWindow() async {
    final window = _controlsWindow;
    _controlsWindow = null;
    if (window != null && !window.isClosed) await window.close();
    await closeDanmakuListWindow();
    notifyListeners();
  }

  Future<void> closeDanmakuListWindow() async {
    final window = _danmakuListWindow;
    _danmakuListWindow = null;
    if (window != null && !window.isClosed) await window.close();
    notifyListeners();
  }

  Future<void> closeAll() async {
    await closeDanmakuListWindow();
    final window = _controlsWindow;
    _controlsWindow = null;
    if (window != null && !window.isClosed) await window.close();
    notifyListeners();
  }

  void _handleControlsWindowClosed() {
    _controlsWindow = null;
    unawaited(closeDanmakuListWindow());
    notifyListeners();
  }

  void _handleDanmakuListWindowClosed() {
    _danmakuListWindow = null;
    notifyListeners();
  }

  void _handleSessionAvailabilityChanged() {
    if (!ExternalPlayerConsoleService.hasActiveSession) {
      unawaited(closeAll());
    }
  }

  Future<Size> _preferredPortraitSize() async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final visibleSize = display.visibleSize ?? display.size;
      if (visibleSize.height.isFinite && visibleSize.height > 0) {
        final height = visibleSize.height / 2;
        return Size(height / 2, height);
      }
    } catch (error) {
      debugPrint(
        '[ExternalPlayerConsoleWindow] 获取屏幕尺寸失败，使用默认尺寸: $error',
      );
    }
    return const Size(270, 540);
  }

  Size _minimumSizeFor(Size preferredSize) {
    return Size(
      preferredSize.width.clamp(160, 220).toDouble(),
      preferredSize.height.clamp(320, 440).toDouble(),
    );
  }
}
