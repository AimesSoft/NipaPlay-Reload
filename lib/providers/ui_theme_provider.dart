import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';
import 'package:nipaplay/themes/theme_registry.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/platform_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UIThemeProvider extends ChangeNotifier {
  static const String _key = 'ui_theme_type';

  String _currentThemeId = ThemeRegistry.defaultThemeId;
  bool _isInitialized = false;
  final Map<String, Map<String, dynamic>> _themeSettings = {};

  bool get isInitialized => _isInitialized;

  ThemeDescriptor get currentThemeDescriptor =>
      ThemeRegistry.maybeGet(_currentThemeId) ?? ThemeRegistry.defaultTheme;

  String get currentThemeId => currentThemeDescriptor.id;

  bool get isNipaplayTheme => currentThemeId == ThemeIds.nipaplay;
  bool get isCupertinoTheme => currentThemeId == ThemeIds.cupertino;

  List<ThemeDescriptor> get availableThemes {
    final env = _currentEnvironment;
    final supported = ThemeRegistry.supportedThemes(env)
        .where((theme) => !theme.hiddenFromThemeOptions)
        .toList();
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
        isIOS: !kIsWeb && Platform.isIOS,
        isTablet: globals.isTablet,
      );

  Future<void> _loadTheme() async {
    _currentThemeId = _lockedThemeId(_currentEnvironment);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _currentThemeId);
    } catch (e) {
      debugPrint('加载UI主题设置失败: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setTheme(ThemeDescriptor descriptor) async {
    final lockedId = _lockedThemeId(_currentEnvironment);
    if (descriptor.id != lockedId) {
      debugPrint('UI theme is locked to $lockedId; ignoring ${descriptor.id}');
      return;
    }
    if (!descriptor.isSupported(_currentEnvironment)) {
      return;
    }
    if (_currentThemeId == lockedId) {
      return;
    }

    _currentThemeId = lockedId;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, lockedId);
    } catch (e) {
      debugPrint('保存UI主题设置失败: $e');
    }
  }

  String _lockedThemeId(ThemeEnvironment env) {
    if (env.isWeb) {
      return ThemeRegistry.resolveTheme(null, env).id;
    }
    return env.isPhone ? ThemeIds.cupertino : ThemeIds.nipaplay;
  }
}
