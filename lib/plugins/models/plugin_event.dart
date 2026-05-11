import 'dart:convert';

class PluginEvent {
  const PluginEvent({
    required this.name,
    required this.data,
  });

  final String name;
  final Map<String, dynamic> data;

  String toJson() {
    return json.encode({
      'name': name,
      'data': data,
    });
  }

  factory PluginEvent.fromJson(String jsonStr) {
    final decoded = json.decode(jsonStr) as Map<String, dynamic>;
    return PluginEvent(
      name: decoded['name'] as String,
      data: decoded['data'] as Map<String, dynamic>,
    );
  }
}

class PluginEventType {
  static const String videoLoaded = 'videoLoaded';
  static const String play = 'play';
  static const String pause = 'pause';
  static const String seek = 'seek';
  static const String danmakuShow = 'danmakuShow';
  static const String danmakuLoaded = 'danmakuLoaded';
  static const String settingsChanged = 'settingsChanged';
  static const String appResumed = 'appResumed';
  static const String appPaused = 'appPaused';
}
