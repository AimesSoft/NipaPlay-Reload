import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  late SharedPreferences _prefs;

  // --- Settings ---
  double _blurPower = 0.0; // Default blur power (无模糊)
  static const double _defaultBlur = 0.0;
  static const String _blurPowerKey = 'blurPower';
  
  // 弹幕转换简体中文设置
  bool _danmakuConvertToSimplified = true; // 默认开启
  static const String _danmakuConvertKey = 'danmaku_convert_to_simplified';

  // --- Getters ---
  double get blurPower => _blurPower;
  bool get isBlurEnabled => _blurPower > 0;
  bool get danmakuConvertToSimplified => _danmakuConvertToSimplified;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    // Load blur power, defaulting to 0.0 if not set (无模糊)
    _blurPower = _prefs.getDouble(_blurPowerKey) ?? _defaultBlur;
    // Load danmaku convert setting, defaulting to true if not set
    _danmakuConvertToSimplified = _prefs.getBool(_danmakuConvertKey) ?? true;
    notifyListeners();
  }

  // --- Setters ---

  /// Toggles the background blur effect.
  ///
  /// If `enable` is true, blurPower is set to a medium blur value.
  /// If `enable` is false, blurPower is set to 0.
  Future<void> setBlurEnabled(bool enable) async {
    _blurPower = enable ? 10.0 : 0.0; // 开启时使用中等模糊强度
    await _prefs.setDouble(_blurPowerKey, _blurPower);
    notifyListeners();
  }

  /// Sets a specific blur power value.
  Future<void> setBlurPower(double value) async {
    _blurPower = value;
    await _prefs.setDouble(_blurPowerKey, _blurPower);
    notifyListeners();
  }

  /// Sets the danmaku convert to simplified Chinese setting.
  Future<void> setDanmakuConvertToSimplified(bool enable) async {
    _danmakuConvertToSimplified = enable;
    await _prefs.setBool(_danmakuConvertKey, _danmakuConvertToSimplified);
    notifyListeners();
  }
}
