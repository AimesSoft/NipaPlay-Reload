import 'dart:async';

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

  final Completer<void> _loadCompleter = Completer<void>();

  bool get enabled => _enabled;
  bool get createFolderForTask => _createFolderForTask;
  bool get autoScanCompletedTasks => _autoScanCompletedTasks;
  bool get isLoaded => _isLoaded;

  /// 首次加载完成（或失败）时完成。
  ///
  /// 调用方应 `await` 这个 Future，而不是轮询 [isLoaded]：轮询在加载失败时
  /// 会变成永不退出的忙等循环。
  Future<void> get loaded => _loadCompleter.future;

  Future<void> _loadSettings() async {
    try {
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
    } catch (e) {
      debugPrint('加载下载器设置失败，使用默认值: $e');
    } finally {
      // 无论成功与否都要收敛，保证等待方一定会被唤醒。
      _isLoaded = true;
      if (!_loadCompleter.isCompleted) {
        _loadCompleter.complete();
      }
      notifyListeners();
    }
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
