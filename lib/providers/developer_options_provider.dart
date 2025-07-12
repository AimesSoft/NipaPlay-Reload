import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/settings_storage.dart';

/// 开发者选项Provider
/// 管理应用中的开发者相关设置
class DeveloperOptionsProvider extends ChangeNotifier {
  // 是否显示系统资源监控
  bool _showSystemResources = false;
  
  // 是否启用终端输出日志收集
  bool _enableDebugLogCollection = true;
  
  // 是否显示CanvasDanmaku弹幕内核碰撞箱
  bool _showCanvasDanmakuCollisionBoxes = false;
  
  // 是否显示CanvasDanmaku弹幕内核轨道编号
  bool _showCanvasDanmakuTrackNumbers = false;
  
  // 是否显示GPUDanmaku弹幕内核碰撞箱
  bool _showGPUDanmakuCollisionBoxes = false;
  
  // 是否显示GPUDanmaku弹幕内核轨道编号
  bool _showGPUDanmakuTrackNumbers = false;
  
  // 获取显示系统资源监控状态
  bool get showSystemResources => _showSystemResources;
  
  // 获取调试日志收集状态
  bool get enableDebugLogCollection => _enableDebugLogCollection;
  
  // 获取CanvasDanmaku弹幕内核碰撞箱显示状态
  bool get showCanvasDanmakuCollisionBoxes => _showCanvasDanmakuCollisionBoxes;
  
  // 获取CanvasDanmaku弹幕内核轨道编号显示状态
  bool get showCanvasDanmakuTrackNumbers => _showCanvasDanmakuTrackNumbers;
  
  // 获取GPUDanmaku弹幕内核碰撞箱显示状态
  bool get showGPUDanmakuCollisionBoxes => _showGPUDanmakuCollisionBoxes;
  
  // 获取GPUDanmaku弹幕内核轨道编号显示状态
  bool get showGPUDanmakuTrackNumbers => _showGPUDanmakuTrackNumbers;
  
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
    
    _showCanvasDanmakuCollisionBoxes = await SettingsStorage.loadBool(
      'show_canvas_danmaku_collision_boxes',
      defaultValue: false
    );
    
    _showCanvasDanmakuTrackNumbers = await SettingsStorage.loadBool(
      'show_canvas_danmaku_track_numbers',
      defaultValue: false
    );
    
    _showGPUDanmakuCollisionBoxes = await SettingsStorage.loadBool(
      'show_gpu_danmaku_collision_boxes',
      defaultValue: false
    );
    
    _showGPUDanmakuTrackNumbers = await SettingsStorage.loadBool(
      'show_gpu_danmaku_track_numbers',
      defaultValue: false
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
  
  // 设置CanvasDanmaku弹幕内核碰撞箱显示状态
  Future<void> setShowCanvasDanmakuCollisionBoxes(bool value) async {
    if (_showCanvasDanmakuCollisionBoxes != value) {
      _showCanvasDanmakuCollisionBoxes = value;
      await SettingsStorage.saveBool('show_canvas_danmaku_collision_boxes', _showCanvasDanmakuCollisionBoxes);
      notifyListeners();
    }
  }
  
  // 设置CanvasDanmaku弹幕内核轨道编号显示状态
  Future<void> setShowCanvasDanmakuTrackNumbers(bool value) async {
    if (_showCanvasDanmakuTrackNumbers != value) {
      _showCanvasDanmakuTrackNumbers = value;
      await SettingsStorage.saveBool('show_canvas_danmaku_track_numbers', _showCanvasDanmakuTrackNumbers);
      notifyListeners();
    }
  }
  
  // 设置GPUDanmaku弹幕内核碰撞箱显示状态
  Future<void> setShowGPUDanmakuCollisionBoxes(bool value) async {
    if (_showGPUDanmakuCollisionBoxes != value) {
      _showGPUDanmakuCollisionBoxes = value;
      await SettingsStorage.saveBool('show_gpu_danmaku_collision_boxes', _showGPUDanmakuCollisionBoxes);
      notifyListeners();
    }
  }
  
  // 设置GPUDanmaku弹幕内核轨道编号显示状态
  Future<void> setShowGPUDanmakuTrackNumbers(bool value) async {
    if (_showGPUDanmakuTrackNumbers != value) {
      _showGPUDanmakuTrackNumbers = value;
      await SettingsStorage.saveBool('show_gpu_danmaku_track_numbers', _showGPUDanmakuTrackNumbers);
      notifyListeners();
    }
  }
} 