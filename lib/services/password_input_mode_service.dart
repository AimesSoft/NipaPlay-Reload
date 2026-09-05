import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Restricts only the active macOS password field's input context to Roman
/// input sources. No password text is sent to native code or modified here.
class PasswordInputModeService with WidgetsBindingObserver {
  static final instance = PasswordInputModeService();
  static const _channel = MethodChannel('nipaplay/password_input_mode');
  bool _started = false;
  bool _scheduled = false;
  bool _resumed = true;

  void start() {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    _started = true;
    FocusManager.instance.addListener(_scheduleUpdate);
    WidgetsBinding.instance.addObserver(this);
    _scheduleUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    if (!_started || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_started) return;
      final context = FocusManager.instance.primaryFocus?.context;
      final widget = context?.widget;
      final editable = widget is EditableText
          ? widget
          : context?.findAncestorWidgetOfExactType<EditableText>();
      final isPassword = editable != null &&
          (editable.obscureText ||
              editable.keyboardType == TextInputType.visiblePassword);
      unawaited(_setNativeMode(_resumed && isPassword));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _setNativeMode(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setPasswordMode', enabled);
    } on MissingPluginException {
      // Older runners and non-native widget tests can still edit passwords.
    } on PlatformException catch (error) {
      debugPrint('Password input mode unavailable: ${error.code}');
    }
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    FocusManager.instance.removeListener(_scheduleUpdate);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_setNativeMode(false));
  }
}
