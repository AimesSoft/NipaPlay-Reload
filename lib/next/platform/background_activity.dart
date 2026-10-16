import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps macOS from napping NipaPlay while Next may be working for the user
/// in the background. Every step Nipa takes goes through NipaPlay, and a
/// napping app answers in minutes instead of milliseconds; downloads slow
/// down too. System sleep stays allowed.
abstract final class BackgroundActivity {
  static const _native = MethodChannel('nipaplay/instance');
  static bool _active = false;

  static Future<void> set(bool active) async {
    if (kIsWeb || !Platform.isMacOS || _active == active) return;
    _active = active;
    try {
      await _native.invokeMethod('backgroundActivity', {'active': active});
    } catch (error) {
      debugPrint('[Next] background activity unavailable: $error');
    }
  }
}
