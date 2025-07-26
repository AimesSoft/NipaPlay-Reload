import 'package:flutter/material.dart';
import '../utils/hotkey_service.dart';

/// 热键服务初始化器，用于在应用程序启动时初始化HotkeyService
class HotkeyServiceInitializer {
  static final HotkeyServiceInitializer _instance = HotkeyServiceInitializer._internal();
  
  factory HotkeyServiceInitializer() {
    return _instance;
  }
  
  HotkeyServiceInitializer._internal();
  
  bool _isInitialized = false;
  
  /// 初始化热键服务
  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) return;
    
    await HotkeyService().initialize(context);
    _isInitialized = true;
  }
  
  /// 清理资源
  Future<void> dispose() async {
    if (!_isInitialized) return;
    
    await HotkeyService().dispose();
    _isInitialized = false;
  }
} 