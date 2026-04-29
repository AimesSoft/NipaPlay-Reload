import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class LabsSettingsProvider extends ChangeNotifier {
  LabsSettingsProvider() {
    _loadSettings();
  }

  bool _enableLargeScreenMode = false;
  bool _isLoaded = false;

  bool get enableLargeScreenMode => _enableLargeScreenMode;
  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    _enableLargeScreenMode = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableLargeScreenMode,
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
}
