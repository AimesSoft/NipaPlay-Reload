import 'package:nipaplay/plugins/models/plugin_event.dart';

class PluginEventBus {
  final _listeners = <String, Set<void Function(PluginEvent)>>{};

  void on(String eventName, void Function(PluginEvent) listener) {
    _listeners.putIfAbsent(eventName, () => {}).add(listener);
  }

  void off(String eventName, void Function(PluginEvent) listener) {
    _listeners[eventName]?.remove(listener);
  }

  void emit(String eventName, Map<String, dynamic> data) {
    final event = PluginEvent(name: eventName, data: data);
    final listeners = _listeners[eventName];
    if (listeners != null) {
      for (final listener in listeners) {
        try {
          listener(event);
        } catch (_) {}
      }
    }
  }

  void emitVideoLoaded(Map<String, dynamic> data) {
    emit(PluginEventType.videoLoaded, data);
  }

  void emitPlay(Map<String, dynamic> data) {
    emit(PluginEventType.play, data);
  }

  void emitPause(Map<String, dynamic> data) {
    emit(PluginEventType.pause, data);
  }

  void emitSeek(Map<String, dynamic> data) {
    emit(PluginEventType.seek, data);
  }

  void emitDanmakuShow(Map<String, dynamic> data) {
    emit(PluginEventType.danmakuShow, data);
  }

  void emitSettingsChanged(Map<String, dynamic> data) {
    emit(PluginEventType.settingsChanged, data);
  }

  void emitAppResumed() {
    emit(PluginEventType.appResumed, {});
  }

  void emitAppPaused() {
    emit(PluginEventType.appPaused, {});
  }

  void dispose() {
    _listeners.clear();
  }
}