import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class LabsSettingsProvider extends ChangeNotifier {
  LabsSettingsProvider() {
    _loadSettings();
  }

  bool _enableLargeScreenMode = false;
  bool _enableErikaPlayerKernel = false;
  bool _isLoaded = false;

  // The television layout is a first-class mode on Apple TV rather than an
  // experimental feature. The separate layout preference can still be used
  // to leave large-screen mode for the current device.
  bool get enableLargeScreenMode => globals.isTvOS || _enableLargeScreenMode;
  bool get enableErikaPlayerKernel => _enableErikaPlayerKernel;
  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    _enableLargeScreenMode = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableLargeScreenMode,
      defaultValue: false,
    );
    _enableErikaPlayerKernel = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableErikaPlayerKernel,
      defaultValue: false,
    );
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setEnableLargeScreenMode(bool enabled) async {
    if (globals.isTvOS) return;
    if (_enableLargeScreenMode == enabled) return;
    _enableLargeScreenMode = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableLargeScreenMode,
      enabled,
    );
  }

  Future<void> setEnableErikaPlayerKernel(bool enabled) async {
    if (_enableErikaPlayerKernel == enabled) return;
    _enableErikaPlayerKernel = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableErikaPlayerKernel,
      enabled,
    );
  }
}
