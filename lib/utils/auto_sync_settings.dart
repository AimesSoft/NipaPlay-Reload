import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AutoSyncSettings {
  static const String _enabledKey = 'auto_sync_enabled';
  static const String _pathKey = 'auto_sync_path';
  
  static SharedPreferences? _prefs;
  
  static Future<void> _ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// 获取自动同步是否启用
  static Future<bool> isEnabled() async {
    await _ensureInitialized();
    return _prefs!.getBool(_enabledKey) ?? false;
  }
  
  /// 设置自动同步启用状态
  static Future<void> setEnabled(bool enabled) async {
    await _ensureInitialized();
    await _prefs!.setBool(_enabledKey, enabled);
    debugPrint('自动同步已${enabled ? "启用" : "禁用"}');
  }
  
  /// 获取自动同步路径
  static Future<String?> getSyncPath() async {
    await _ensureInitialized();
    return _prefs!.getString(_pathKey);
  }
  
  /// 设置自动同步路径
  static Future<void> setSyncPath(String? path) async {
    await _ensureInitialized();
    if (path != null) {
      await _prefs!.setString(_pathKey, path);
      debugPrint('自动同步路径已设置: $path');
    } else {
      await _prefs!.remove(_pathKey);
      debugPrint('自动同步路径已清除');
    }
  }
  
  /// 获取自动同步文件的完整路径
  static Future<String?> getSyncFilePath() async {
    final syncPath = await getSyncPath();
    if (syncPath == null) return null;
    
    // 固定文件名：nipaplay_auto_sync.nph
    return '$syncPath/nipaplay_auto_sync.nph';
  }
}