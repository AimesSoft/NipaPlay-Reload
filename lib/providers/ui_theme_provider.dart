import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UIThemeType {
  nipaplay,
  fluentUI,
}

class UIThemeProvider extends ChangeNotifier {
  static const String _key = 'ui_theme_type';
  UIThemeType _currentTheme = UIThemeType.nipaplay;
  bool _isInitialized = false;

  UIThemeType get currentTheme => _currentTheme;
  bool get isInitialized => _isInitialized;

  bool get isNipaplayTheme => _currentTheme == UIThemeType.nipaplay;
  bool get isFluentUITheme => _currentTheme == UIThemeType.fluentUI;

  UIThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt(_key) ?? 0;
      _currentTheme = UIThemeType.values[themeIndex];
    } catch (e) {
      debugPrint('加载UI主题设置失败: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setTheme(UIThemeType theme) async {
    if (_currentTheme != theme) {
      _currentTheme = theme;
      notifyListeners();
      
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_key, theme.index);
      } catch (e) {
        debugPrint('保存UI主题设置失败: $e');
      }
    }
  }

  String getThemeName(UIThemeType theme) {
    switch (theme) {
      case UIThemeType.nipaplay:
        return 'NipaPlay';
      case UIThemeType.fluentUI:
        return 'Fluent UI';
    }
  }
}