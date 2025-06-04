import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/settings_storage.dart';

/// 开发者选项Provider
/// 管理应用中的开发者相关设置
class DeveloperOptionsProvider extends ChangeNotifier {
  // 是否显示系统资源监控
  bool _showSystemResources = false;
  
  // 是否启用终端输出日志收集
  bool _enableDebugLogCollection = true;
  
  // 获取显示系统资源监控状态
  bool get showSystemResources => _showSystemResources;
  
  // 获取调试日志收集状态
  bool get enableDebugLogCollection => _enableDebugLogCollection;
  
  // 构造函数
  DeveloperOptionsProvider() {
    _loadSettings();
  }
  
  // 加载设置
  Future<void> _loadSettings() async {
    _showSystemResources = await SettingsStorage.loadBool(
      'show_system_resources', 
      defaultValue: false
    );
    
    _enableDebugLogCollection = await SettingsStorage.loadBool(
      'enable_debug_log_collection',
      defaultValue: true
    );
    
    notifyListeners();
  }
  
  // 切换系统资源监控显示状态
  Future<void> toggleSystemResources() async {
    _showSystemResources = !_showSystemResources;
    await SettingsStorage.saveBool('show_system_resources', _showSystemResources);
    notifyListeners();
  }
  
  // 设置系统资源监控显示状态
  Future<void> setShowSystemResources(bool value) async {
    if (_showSystemResources != value) {
      _showSystemResources = value;
      await SettingsStorage.saveBool('show_system_resources', _showSystemResources);
      notifyListeners();
    }
  }
  
  // 设置调试日志收集状态
  Future<void> setEnableDebugLogCollection(bool value) async {
    if (_enableDebugLogCollection != value) {
      _enableDebugLogCollection = value;
      await SettingsStorage.saveBool('enable_debug_log_collection', _enableDebugLogCollection);
      notifyListeners();
    }
  }
} 