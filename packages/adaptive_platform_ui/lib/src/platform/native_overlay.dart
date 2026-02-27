import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'platform_info.dart';

/// Native overlay helpers for iOS 26+.
class AdaptiveNativeOverlay {
  static const MethodChannel _channel =
      MethodChannel('adaptive_platform_ui/native_overlay');

  static bool get _isSupported =>
      !kIsWeb && PlatformInfo.isIOS26OrHigher();

  static Future<void> showScanProgress({
    required String title,
    required String message,
    double progress = 0.0,
  }) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('showScanProgress', {
        'title': title,
        'message': message,
        'progress': progress,
      });
    } catch (_) {}
  }

  static Future<void> updateScanProgress({
    String? message,
    double? progress,
  }) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('updateScanProgress', {
        if (message != null) 'message': message,
        if (progress != null) 'progress': progress,
      });
    } catch (_) {}
  }

  static Future<void> dismissScanProgress() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('dismissScanProgress');
    } catch (_) {}
  }

  static Future<void> showToast({
    required String message,
    Duration duration = const Duration(seconds: 2),
  }) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('showToast', {
        'message': message,
        'durationMs': duration.inMilliseconds,
      });
    } catch (_) {}
  }
}
