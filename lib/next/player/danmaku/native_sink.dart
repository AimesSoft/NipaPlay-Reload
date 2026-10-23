/// Implemented by a kernel driver with a native compositor (Erika). Calls
/// must enter the driver's fenced serial queue, as all native operations do.
/// The session port stops forwarding before its session starts closing.
abstract interface class SessionNativeDanmakuDriver {
  SessionNativeDanmakuSink get danmakuSink;
}

abstract interface class SessionNativeDanmakuSink {
  Future<void> replaceDanmaku(List<Map<String, dynamic>> timeline);
  Future<void> configureDanmaku(Map<String, Object?> settings);
}
