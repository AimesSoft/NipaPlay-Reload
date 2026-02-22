class DanmakuNextLog {
  static void d(
    String tag,
    String message, {
    Duration throttle = const Duration(seconds: 1),
  }) {
    // Intentionally no-op: silence [DanmakuNext] logs.
    return;
  }

  static void once(String tag, String message) {
    // Intentionally no-op: silence [DanmakuNext] logs.
    return;
  }
}
