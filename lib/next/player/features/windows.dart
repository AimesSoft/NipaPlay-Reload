import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/services/desktop_picture_in_picture_preferences.dart';

/// The OS boundary is injectable so window tests never move, raise or resize
/// an actual window. Only explicit UI/window.control calls reach it.
abstract interface class PlaybackWindowPort {
  bool get closed;
  bool get alwaysOnTop;
  Future<void> close();
  Future<void> setAlwaysOnTop(bool value);
  Future<void> setPictureInPicture(bool value, double aspect);
}

typedef PlaybackWindowCreator = Future<PlaybackWindowPort> Function(
    WidgetBuilder builder, double aspect, VoidCallback onClosed);

final class PlaybackWindows extends ChangeNotifier {
  PlaybackWindows({PlaybackWindowCreator? create})
      : _create = create ?? _native;
  final PlaybackWindowCreator _create;
  PlaybackWindowPort? _window;
  Future<void> _turn = Future.value();
  bool _detached = false;
  bool _pip = false;
  bool _wasTop = false;
  bool _disposed = false;
  final stageKey = GlobalKey(debugLabel: 'next.window.video');

  bool get detached => _detached;
  bool get pictureInPicture => _pip;
  WindowController? get nativeWindow =>
      _window is _NativeWindow ? (_window as _NativeWindow).window : null;
  static bool get supported => DesktopMultiWindow.isSupported;

  Future<void> detach(WidgetBuilder builder, double aspect) =>
      _serial(() async {
        if (_disposed || _window != null) return;
        _detached = true;
        notifyListeners();
        try {
          final window = await _create(builder, aspect, _closed);
          if (_disposed || window.closed) {
            await window.close();
            _closed();
            return;
          }
          _window = window;
        } catch (_) {
          _closed();
          rethrow;
        }
      });

  Future<void> setPictureInPicture(bool value, double aspect) =>
      _serial(() async {
        final w = _window;
        if (w == null || w.closed || value == _pip) return;
        if (value) _wasTop = w.alwaysOnTop;
        try {
          await w.setPictureInPicture(value, aspect);
          await w.setAlwaysOnTop(value || _wasTop);
          _pip = value;
          notifyListeners();
        } catch (_) {
          await w.setPictureInPicture(false, aspect);
          await w.setAlwaysOnTop(_wasTop);
          _pip = false;
          notifyListeners();
          rethrow;
        }
      });

  Future<void> returnToMain() => _serial(() async {
        await _window?.close();
        _closed();
      });

  Future<void> _serial(Future<void> Function() op) {
    final result = _turn.then((_) => op());
    _turn = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  void _closed() {
    _window = null;
    _pip = false;
    _detached = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> shutdown() async {
    _disposed = true;
    await returnToMain();
  }

  static Future<PlaybackWindowPort> _native(
          WidgetBuilder builder, double aspect, VoidCallback onClosed) async =>
      _NativeWindow(await DesktopMultiWindow.createWindow(
        title: 'NipaPlay Next',
        size: Size(640, 640 / aspect),
        minimumSize: Size(240, 240 / aspect),
        aspectRatio: aspect,
        builder: (context, _) => builder(context),
        onClosed: onClosed,
      ));
}

final class _NativeWindow implements PlaybackWindowPort {
  _NativeWindow(this.window);
  final WindowController window;
  @override
  bool get closed => window.isClosed;
  @override
  bool get alwaysOnTop => window.isAlwaysOnTop;
  @override
  Future<void> close() => window.close();
  @override
  Future<void> setAlwaysOnTop(bool value) => window.setAlwaysOnTop(value);
  @override
  Future<void> setPictureInPicture(bool value, double aspect) async {
    final placement = await DesktopPictureInPicturePreferences.loadPosition();
    if (value && window.isFullscreen) await window.setFullscreen(false);
    await window
        .setMinimumSize(Size(value ? 160 : 240, (value ? 160 : 240) / aspect));
    await window.setPictureInPictureMode(
        enabled: value,
        aspectRatio: aspect,
        placement:
            DesktopPictureInPicturePreferences.serializePosition(placement));
  }
}
