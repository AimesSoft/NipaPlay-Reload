class ChannelName {
  static const String methodChannel =
      'com.kurenai7968.volume_controller.method';
  static const String eventChannel =
      'com.kurenai7968.volume_controller.volume_listener_event';
}

class MethodName {
  static const String getVolume = 'getVolume';
  static const String setVolume = 'setVolume';
  static const String isMuted = 'isMuted';
  static const String setMute = 'setMute';
}

class MethodArgument {
  static const String volume = 'volume';
  static const String showSystemUI = 'showSystemUI';
  static const String isMute = 'isMute';
}

class EventArgument {
  static const String fetchInitialVolume = 'fetchInitialVolume';
}
