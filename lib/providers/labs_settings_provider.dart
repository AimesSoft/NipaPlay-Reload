import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/services/macos_process_environment.dart';

class LabsSettingsProvider extends ChangeNotifier {
  LabsSettingsProvider({Future<bool> Function()? sandboxStatus}) {
    _sandboxStatus = sandboxStatus ?? MacOSProcessEnvironment.isSandboxed;
    ready = _loadSettings();
  }

  /// Completes after the persisted lab switches have been restored.
  ///
  /// Routes that make a one-shot decision from these values must await this
  /// future; otherwise an app launch can observe the in-memory defaults before
  /// SharedPreferences has finished loading.
  late final Future<void> ready;

  bool _enableImmersiveAnimeDetail = false;
  bool _enableAgentEndpoint = false;
  bool _isLoaded = false;
  bool _nextAvailable = false;
  late final Future<bool> Function() _sandboxStatus;

  bool get enableImmersiveAnimeDetail => _enableImmersiveAnimeDetail;
  bool get nextAvailable => _nextAvailable;
  bool get enableAgentEndpoint => _nextAvailable && _enableAgentEndpoint;
  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    _nextAvailable = !await _sandboxStatus();
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
    if (enabled && !_nextAvailable) {
      throw StateError('NipaPlay Next is unavailable in an App Sandbox process');
    }
    if (_enableAgentEndpoint == enabled) return;
    _enableAgentEndpoint = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableAgentEndpoint,
      enabled,
    );
  }
}
