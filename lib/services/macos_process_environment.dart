import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Queries the running process, rather than its build configuration or environment variables.
abstract final class MacOSProcessEnvironment {
  static const _channel = MethodChannel('security_bookmark');
  static Future<bool>? _sandboxed;

  static Future<bool> isSandboxed() {
    if (kIsWeb || !Platform.isMacOS) return Future.value(false);
    return _sandboxed ??= _query();
  }

  static Future<bool> _query() async {
    final bool? value;
    try {
      value = await _channel.invokeMethod<bool>('isSandboxed');
    } on MissingPluginException {
      // No native host (flutter test), so not the sandboxed app container.
      return false;
    }
    if (value == null) throw StateError('macOS sandbox status is unavailable');
    return value;
  }
}
