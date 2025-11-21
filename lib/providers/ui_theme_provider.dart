import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';
import 'package:nipaplay/themes/theme_registry.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:shared_preferences/shared_preferences.dart';

class UIThemeProvider extends ChangeNotifier {
  static const String _key = 'ui_theme_type';
  static const String _fluentThemeModeKey = 'fluent_theme_mode';

  String _currentThemeId = ThemeRegistry.defaultThemeId;
  bool _isInitialized = false;
  ThemeMode _fluentThemeMode = ThemeMode.dark;
  final Map<String, Map<String, dynamic>> _themeSettings = {};

  bool get isInitialized => _isInitialized;

  ThemeDescriptor get currentThemeDescriptor =>
      ThemeRegistry.maybeGet(_currentThemeId) ?? ThemeRegistry.defaultTheme;

  String get currentThemeId => currentThemeDescriptor.id;

  bool get isNipaplayTheme => currentThemeId == ThemeIds.nipaplay;
  bool get isFluentUITheme => currentThemeId == ThemeIds.fluent;
  bool get isCupertinoTheme => currentThemeId == ThemeIds.cupertino;

  ThemeMode get fluentThemeMode => _fluentThemeMode;

  List<ThemeDescriptor> get availableThemes {
    final env = _currentEnvironment;
    final supported = ThemeRegistry.supportedThemes(env);
    final containsCurrent =
        supported.any((theme) => theme.id == currentThemeId);
    if (!containsCurrent) {
      return [...supported, currentThemeDescriptor];
    }
    return supported;
  }

  Map<String, dynamic> get currentThemeSettings =>
      UnmodifiableMapView(_themeSettings[currentThemeId] ?? const {});

  UIThemeProvider() {
    _loadTheme();
  }

  ThemeEnvironment get _currentEnvironment => ThemeEnvironment(
        isDesktop: globals.isDesktop,
        isPhone: globals.isPhone,
        isWeb: kIsWeb,
      );

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getString(_key);
      final env = _currentEnvironment;
      _currentThemeId = ThemeRegistry.resolveTheme(storedId, env).id;

      final storedMode = prefs.getString(_fluentThemeModeKey);
      if (storedMode != null) {
        _fluentThemeMode = _themeModeFromString(storedMode);
      }
      _ensureThemeSettings(ThemeIds.fluent)['fluentThemeMode'] =
          _fluentThemeMode;
    } catch (e) {
      debugPrint('加载UI主题设置失败: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setTheme(ThemeDescriptor descriptor) async {
    if (!descriptor.isSupported(_currentEnvironment)) {
      return;
    }
    if (_currentThemeId == descriptor.id) {
      return;
    }

    _currentThemeId = descriptor.id;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, descriptor.id);
    } catch (e) {
      debugPrint('保存UI主题设置失败: $e');
    }
  }

  Future<void> setFluentThemeMode(ThemeMode mode) async {
    if (_fluentThemeMode == mode) return;

    _fluentThemeMode = mode;
    _ensureThemeSettings(ThemeIds.fluent)['fluentThemeMode'] = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fluentThemeModeKey, _themeModeToString(mode));
    } catch (e) {
      debugPrint('保存Fluent主题外观设置失败: $e');
    }
  }

  Map<String, dynamic> _ensureThemeSettings(String themeId) {
    return _themeSettings.putIfAbsent(themeId, () => {});
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
