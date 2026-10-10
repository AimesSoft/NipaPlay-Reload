import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class LabsSettingsProvider extends ChangeNotifier {
  LabsSettingsProvider() {
    ready = _loadSettings();
  }

  /// Completes after the persisted lab switches have been restored.
  ///
  /// Routes that make a one-shot decision from these values must await this
  /// future; otherwise an app launch can observe the in-memory defaults before
  /// SharedPreferences has finished loading.
  late final Future<void> ready;

  bool _enableErikaPlayerKernel = false;
  bool _enableImmersiveAnimeDetail = false;
  bool _enableAgentEndpoint = false;
  bool _isLoaded = false;

  bool get enableErikaPlayerKernel => _enableErikaPlayerKernel;
  bool get enableImmersiveAnimeDetail => _enableImmersiveAnimeDetail;
  bool get enableAgentEndpoint => _enableAgentEndpoint;
  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    _enableErikaPlayerKernel = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableErikaPlayerKernel,
      defaultValue: false,
    );
    _enableImmersiveAnimeDetail = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableImmersiveAnimeDetail,
      defaultValue: false,
    );
    _enableAgentEndpoint = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableAgentEndpoint,
      defaultValue: false,
    );
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setEnableErikaPlayerKernel(bool enabled) async {
    await ready;
    if (_enableErikaPlayerKernel == enabled) return;
    _enableErikaPlayerKernel = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableErikaPlayerKernel,
      enabled,
    );
  }

  Future<void> setEnableImmersiveAnimeDetail(bool enabled) async {
    await ready;
    if (_enableImmersiveAnimeDetail == enabled) return;
    _enableImmersiveAnimeDetail = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableImmersiveAnimeDetail,
      enabled,
    );
  }

  Future<void> setEnableAgentEndpoint(bool enabled) async {
    await ready;
    if (_enableAgentEndpoint == enabled) return;
    _enableAgentEndpoint = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableAgentEndpoint,
      enabled,
    );
  }
}
