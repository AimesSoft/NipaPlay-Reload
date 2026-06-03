struct ChannelName {
  static let methodChannel = "com.kurenai7968.volume_controller.method"
  static let eventChannel = "com.kurenai7968.volume_controller.volume_listener_event"
}

struct MethodName {
  static let getVolume = "getVolume"
  static let setVolume = "setVolume"
  static let isMuted = "isMuted"
  static let setMute = "setMute"
}

struct MethodArgument {
  static let volume = "volume"
  static let showSystemUI = "showSystemUI"
  static let isMute = "isMute"
}

struct EventArgument {
  static let fetchInitialVolume = "fetchInitialVolume"
}
