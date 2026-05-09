import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class DownloaderSettingsProvider extends ChangeNotifier {
  DownloaderSettingsProvider() {
    _loadSettings();
  }

  bool _enabled = true;
  bool _createFolderForTask = true;
  bool _autoScanCompletedTasks = true;
  bool _isLoaded = false;

  bool get enabled => _enabled;
  bool get createFolderForTask => _createFolderForTask;
  bool get autoScanCompletedTasks => _autoScanCompletedTasks;
  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    _enabled = await SettingsStorage.loadBool(
      SettingsKeys.downloaderEnabled,
      defaultValue: true,
    );
    _createFolderForTask = await SettingsStorage.loadBool(
      SettingsKeys.downloaderCreateFolderForTask,
      defaultValue: true,
    );
    _autoScanCompletedTasks = await SettingsStorage.loadBool(
      SettingsKeys.downloaderAutoScanCompletedTasks,
      defaultValue: true,
    );
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(SettingsKeys.downloaderEnabled, enabled);
  }

  Future<void> setCreateFolderForTask(bool enabled) async {
    if (_createFolderForTask == enabled) return;
    _createFolderForTask = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.downloaderCreateFolderForTask,
      enabled,
    );
  }

  Future<void> setAutoScanCompletedTasks(bool enabled) async {
    if (_autoScanCompletedTasks == enabled) return;
    _autoScanCompletedTasks = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(
      SettingsKeys.downloaderAutoScanCompletedTasks,
      enabled,
    );
  }
}
