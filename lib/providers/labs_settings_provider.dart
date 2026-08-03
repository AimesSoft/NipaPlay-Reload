import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class LabsSettingsProvider extends ChangeNotifier {
  LabsSettingsProvider() {
    _loadSettings();
  }

  bool _enableErikaPlayerKernel = false;
  bool _isLoaded = false;

  bool get enableErikaPlayerKernel => _enableErikaPlayerKernel;
  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    _enableErikaPlayerKernel = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableErikaPlayerKernel,
      defaultValue: false,
    );
    _isLoaded = true;
    notifyListeners();
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
