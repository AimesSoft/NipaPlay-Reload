import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';

class LabsSettingsProvider extends ChangeNotifier {
  LabsSettingsProvider() {
    _loadSettings();
  }

  bool _enableLargeScreenMode = false;
  bool _showRemoteAccessQrCode = false;
  bool _enableNext2DanmakuKernel = false;
  bool _enableNextPlusPlusEngine = true; // 默认打开：Next++ 激进优化引擎
  bool _isLoaded = false;

  bool get enableLargeScreenMode => _enableLargeScreenMode;
  bool get showRemoteAccessQrCode => _showRemoteAccessQrCode;
  bool get enableNext2DanmakuKernel => _enableNext2DanmakuKernel;
  bool get enableNextPlusPlusEngine => _enableNextPlusPlusEngine;
  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    _enableLargeScreenMode = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableLargeScreenMode,
      defaultValue: false,
    );
    _showRemoteAccessQrCode = await SettingsStorage.loadBool(
      SettingsKeys.labsShowRemoteAccessQrCode,
      defaultValue: false,
    );
    _enableNext2DanmakuKernel = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableNext2DanmakuKernel,
      defaultValue: false,
    );
    _enableNextPlusPlusEngine = await SettingsStorage.loadBool(
      SettingsKeys.labsEnableNextPlusPlusEngine,
      defaultValue: true,
    );
    DanmakuKernelFactory.setEnableNextPlusPlus(_enableNextPlusPlusEngine);
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

  Future<void> setShowRemoteAccessQrCode(bool enabled) async {
    if (_showRemoteAccessQrCode == enabled) return;
    _showRemoteAccessQrCode = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsShowRemoteAccessQrCode,
      enabled,
    );
  }

  Future<void> setEnableNext2DanmakuKernel(bool enabled) async {
    if (_enableNext2DanmakuKernel == enabled) return;
    _enableNext2DanmakuKernel = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableNext2DanmakuKernel,
      enabled,
    );
  }

  Future<void> setEnableNextPlusPlusEngine(bool enabled) async {
    if (_enableNextPlusPlusEngine == enabled) return;
    _enableNextPlusPlusEngine = enabled;
    DanmakuKernelFactory.setEnableNextPlusPlus(enabled);
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.labsEnableNextPlusPlusEngine,
      enabled,
    );
  }
}
