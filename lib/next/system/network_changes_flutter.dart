import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

abstract final class SystemNetworkChanges {
  static const channel = MethodChannel('nipaplay/network_path');
  static Stream<void>? get changes =>
      Platform.isIOS || Platform.isMacOS ? _events : null;
  static final _listeners = <MultiStreamController<void>>{};
  static Future<void> _turn = Future.value();
  static bool _running = false;
  static final _events = Stream<void>.multi((listener) {
    _listeners.add(listener);
    _sync();
    listener.onCancel = () {
      _listeners.remove(listener);
      _sync();
    };
  }, isBroadcast: true);
  static void _sync() {
    _turn = _turn.then((_) async {
      if (_listeners.isNotEmpty && !_running) {
        channel.setMethodCallHandler((call) async {
          if (call.method == 'changed') {
            for (final listener in [..._listeners]) {
              listener.add(null);
            }
          }
        });
        try {
          await channel.invokeMethod<void>('start');
          _running = true;
        } catch (error, stack) {
          for (final listener in [..._listeners]) {
            listener.addError(error, stack);
          }
        }
      } else if (_listeners.isEmpty && _running) {
        _running = false;
        channel.setMethodCallHandler(null);
        try {
          await channel.invokeMethod<void>('stop');
        } on MissingPluginException {/* 未包含桥接的测试宿主。 */} on PlatformException {
          /* 清理不能阻止会话释放。 */
        }
      }
    });
  }
}
