import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class LabsSettingsProvider extends ChangeNotifier {
  LabsSettingsProvider() {
    _loadSettings();
  }

  bool _enableLargeScreenMode = false;
  bool _enableRustFileScan = false;
  bool _isLoaded = false;

  bool get enableLargeScreenMode => _enableLargeScreenMode;
  bool get enableRustFileScan => _enableRustFileScan;
  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    _enableLargeScreenMode = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableLargeScreenMode,
      defaultValue: false,
    );
    _enableRustFileScan = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableRustFileScan,
      defaultValue: false,
    );
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setEnableLargeScreenMode(bool enabled) async {
    if (_enableLargeScreenMode == enabled) return;
    _enableLargeScreenMode = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableLargeScreenMode,
      enabled,
    );
  }

  Future<void> setEnableRustFileScan(bool enabled) async {
    if (_enableRustFileScan == enabled) return;
    _enableRustFileScan = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableRustFileScan,
      enabled,
    );
  }
}
