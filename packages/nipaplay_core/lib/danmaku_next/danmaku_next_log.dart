import 'dart:developer' as developer;

class DanmakuNextLog {
  static final Map<String, int> _lastLogTimeMs = {};

  static void d(
    String tag,
    String message, {
    Duration throttle = const Duration(seconds: 1),
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastLogTimeMs[tag] ?? 0;
    if (now - last < throttle.inMilliseconds) return;
    _lastLogTimeMs[tag] = now;

    final line = '[$tag] $message';
    developer.log(line, name: 'DanmakuNext');
  }

  static void once(String tag, String message) {
    d(tag, message, throttle: const Duration(days: 365));
  }
}
