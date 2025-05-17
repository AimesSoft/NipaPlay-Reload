import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class AppearanceSettingsProvider extends ChangeNotifier {
  static const String _enablePageAnimationKey = 'enable_page_animation';
  
  // 默认值根据平台决定
  late bool _enablePageAnimation;
  
  // 获取是否启用页面滑动动画
  bool get enablePageAnimation => _enablePageAnimation;
  
  // 构造函数
  AppearanceSettingsProvider() {
    // 初始化默认值：移动端启用，桌面端禁用
    _enablePageAnimation = _getDefaultAnimationValue();
    _loadSettings();
  }
  
  // 根据平台返回默认动画设置
  bool _getDefaultAnimationValue() {
    // 在移动端设备上默认启用动画
    if (Platform.isIOS || Platform.isAndroid) {
      return true;
    }
    // 在桌面端设备上默认禁用动画
    else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return false;
    }
    // 其他未知平台，默认禁用
    return false;
  }
  
  // 从SharedPreferences加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 从存储加载时使用平台相关的默认值
      _enablePageAnimation = prefs.getBool(_enablePageAnimationKey) ?? _getDefaultAnimationValue();
      notifyListeners();
    } catch (e) {
      debugPrint('加载外观设置时出错: $e');
    }
  }
  
  // 设置是否启用页面滑动动画
  Future<void> setEnablePageAnimation(bool value) async {
    if (_enablePageAnimation == value) return;
    
    _enablePageAnimation = value;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enablePageAnimationKey, value);
    } catch (e) {
      debugPrint('保存外观设置时出错: $e');
    }
  }
} 