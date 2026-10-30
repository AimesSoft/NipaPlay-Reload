/// Implemented by a kernel driver with a native compositor (Erika). Calls
/// must enter the driver's fenced serial queue, as all native operations do.
/// The session port stops forwarding before its session starts closing.
abstract interface class SessionNativeDanmakuDriver {
  SessionNativeDanmakuSink get danmakuSink;
}

abstract interface class SessionNativeDanmakuSink {
  /// The whole display timeline as JSON (a list of NipaPlay's danmaku maps:
  /// time, content, type, color, …), encoded on the danmaku worker so the
  /// main isolate neither copies nor encodes the comments.
  Future<void> replaceDanmaku(String timelineJson);
  Future<void> configureDanmaku(Map<String, Object?> settings);
}
