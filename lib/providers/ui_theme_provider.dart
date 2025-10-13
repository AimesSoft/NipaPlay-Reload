import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

enum UIThemeType {
  nipaplay,
  fluentUI,
}

class UIThemeProvider extends ChangeNotifier {
  static const String _key = 'ui_theme_type';
  static const String _fluentThemeModeKey = 'fluent_theme_mode';
  UIThemeType _currentTheme = UIThemeType.nipaplay;
  ThemeMode _fluentThemeMode = ThemeMode.dark;
  bool _isInitialized = false;

  UIThemeType get currentTheme => _currentTheme;
  bool get isInitialized => _isInitialized;
  ThemeMode get fluentThemeMode => _fluentThemeMode;

  bool get isNipaplayTheme => _currentTheme == UIThemeType.nipaplay;
  bool get isFluentUITheme => _currentTheme == UIThemeType.fluentUI;

  UIThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt(_key) ?? 0;
      if (themeIndex >= 0 && themeIndex < UIThemeType.values.length) {
        _currentTheme = UIThemeType.values[themeIndex];
      }

      final storedMode = prefs.getString(_fluentThemeModeKey);
      if (storedMode != null) {
        _fluentThemeMode = _themeModeFromString(storedMode);
      }
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

  Future<void> setFluentThemeMode(ThemeMode mode) async {
    if (_fluentThemeMode != mode) {
      _fluentThemeMode = mode;
      notifyListeners();

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_fluentThemeModeKey, _themeModeToString(mode));
      } catch (e) {
        debugPrint('保存Fluent主题外观设置失败: $e');
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

  ThemeMode _themeModeFromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
