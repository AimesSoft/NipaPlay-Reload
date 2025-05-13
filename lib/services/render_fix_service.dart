import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 渲染修复策略枚举，与开发者选项页面中定义的保持一致
enum LinuxRenderFixMode {
  none, // 不使用任何修复
  invisibleMenu, // 使用不可见设置菜单
  forcedVulkan, // 强制使用Vulkan渲染
  forcedOpenGL, // 强制使用OpenGL渲染
  customColor, // 自定义背景色
}

/// 渲染修复服务，用于处理SteamDeck和Linux上的渲染问题
class RenderFixService {
  static const String _linuxRenderFixModeKey = 'linux_render_fix_mode';
  static const String _linuxRenderFixEnabledKey = 'linux_render_fix_enabled';
  static const String _steamdeckDetectedKey = 'steamdeck_detected';
  
  /// 单例实例
  static final RenderFixService _instance = RenderFixService._internal();
  
  /// 当前修复模式
  LinuxRenderFixMode? _currentMode;
  
  /// 是否已初始化
  bool _isInitialized = false;
  
  /// 是否在SteamDeck上运行
  bool _isSteamDeck = false;
  
  /// 工厂构造函数，返回单例实例
  factory RenderFixService() {
    return _instance;
  }
  
  /// 私有构造函数
  RenderFixService._internal();
  
  /// 当前修复模式
  LinuxRenderFixMode? get currentMode => _currentMode;
  
  /// 是否在SteamDeck上运行
  bool get isSteamDeck => _isSteamDeck;
  
  /// 检测是否是SteamDeck
  Future<bool> _detectSteamDeck() async {
    if (!Platform.isLinux) return false;
    
    final prefs = await SharedPreferences.getInstance();
    final isSteamDeck = prefs.getBool(_steamdeckDetectedKey) ?? false;
    
    if (isSteamDeck) return true;
    
    try {
      final result = await Process.run('cat', ['/etc/os-release']);
      final isSteamOS = result.stdout.toString().toLowerCase().contains('steamos');
      
      if (isSteamOS) {
        await prefs.setBool(_steamdeckDetectedKey, true);
        return true;
      }
    } catch (e) {
      debugPrint('检测SteamDeck失败: $e');
    }
    
    return false;
  }
  
  /// 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _isSteamDeck = await _detectSteamDeck();
      
      final prefs = await SharedPreferences.getInstance();
      final modeIndex = prefs.getInt(_linuxRenderFixModeKey) ?? 0;
      final isEnabled = prefs.getBool(_linuxRenderFixEnabledKey) ?? false;
      
      if (isEnabled && modeIndex >= 0 && modeIndex < LinuxRenderFixMode.values.length) {
        _currentMode = LinuxRenderFixMode.values[modeIndex];
        await _applyRenderFix(_currentMode!);
      } else {
        _currentMode = LinuxRenderFixMode.none;
      }
      
      _isInitialized = true;
      debugPrint('渲染修复服务初始化完成，当前模式: $_currentMode, 是否SteamDeck: $_isSteamDeck');
    } catch (e) {
      debugPrint('渲染修复服务初始化失败: $e');
    }
  }
  
  /// 设置修复模式
  Future<void> setRenderFixMode(LinuxRenderFixMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_linuxRenderFixModeKey, mode.index);
    await prefs.setBool(_linuxRenderFixEnabledKey, mode != LinuxRenderFixMode.none);
    
    _currentMode = mode;
    
    if (mode != LinuxRenderFixMode.none) {
      await _applyRenderFix(mode);
    }
  }
  
  /// 根据不同修复模式应用相应的修复方法
  Future<void> _applyRenderFix(LinuxRenderFixMode mode) async {
    if (!Platform.isLinux) return;
    
    try {
      switch (mode) {
        case LinuxRenderFixMode.invisibleMenu:
          // 由InvisibleSettingsMenu组件自动处理
          break;
          
        case LinuxRenderFixMode.forcedVulkan:
        case LinuxRenderFixMode.forcedOpenGL:
        case LinuxRenderFixMode.customColor:
          // MDK的全局选项需要在创建Player实例时设置
          // 所以这些设置将在configurePlayerInstance方法中处理
          break;
          
        default:
          // 不应用任何修复
          break;
      }
      
      debugPrint('已应用渲染修复模式: $mode');
    } catch (e) {
      debugPrint('应用渲染修复失败: $e');
    }
  }
  
  /// 配置Player实例的渲染参数
  void configurePlayerInstance(Player player) {
    if (!Platform.isLinux || _currentMode == null || _currentMode == LinuxRenderFixMode.none) {
      return;
    }
    
    try {
      // 所有模式都设置黑色背景，确保视频背景色正确
      player.setBackgroundColor(0.0, 0.0, 0.0, 1.0);
      
      switch (_currentMode) {
        case LinuxRenderFixMode.forcedVulkan:
          // 强制使用Vulkan渲染API
          // 注意：这些是示例配置，根据fvp/mdk文档调整参数
          try {
            // 创建VulkanRenderAPI对象
            // 这里需要根据fvp/mdk的实际API进行调整
          } catch (e) {
            debugPrint('配置Vulkan渲染API失败: $e');
          }
          break;
          
        case LinuxRenderFixMode.forcedOpenGL:
          // 强制使用OpenGL渲染API
          try {
            // 创建OpenGLRenderAPI对象
            // 这里需要根据fvp/mdk的实际API进行调整
          } catch (e) {
            debugPrint('配置OpenGL渲染API失败: $e');
          }
          break;
          
        case LinuxRenderFixMode.customColor:
        case LinuxRenderFixMode.invisibleMenu:
        default:
          // 已经设置了背景色，不需要其他操作
          break;
      }
    } catch (e) {
      debugPrint('配置Player实例渲染参数失败: $e');
    }
  }
} 