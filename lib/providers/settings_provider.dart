import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  late SharedPreferences _prefs;

  // --- Settings ---
  double _blurPower = 10.0; // Default blur power
  static const double _defaultBlur = 10.0;
  static const String _blurPowerKey = 'blurPower';

  // --- Getters ---
  double get blurPower => _blurPower;
  bool get isBlurEnabled => _blurPower > 0;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    // Load blur power, defaulting to 10.0 if not set
    _blurPower = _prefs.getDouble(_blurPowerKey) ?? _defaultBlur;
    notifyListeners();
  }

  // --- Setters ---

  /// Toggles the background blur effect.
  ///
  /// If `enable` is true, blurPower is set to the default value.
  /// If `enable` is false, blurPower is set to 0.
  Future<void> setBlurEnabled(bool enable) async {
    _blurPower = enable ? _defaultBlur : 0.0;
    await _prefs.setDouble(_blurPowerKey, _blurPower);
    notifyListeners();
  }

  /// Sets a specific blur power value.
  Future<void> setBlurPower(double value) async {
    _blurPower = value;
    await _prefs.setDouble(_blurPowerKey, _blurPower);
    notifyListeners();
  }
}
