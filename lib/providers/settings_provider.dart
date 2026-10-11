import 'package:flutter/material.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/settings/application_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/l10n/app_locale_utils.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:nipaplay/utils/external_player_utils.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class SettingsProvider with ChangeNotifier {
  late SharedPreferences _prefs;
  late final Future<void> _settingsLoaded;

  // --- Settings ---
  double _blurPower = 0.0; // Default blur power (无模糊)
  static const double _defaultBlur = 0.0;
  static const String _blurPowerKey = 'blurPower';

  /// 电视设备上的模糊强度上限。
  ///
  /// 背景毛玻璃是一次全屏 BackdropFilter，每帧都要重算；glassmorphism 还会把
  /// 纵向 sigma 再乘以 2。低端电视 GPU（Mali-450 级别）在 σ≥50 时会明显掉帧，
  /// 因此即便用户此前在别的设备上存过更大的值，这里也要夹住。
  static const double _tvMaxBlurPower = 25.0;

  static double get _maxBlurPower =>
      globals.isTelevision ? _tvMaxBlurPower : 100.0;

  static double _clampBlurPower(double value) {
    if (value.isNaN) return _defaultBlur;
    return value.clamp(0.0, _maxBlurPower).toDouble();
  }

  // 弹幕转换简体中文设置
  bool _danmakuConvertToSimplified = true; // 默认开启
  bool _defaultDanmakuConvertToSimplified = true;
  // 哈希匹配失败后自动选择搜索第一个结果（避免弹窗）
  bool _autoMatchDanmakuFirstSearchResultOnHashFail = true; // 默认开启

  DanmakuAutoLoadStrategy _danmakuAutoLoadStrategy =
      DanmakuAutoLoadStrategy.remoteAndLocal;
  bool _skipDanmakuMatching = false;
  bool _fastPlaybackStartup = false;

  // 外部播放器设置
  bool _useExternalPlayer = false;
  String _externalPlayerPath = '';
  ExternalPlayerType _externalPlayerType = ExternalPlayerType.unset;
  bool _externalPlayerDanmakuOverlay = true; // 弹幕外挂默认开启
  bool _externalPlayerAutoSwitchToDanmakuConsole = true;
  bool _externalPlayerShrinkWindow = false;
  bool _externalPlayerConsoleWindowMode = false;

  // GitHub 代理设置
  String _githubProxyUrl = '';

  // 弹幕超采样设置：0.0=关闭, 1.5=1.5x, 2.0=2x
  double _danmakuSupersample = 0.0;

  // --- Getters ---
  double get blurPower => _blurPower;
  bool get isBlurEnabled => _blurPower > 0;
  bool get danmakuConvertToSimplified => _danmakuConvertToSimplified;
  bool get defaultDanmakuConvertToSimplified => _defaultDanmakuConvertToSimplified;
  bool get autoMatchDanmakuFirstSearchResultOnHashFail =>
      _autoMatchDanmakuFirstSearchResultOnHashFail;
  DanmakuAutoLoadStrategy get danmakuAutoLoadStrategy =>
      _danmakuAutoLoadStrategy;
  bool get skipDanmakuMatching => _skipDanmakuMatching;
  bool get fastPlaybackStartup => _fastPlaybackStartup;
  bool get useExternalPlayer => _useExternalPlayer;
  String get externalPlayerPath => _externalPlayerPath;
  ExternalPlayerType get externalPlayerType => _externalPlayerType;
  bool get externalPlayerDanmakuOverlay => _externalPlayerDanmakuOverlay;
  bool get externalPlayerAutoSwitchToDanmakuConsole =>
      _externalPlayerAutoSwitchToDanmakuConsole;
  bool get externalPlayerShrinkWindow => _externalPlayerShrinkWindow;
  bool get externalPlayerConsoleWindowMode => _externalPlayerConsoleWindowMode;
  String get githubProxyUrl => _githubProxyUrl;
  double get danmakuSupersample => _danmakuSupersample;

  SettingsProvider() {
    ApplicationSettings.settings = this;
    _defaultDanmakuConvertToSimplified =
        !AppLocaleUtils.isTraditionalChineseLocale(
            WidgetsBinding.instance.platformDispatcher.locale);
    // SharedPreferences loads asynchronously. Expose the correct platform
    // default immediately so iPad does not create a transient 2x texture and
    // rebuild it at 1.5x moments later during player startup.
    _danmakuSupersample = _defaultDanmakuSupersample();
    _settingsLoaded = _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    // Load blur power, defaulting to 0.0 if not set (无模糊)
    _blurPower = _clampBlurPower(
      _prefs.getDouble(_blurPowerKey) ?? _defaultBlur,
    );
    // 当用户仍为“自动语言”且系统为繁中时，首次默认关闭“弹幕转简体”。
    final languageMode =
        _prefs.getString(SettingsKeys.appLanguageMode) ?? 'auto';
    _defaultDanmakuConvertToSimplified = languageMode != 'auto' ||
        !AppLocaleUtils.isTraditionalChineseLocale(
            WidgetsBinding.instance.platformDispatcher.locale);
    _danmakuConvertToSimplified =
        _prefs.getBool(SettingsKeys.danmakuConvertToSimplified) ??
            _defaultDanmakuConvertToSimplified;
    _autoMatchDanmakuFirstSearchResultOnHashFail = _prefs.getBool(
            SettingsKeys.autoMatchDanmakuFirstSearchResultOnHashFail) ??
        true;
    final persistedStrategy =
        _prefs.getString(SettingsKeys.danmakuAutoLoadStrategy);
    final danmakuAutoLoadSettings = resolveDanmakuAutoLoadSettings(
      persistedStrategy: persistedStrategy,
      persistedSkipMatching: _prefs.getBool(SettingsKeys.skipDanmakuMatching),
      legacyAutoMatchOnPlay:
          _prefs.getBool(SettingsKeys.autoMatchDanmakuOnPlay),
    );
    _danmakuAutoLoadStrategy = danmakuAutoLoadSettings.strategy;
    _skipDanmakuMatching = danmakuAutoLoadSettings.skipMatching;
    _fastPlaybackStartup =
        _prefs.getBool(SettingsKeys.fastPlaybackStartup) ?? false;
    if (persistedStrategy != _danmakuAutoLoadStrategy.prefsValue) {
      await SettingsAccess.persist(SettingsKeys.danmakuAutoLoadStrategy, () => _prefs.setString(
        SettingsKeys.danmakuAutoLoadStrategy,
        _danmakuAutoLoadStrategy.prefsValue,
      ), migration: true);
    }
    if (!_prefs.containsKey(SettingsKeys.skipDanmakuMatching)) {
      await SettingsAccess.persist(SettingsKeys.skipDanmakuMatching, () => _prefs.setBool(
        SettingsKeys.skipDanmakuMatching,
        _skipDanmakuMatching,
      ), migration: true);
    }
    _useExternalPlayer =
        _prefs.getBool(SettingsKeys.useExternalPlayer) ?? false;
    _externalPlayerPath =
        _prefs.getString(SettingsKeys.externalPlayerPath) ?? '';
    final savedExternalPlayerType =
        _prefs.getString(SettingsKeys.externalPlayerType);
    if (savedExternalPlayerType == null) {
      _externalPlayerType = _externalPlayerPath.isEmpty
          ? ExternalPlayerType.unset
          : detectExternalPlayerType(_externalPlayerPath);
      await SettingsAccess.persist(SettingsKeys.externalPlayerType, () => _prefs.setString(
        SettingsKeys.externalPlayerType,
        _externalPlayerType.name,
      ), migration: true);
    } else {
      _externalPlayerType = ExternalPlayerType.values.firstWhere(
        (type) => type.name == savedExternalPlayerType,
        orElse: () => ExternalPlayerType.unset,
      );
    }
    _externalPlayerDanmakuOverlay =
        _prefs.getBool(SettingsKeys.externalPlayerDanmakuOverlay) ?? true;
    _externalPlayerAutoSwitchToDanmakuConsole =
        _prefs.getBool(SettingsKeys.externalPlayerAutoSwitchToDanmakuConsole) ??
            true;
    _externalPlayerShrinkWindow =
        _prefs.getBool(SettingsKeys.externalPlayerShrinkWindow) ?? false;
    _externalPlayerConsoleWindowMode =
        _prefs.getBool(SettingsKeys.externalPlayerConsoleWindowMode) ?? false;
    _githubProxyUrl = _prefs.getString(SettingsKeys.githubProxyUrl) ?? '';
    // 弹幕超采样：iPad 默认 1.5x；其他平板和低 DPR 桌面设备维持 2x。
    // 已保存过设置的用户继续使用其现有值，仅影响首次默认值。
    final savedSupersample =
        _parseDanmakuSupersample(_prefs.get(SettingsKeys.danmakuSupersampleV2)) ??
            _parseDanmakuSupersample(
                _prefs.get(SettingsKeys.danmakuSupersample));
    _danmakuSupersample = savedSupersample ?? _defaultDanmakuSupersample();
    if (savedSupersample != null) {
      await SettingsAccess.persist(SettingsKeys.danmakuSupersampleV2, () => _prefs.setString(
        SettingsKeys.danmakuSupersampleV2,
        savedSupersample.toStringAsFixed(1),
      ), migration: true);
    }
    notifyListeners();
  }

  Future<void> get ready => _settingsLoaded;

  @override
  void dispose() {
    if (identical(ApplicationSettings.settings, this)) ApplicationSettings.settings = null;
    super.dispose();
  }

  // --- Setters ---

  /// 判断当前设备默认 DPR 是否低于 2.0
  static bool _defaultDprBelow2() {
    try {
      final dpr = WidgetsBinding
          .instance.platformDispatcher.views.first.devicePixelRatio;
      return dpr < 2.0;
    } catch (_) {
      return false;
    }
  }

  static double _defaultDanmakuSupersample() {
    if (globals.isIPad) {
      return 1.5;
    }
    if (globals.isTablet || (globals.isDesktop && _defaultDprBelow2())) {
      return 2.0;
    }
    return 0.0;
  }

  static double? _parseDanmakuSupersample(Object? value) {
    // 字符串键明确区分“关闭”和未保存；兼容旧数值/开关存档。
    final parsed = value is bool
        ? (value ? 2.0 : 0.0)
        : value is num
            ? value.toDouble()
            : value is String
                ? double.tryParse(value)
                : null;
    return parsed == 0.0 || parsed == 1.5 || parsed == 2.0 ? parsed : null;
  }

  /// Toggles the background blur effect.
  ///
  /// If `enable` is true, blurPower is set to a medium blur value.
  /// If `enable` is false, blurPower is set to 0.
  Future<void> setBlurEnabled(bool enable) async {
    _blurPower = enable ? 10.0 : 0.0; // 开启时使用中等模糊强度
    await SettingsAccess.persist(_blurPowerKey, () => _prefs.setDouble(_blurPowerKey, _blurPower));
    notifyListeners();
  }

  /// Sets a specific blur power value.
  Future<void> setBlurPower(double value) async {
    _blurPower = _clampBlurPower(value);
    await SettingsAccess.persist(_blurPowerKey, () => _prefs.setDouble(_blurPowerKey, _blurPower));
    notifyListeners();
  }

  /// Sets the danmaku convert to simplified Chinese setting.
  Future<void> setDanmakuConvertToSimplified(bool enable) async {
    _danmakuConvertToSimplified = enable;
    await SettingsAccess.persist(SettingsKeys.danmakuConvertToSimplified, () => _prefs.setBool(
        SettingsKeys.danmakuConvertToSimplified, _danmakuConvertToSimplified));
    notifyListeners();
  }

  Future<void> setAutoMatchDanmakuFirstSearchResultOnHashFail(
      bool enable) async {
    _autoMatchDanmakuFirstSearchResultOnHashFail = enable;
    await SettingsAccess.persist(SettingsKeys.autoMatchDanmakuFirstSearchResultOnHashFail, () => _prefs.setBool(
      SettingsKeys.autoMatchDanmakuFirstSearchResultOnHashFail,
      _autoMatchDanmakuFirstSearchResultOnHashFail,
    ));
    notifyListeners();
  }

  Future<void> setDanmakuAutoLoadStrategy(
      DanmakuAutoLoadStrategy strategy) async {
    if (strategy == DanmakuAutoLoadStrategy.manual) {
      await setSkipDanmakuMatching(true);
      return;
    }
    if (_danmakuAutoLoadStrategy == strategy) return;
    _danmakuAutoLoadStrategy = strategy;
    await SettingsAccess.persist(SettingsKeys.danmakuAutoLoadStrategy, () => _prefs.setString(
      SettingsKeys.danmakuAutoLoadStrategy,
      _danmakuAutoLoadStrategy.prefsValue,
    ));
    notifyListeners();
  }

  Future<void> setSkipDanmakuMatching(bool skip) async {
    if (_skipDanmakuMatching == skip) return;
    _skipDanmakuMatching = skip;
    await SettingsAccess.persist(SettingsKeys.skipDanmakuMatching, () => _prefs.setBool(SettingsKeys.skipDanmakuMatching, skip));
    notifyListeners();
  }

  Future<void> setFastPlaybackStartup(bool enable) async {
    if (_fastPlaybackStartup == enable) return;
    _fastPlaybackStartup = enable;
    await SettingsAccess.persist(SettingsKeys.fastPlaybackStartup, () => _prefs.setBool(SettingsKeys.fastPlaybackStartup, enable));
    notifyListeners();
  }

  Future<void> setUseExternalPlayer(bool enable) async {
    _useExternalPlayer = enable;
    await SettingsAccess.persist(SettingsKeys.useExternalPlayer, () => _prefs.setBool(
      SettingsKeys.useExternalPlayer,
      _useExternalPlayer,
    ));
    notifyListeners();
  }

  Future<void> setExternalPlayerPath(String path) async {
    _externalPlayerPath = path.trim();
    await SettingsAccess.persist(SettingsKeys.externalPlayerPath, () => _prefs.setString(
      SettingsKeys.externalPlayerPath,
      _externalPlayerPath,
    ));
    notifyListeners();
  }

  Future<void> setExternalPlayerType(ExternalPlayerType type) async {
    if (_externalPlayerType == type) return;
    _externalPlayerType = type;
    await SettingsAccess.persist(SettingsKeys.externalPlayerType, () => _prefs.setString(SettingsKeys.externalPlayerType, type.name));
    notifyListeners();
  }

  Future<void> setExternalPlayerDanmakuOverlay(bool enable) async {
    if (_externalPlayerDanmakuOverlay == enable) return;
    _externalPlayerDanmakuOverlay = enable;
    await SettingsAccess.persist(SettingsKeys.externalPlayerDanmakuOverlay, () => _prefs.setBool(
      SettingsKeys.externalPlayerDanmakuOverlay,
      _externalPlayerDanmakuOverlay,
    ));
    notifyListeners();
  }

  Future<void> setExternalPlayerAutoSwitchToDanmakuConsole(bool enable) async {
    if (_externalPlayerAutoSwitchToDanmakuConsole == enable) return;
    _externalPlayerAutoSwitchToDanmakuConsole = enable;

    await SettingsAccess.persist(SettingsKeys.externalPlayerAutoSwitchToDanmakuConsole, () => _prefs.setBool(
      SettingsKeys.externalPlayerAutoSwitchToDanmakuConsole,
      _externalPlayerAutoSwitchToDanmakuConsole,
    ));

    notifyListeners();
  }

  Future<void> setExternalPlayerShrinkWindow(bool enable) async {
    if (_externalPlayerShrinkWindow == enable) return;
    _externalPlayerShrinkWindow = enable;
    await SettingsAccess.persist(SettingsKeys.externalPlayerShrinkWindow, () => _prefs.setBool(
      SettingsKeys.externalPlayerShrinkWindow,
      _externalPlayerShrinkWindow,
    ));
    notifyListeners();
  }

  Future<void> setExternalPlayerConsoleWindowMode(bool enable) async {
    if (_externalPlayerConsoleWindowMode == enable) return;
    _externalPlayerConsoleWindowMode = enable;
    await SettingsAccess.persist(SettingsKeys.externalPlayerConsoleWindowMode, () => _prefs.setBool(
      SettingsKeys.externalPlayerConsoleWindowMode,
      _externalPlayerConsoleWindowMode,
    ));
    notifyListeners();
  }

  Future<void> setGithubProxyUrl(String url) async {
    _githubProxyUrl = url.trim();
    await SettingsAccess.persist(SettingsKeys.githubProxyUrl, () => _prefs.setString(
      SettingsKeys.githubProxyUrl,
      _githubProxyUrl,
    ));
    notifyListeners();
  }

  Future<void> setDanmakuSupersample(double value) async {
    if (_parseDanmakuSupersample(value) == null) return;
    // 等待首轮加载，避免设置尚未初始化或后到的默认值覆盖用户选择。
    await _settingsLoaded;
    _danmakuSupersample = value;
    await SettingsAccess.persist(SettingsKeys.danmakuSupersampleV2, () => _prefs.setString(
      SettingsKeys.danmakuSupersampleV2,
      value.toStringAsFixed(1),
    ));
    await SettingsAccess.persist(SettingsKeys.danmakuSupersample, () => _prefs.setDouble(SettingsKeys.danmakuSupersample, value));
    notifyListeners();
  }
}
