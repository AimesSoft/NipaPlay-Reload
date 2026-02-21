import 'package:flutter/foundation.dart';

class DanmakuNextLog {
  static final Map<String, DateTime> _last = <String, DateTime>{};
  static final Set<String> _once = <String>{};

  static void d(
    String tag,
    String message, {
    Duration throttle = const Duration(seconds: 1),
  }) {
    if (throttle <= Duration.zero) {
      debugPrint('[DanmakuNext][$tag] $message');
      return;
    }

    final now = DateTime.now();
    final key = '$tag|${throttle.inMilliseconds}';
    final last = _last[key];
    if (last != null && now.difference(last) < throttle) return;
    _last[key] = now;
    debugPrint('[DanmakuNext][$tag] $message');
  }

  static void once(String tag, String message) {
    final key = '$tag|$message';
    if (_once.add(key)) {
      debugPrint('[DanmakuNext][$tag] $message');
    }
  }
}
