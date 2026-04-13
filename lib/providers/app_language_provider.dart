import 'package:flutter/widgets.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/l10n/app_locale_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguageMode {
  auto,
  simplifiedChinese,
  traditionalChinese,
}

class AppLanguageProvider with ChangeNotifier {
  late final SharedPreferences _prefs;
  Future<void>? _loadFuture;
  bool _initialized = false;

  AppLanguageMode _mode = AppLanguageMode.auto;
  Locale _resolvedLocale = AppLocaleUtils.simplifiedChinese;

  AppLanguageMode get mode => _mode;
  Locale get locale => _resolvedLocale;
  bool get isAuto => _mode == AppLanguageMode.auto;

  AppLanguageProvider() {
    _loadFuture = _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    _mode = _modeFromStorage(_prefs.getString(SettingsKeys.appLanguageMode));
    _resolvedLocale = _resolveLocale();
    _initialized = true;
    notifyListeners();
  }

  Future<void> setMode(AppLanguageMode mode) async {
    if (!_initialized) {
      await _loadFuture;
    }
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    _resolvedLocale = _resolveLocale();
    await _prefs.setString(SettingsKeys.appLanguageMode, _modeToStorage(mode));
    notifyListeners();
  }

  void refreshSystemLocale([Locale? systemLocale]) {
    if (!isAuto) {
      return;
    }
    final nextLocale = AppLocaleUtils.resolveLocaleFromSystem(
      systemLocale ?? WidgetsBinding.instance.platformDispatcher.locale,
    );
    if (nextLocale == _resolvedLocale) {
      return;
    }
    _resolvedLocale = nextLocale;
    notifyListeners();
  }

  Locale _resolveLocale() {
    switch (_mode) {
      case AppLanguageMode.simplifiedChinese:
        return AppLocaleUtils.simplifiedChinese;
      case AppLanguageMode.traditionalChinese:
        return AppLocaleUtils.traditionalChinese;
      case AppLanguageMode.auto:
        return AppLocaleUtils.resolveLocaleFromSystem(
          WidgetsBinding.instance.platformDispatcher.locale,
        );
    }
  }

  static AppLanguageMode _modeFromStorage(String? value) {
    switch (value) {
      case 'simplified':
        return AppLanguageMode.simplifiedChinese;
      case 'traditional':
        return AppLanguageMode.traditionalChinese;
      case 'auto':
      default:
        return AppLanguageMode.auto;
    }
  }

  static String _modeToStorage(AppLanguageMode mode) {
    switch (mode) {
      case AppLanguageMode.simplifiedChinese:
        return 'simplified';
      case AppLanguageMode.traditionalChinese:
        return 'traditional';
      case AppLanguageMode.auto:
        return 'auto';
    }
  }
}
