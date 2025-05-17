import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppearanceSettingsProvider extends ChangeNotifier {
  static const String _enablePageAnimationKey = 'enable_page_animation';
  
  // 默认值为true，即默认使用PageView
  bool _enablePageAnimation = true;
  
  // 获取是否启用页面滑动动画
  bool get enablePageAnimation => _enablePageAnimation;
  
  // 构造函数
  AppearanceSettingsProvider() {
    _loadSettings();
  }
  
  // 从SharedPreferences加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enablePageAnimation = prefs.getBool(_enablePageAnimationKey) ?? true;
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