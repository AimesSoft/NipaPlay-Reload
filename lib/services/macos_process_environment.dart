import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show FlutterError, kIsWeb, visibleForTesting;

/// Queries the running process, rather than its build configuration or environment variables.
abstract final class MacOSProcessEnvironment {
  static const _channel = MethodChannel('security_bookmark');
  static Future<bool>? _sandboxed;

  /// Tests: the answer, without asking the native host. In a widget test
  /// a platform channel is answered in real time, which fake time never
  /// reaches, so the query would hold up every Classic request a widget
  /// test makes on a Mac (elsewhere it is never asked).
  @visibleForTesting
  static bool? debugSandboxedOverride;

  static Future<bool> isSandboxed() {
    if (debugSandboxedOverride case final sandboxed?) {
      return Future.value(sandboxed);
    }
    if (kIsWeb || !Platform.isMacOS) return Future.value(false);
    // Plain Dart (a unit test of a Classic service) has no binding and so no
    // native host to ask: not the sandboxed app. Not remembered, so that the
    // app, which has one, still asks.
    if (!_hasBinding) return Future.value(false);
    return _sandboxed ??= _query();
  }

  static bool get _hasBinding {
    try {
      ServicesBinding.instance;
      return true;
    } on FlutterError {
      return false;
    }
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
