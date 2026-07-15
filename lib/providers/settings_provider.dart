import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/l10n/app_locale_utils.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class SettingsProvider with ChangeNotifier {
  late SharedPreferences _prefs;

  // --- Settings ---
  double _blurPower = 0.0; // Default blur power (无模糊)
  static const double _defaultBlur = 0.0;
  static const String _blurPowerKey = 'blurPower';

  // 弹幕转换简体中文设置
  bool _danmakuConvertToSimplified = true; // 默认开启
  // 哈希匹配失败后自动选择搜索第一个结果（避免弹窗）
  bool _autoMatchDanmakuFirstSearchResultOnHashFail = true; // 默认开启

  // 播放时自动匹配弹幕
  bool _autoMatchDanmakuOnPlay = true; // 默认开启
  DanmakuAutoLoadStrategy _danmakuAutoLoadStrategy =
      DanmakuAutoLoadStrategy.remoteAndLocal;

  // 外部播放器设置
  bool _useExternalPlayer = false;
  String _externalPlayerPath = '';
  bool _externalPlayerDanmakuOverlay = true; // 弹幕外挂默认开启
  bool _externalPlayerAutoSwitchToDanmakuConsole = true;

  // GitHub 代理设置
  String _githubProxyUrl = '';

  // 弹幕超采样设置：0.0=关闭, 1.5=1.5x, 2.0=2x
  double _danmakuSupersample = 2.0; // 默认值在 _loadSettings 中根据设备类型决定

  // --- Getters ---
  double get blurPower => _blurPower;
  bool get isBlurEnabled => _blurPower > 0;
  bool get danmakuConvertToSimplified => _danmakuConvertToSimplified;
  bool get autoMatchDanmakuFirstSearchResultOnHashFail =>
      _autoMatchDanmakuFirstSearchResultOnHashFail;
  bool get autoMatchDanmakuOnPlay => _autoMatchDanmakuOnPlay;
  DanmakuAutoLoadStrategy get danmakuAutoLoadStrategy =>
      _danmakuAutoLoadStrategy;
  bool get useExternalPlayer => _useExternalPlayer;
  String get externalPlayerPath => _externalPlayerPath;
  bool get externalPlayerDanmakuOverlay => _externalPlayerDanmakuOverlay;
  bool get externalPlayerAutoSwitchToDanmakuConsole => _externalPlayerAutoSwitchToDanmakuConsole;
  String get githubProxyUrl => _githubProxyUrl;
  double get danmakuSupersample => _danmakuSupersample;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    // Load blur power, defaulting to 0.0 if not set (无模糊)
    _blurPower = _prefs.getDouble(_blurPowerKey) ?? _defaultBlur;
    // 当用户仍为“自动语言”且系统为繁中时，首次默认关闭“弹幕转简体”。
    final savedDanmakuConvert = _prefs.getBool(SettingsKeys.danmakuConvertToSimplified);
    if (savedDanmakuConvert != null) {
      _danmakuConvertToSimplified = savedDanmakuConvert;
    } else {
      final languageMode = _prefs.getString(SettingsKeys.appLanguageMode) ?? 'auto';
      if (languageMode == 'auto') {
        final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
        _danmakuConvertToSimplified =
            !AppLocaleUtils.isTraditionalChineseLocale(systemLocale);
      } else {
        _danmakuConvertToSimplified = true;
      }
    }
    _autoMatchDanmakuFirstSearchResultOnHashFail =
        _prefs.getBool(SettingsKeys.autoMatchDanmakuFirstSearchResultOnHashFail) ??
            true;
    final savedAutoMatchDanmakuOnPlay =
        _prefs.getBool(SettingsKeys.autoMatchDanmakuOnPlay);
    _autoMatchDanmakuOnPlay = savedAutoMatchDanmakuOnPlay ?? true;
    _danmakuAutoLoadStrategy = danmakuAutoLoadStrategyFromPrefs(
      _prefs.getString(SettingsKeys.danmakuAutoLoadStrategy),
      legacyAutoMatchOnPlay: _autoMatchDanmakuOnPlay,
    );
    if (!_prefs.containsKey(SettingsKeys.danmakuAutoLoadStrategy)) {
      await _prefs.setString(
        SettingsKeys.danmakuAutoLoadStrategy,
        _danmakuAutoLoadStrategy.prefsValue,
      );
    }
    _useExternalPlayer =
        _prefs.getBool(SettingsKeys.useExternalPlayer) ?? false;
    _externalPlayerPath =
        _prefs.getString(SettingsKeys.externalPlayerPath) ?? '';
    _externalPlayerDanmakuOverlay =
        _prefs.getBool(SettingsKeys.externalPlayerDanmakuOverlay) ?? true;
    _externalPlayerAutoSwitchToDanmakuConsole = _prefs.getBool(SettingsKeys.externalPlayerAutoSwitchToDanmakuConsole) ?? true;
    _githubProxyUrl =
        _prefs.getString(SettingsKeys.githubProxyUrl) ?? '';
    // 弹幕超采样：默认对平板和低 DPR 桌面设备开启 2x
    final defaultSupersample =
        globals.isTablet || (globals.isDesktop && _defaultDprBelow2()) ? 2.0 : 0.0;
    _danmakuSupersample =
        _prefs.getDouble(SettingsKeys.danmakuSupersample) ?? defaultSupersample;
    notifyListeners();
  }

  // --- Setters ---

  /// 判断当前设备默认 DPR 是否低于 2.0
  static bool _defaultDprBelow2() {
    try {
      final dpr = WidgetsBinding.instance.platformDispatcher.views.first
          .devicePixelRatio;
      return dpr < 2.0;
    } catch (_) {
      return false;
    }
  }

  /// Toggles the background blur effect.
  ///
  /// If `enable` is true, blurPower is set to a medium blur value.
  /// If `enable` is false, blurPower is set to 0.
  Future<void> setBlurEnabled(bool enable) async {
    _blurPower = enable ? 10.0 : 0.0; // 开启时使用中等模糊强度
    await _prefs.setDouble(_blurPowerKey, _blurPower);
    notifyListeners();
  }

  /// Sets a specific blur power value.
  Future<void> setBlurPower(double value) async {
    _blurPower = value;
    await _prefs.setDouble(_blurPowerKey, _blurPower);
    notifyListeners();
  }

  /// Sets the danmaku convert to simplified Chinese setting.
  Future<void> setDanmakuConvertToSimplified(bool enable) async {
    _danmakuConvertToSimplified = enable;
    await _prefs.setBool(SettingsKeys.danmakuConvertToSimplified, _danmakuConvertToSimplified);
    notifyListeners();
  }

  Future<void> setAutoMatchDanmakuFirstSearchResultOnHashFail(
      bool enable) async {
    _autoMatchDanmakuFirstSearchResultOnHashFail = enable;
    await _prefs.setBool(
      SettingsKeys.autoMatchDanmakuFirstSearchResultOnHashFail,
      _autoMatchDanmakuFirstSearchResultOnHashFail,
    );
    notifyListeners();
  }

  Future<void> setAutoMatchDanmakuOnPlay(bool enable) async {
    _autoMatchDanmakuOnPlay = enable;
    _danmakuAutoLoadStrategy = enable
        ? DanmakuAutoLoadStrategy.remoteAndLocal
        : DanmakuAutoLoadStrategy.manual;
    await _prefs.setBool(
      SettingsKeys.autoMatchDanmakuOnPlay,
      _autoMatchDanmakuOnPlay,
    );
    await _prefs.setString(
      SettingsKeys.danmakuAutoLoadStrategy,
      _danmakuAutoLoadStrategy.prefsValue,
    );
    notifyListeners();
  }

  Future<void> setDanmakuAutoLoadStrategy(
      DanmakuAutoLoadStrategy strategy) async {
    if (_danmakuAutoLoadStrategy == strategy) return;
    _danmakuAutoLoadStrategy = strategy;
    _autoMatchDanmakuOnPlay = strategy == DanmakuAutoLoadStrategy.remote ||
        strategy == DanmakuAutoLoadStrategy.remoteAndLocal;
    await _prefs.setString(
      SettingsKeys.danmakuAutoLoadStrategy,
      _danmakuAutoLoadStrategy.prefsValue,
    );
    await _prefs.setBool(
      SettingsKeys.autoMatchDanmakuOnPlay,
      _autoMatchDanmakuOnPlay,
    );
    notifyListeners();
  }

  Future<void> setUseExternalPlayer(bool enable) async {
    _useExternalPlayer = enable;
    await _prefs.setBool(
      SettingsKeys.useExternalPlayer,
      _useExternalPlayer,
    );
    notifyListeners();
  }

  Future<void> setExternalPlayerPath(String path) async {
    _externalPlayerPath = path.trim();
    await _prefs.setString(
      SettingsKeys.externalPlayerPath,
      _externalPlayerPath,
    );
    notifyListeners();
  }

  Future<void> setExternalPlayerDanmakuOverlay(bool enable) async {
    if (_externalPlayerDanmakuOverlay == enable) return;
    _externalPlayerDanmakuOverlay = enable;
    await _prefs.setBool(
      SettingsKeys.externalPlayerDanmakuOverlay,
      _externalPlayerDanmakuOverlay,
    );
    notifyListeners();
  }

  Future<void> setExternalPlayerAutoSwitchToDanmakuConsole(bool enable) async {

    if   ( _externalPlayerAutoSwitchToDanmakuConsole == enable) { return; }
    else { _externalPlayerAutoSwitchToDanmakuConsole =  enable; }

    await _prefs.setBool(
      SettingsKeys.externalPlayerAutoSwitchToDanmakuConsole,
      _externalPlayerAutoSwitchToDanmakuConsole,
    );

    notifyListeners();
  }

  Future<void> setGithubProxyUrl(String url) async {
    _githubProxyUrl = url.trim();
    await _prefs.setString(
      SettingsKeys.githubProxyUrl,
      _githubProxyUrl,
    );
    notifyListeners();
  }

  Future<void> setDanmakuSupersample(double value) async {
    _danmakuSupersample = value;
    await _prefs.setDouble(SettingsKeys.danmakuSupersample, value);
    notifyListeners();
  }

}
