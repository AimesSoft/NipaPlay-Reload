import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemoteAccessSettingsProvider extends ChangeNotifier {
  RemoteAccessSettingsProvider() {
    _loadSettings();
  }

  bool _showRemoteAccessQrCode = false;
  bool _isLoaded = false;

  bool get showRemoteAccessQrCode => _showRemoteAccessQrCode;
  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getBool(SettingsKeys.showRemoteAccessQrCode);
    final legacyValue = prefs.getBool(SettingsKeys.labsShowRemoteAccessQrCode);
    _showRemoteAccessQrCode = savedValue ?? legacyValue ?? false;
    if (savedValue == null && legacyValue != null) {
      await prefs.setBool(SettingsKeys.showRemoteAccessQrCode, legacyValue);
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setShowRemoteAccessQrCode(bool enabled) async {
    if (_showRemoteAccessQrCode == enabled) return;
    _showRemoteAccessQrCode = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.showRemoteAccessQrCode, enabled);
  }
}
