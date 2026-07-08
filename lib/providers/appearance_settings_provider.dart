import 'package:flutter/painting.dart' show TextOverflow;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/app_accent_color.dart';

// 定义番剧卡片点击行为的枚举
enum AnimeCardAction {
  synopsis, // 简介
  episodeList, // 剧集列表
}

// 定义最近观看显示样式的枚举
enum RecentWatchingStyle {
  simple, // 简洁版（无截图）
  detailed, // 详细版（带截图）
}

// 定义 桌面和平板布局弹窗显示区域模式
enum NipaplayWindowDisplayMode {
  windowed, // 窗口化
  filledScreen, // 铺满屏幕（保留少量边距）
}

// 定义媒体库管理中目录名称的显示模式
enum FolderNameDisplayMode {
  ellipsis, // 省略号截断（默认，当前机制）
  multiline, // 多行完整显示
}

class AppearanceSettingsProvider extends ChangeNotifier {
  static const String _widgetBlurEffectKey = 'enable_widget_blur_effect';
  static const String _animeCardActionKey = 'anime_card_action';
  static const String _showDanmakuDensityKey = 'show_danmaku_density_chart';
  static const String _recentWatchingStyleKey = 'recent_watching_style';
  static const String _uiScaleKey = 'ui_scale_factor';
  static const String _showAnimeCardSummaryKey = 'show_anime_card_summary';
  static const String _windowDisplayModeKey = 'nipaplay_window_display_mode';
  static const String _accentColorPresetKey = 'app_accent_color_preset';
  static const String _folderNameDisplayModeKey = 'folder_name_display_mode';

  static const double uiScaleMin = 1.0;
  static const double uiScaleMax = 1.3;
  static const double uiScaleStep = 0.05;
  static const double defaultUiScale = 1.0;
  static const double defaultTabletUiScale = 1.2;

  late AnimeCardAction _animeCardAction;
  late bool _showDanmakuDensityChart;
  late RecentWatchingStyle _recentWatchingStyle;
  late double _uiScale;
  late bool _showAnimeCardSummary;
  late NipaplayWindowDisplayMode _windowDisplayMode;
  late AppAccentColorPreset _accentColorPreset;
  late FolderNameDisplayMode _folderNameDisplayMode;

  // 获取设置值
  // 页面滑动动画始终启用
  bool get enablePageAnimation => true;

  bool get enableWidgetBlurEffect => false;
  AnimeCardAction get animeCardAction => _animeCardAction;
  bool get showDanmakuDensityChart => _showDanmakuDensityChart;
  RecentWatchingStyle get recentWatchingStyle => _recentWatchingStyle;
  double get uiScale => _uiScale;
  bool get showAnimeCardSummary => _showAnimeCardSummary;
  NipaplayWindowDisplayMode get windowDisplayMode => _windowDisplayMode;
  AppAccentColorPreset get accentColorPreset => _accentColorPreset;
  FolderNameDisplayMode get folderNameDisplayMode => _folderNameDisplayMode;

  /// 目录名称最大行数：省略号模式为 1，多行模式为 null（不限制，完整显示）
  int? get folderNameMaxLines =>
      _folderNameDisplayMode == FolderNameDisplayMode.ellipsis ? 1 : null;

  /// 目录名称溢出处理：省略号模式为 ellipsis，多行模式为 visible
  TextOverflow get folderNameOverflow =>
      _folderNameDisplayMode == FolderNameDisplayMode.ellipsis
          ? TextOverflow.ellipsis
          : TextOverflow.visible;

  // 构造函数
  AppearanceSettingsProvider() {
    // 初始化默认值
    _animeCardAction = AnimeCardAction.synopsis; // 默认行为是显示简介
    _showDanmakuDensityChart = true; // 默认显示弹幕密度曲线图
    _recentWatchingStyle = RecentWatchingStyle.simple; // 默认简洁版
    _uiScale = _resolveDefaultUiScale();
    _showAnimeCardSummary = true; // 默认显示番剧卡片简介
    _windowDisplayMode = _resolveDefaultWindowDisplayMode();
    _accentColorPreset = AppAccentColorPreset.rose;
    _folderNameDisplayMode = FolderNameDisplayMode.ellipsis;
    AppAccentColors.setCurrent(_accentColorPreset);
    _loadSettings();
  }

  double _resolveDefaultUiScale() {
    if (kIsWeb) {
      return defaultUiScale;
    }
    return globals.isTablet ? defaultTabletUiScale : defaultUiScale;
  }

  NipaplayWindowDisplayMode _resolveDefaultWindowDisplayMode() {
    return globals.isTablet
        ? NipaplayWindowDisplayMode.filledScreen
        : NipaplayWindowDisplayMode.windowed;
  }

  // 从SharedPreferences加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_widgetBlurEffectKey, false);
      _showDanmakuDensityChart = prefs.getBool(_showDanmakuDensityKey) ?? true;
      _showAnimeCardSummary = prefs.getBool(_showAnimeCardSummaryKey) ?? true;
      _accentColorPreset = AppAccentColorPreset.fromStorageKey(
        prefs.getString(_accentColorPresetKey),
      );
      AppAccentColors.setCurrent(_accentColorPreset);

      // 加载目录名称显示模式
      final folderNameModeIndex = prefs.getInt(_folderNameDisplayModeKey);
      if (folderNameModeIndex != null &&
          folderNameModeIndex >= 0 &&
          folderNameModeIndex < FolderNameDisplayMode.values.length) {
        _folderNameDisplayMode =
            FolderNameDisplayMode.values[folderNameModeIndex];
      } else {
        _folderNameDisplayMode = FolderNameDisplayMode.ellipsis;
      }
      final savedUiScale = prefs.getDouble(_uiScaleKey);
      _uiScale = (savedUiScale ?? _resolveDefaultUiScale())
          .clamp(uiScaleMin, uiScaleMax)
          .toDouble();
      final savedWindowDisplayModeIndex = prefs.getInt(_windowDisplayModeKey);
      if (savedWindowDisplayModeIndex != null &&
          savedWindowDisplayModeIndex >= 0 &&
          savedWindowDisplayModeIndex <
              NipaplayWindowDisplayMode.values.length) {
        _windowDisplayMode =
            NipaplayWindowDisplayMode.values[savedWindowDisplayModeIndex];
      } else {
        _windowDisplayMode = _resolveDefaultWindowDisplayMode();
      }

      // 加载番剧卡片点击行为设置
      final actionIndex = prefs.getInt(_animeCardActionKey);
      if (actionIndex != null && actionIndex < AnimeCardAction.values.length) {
        _animeCardAction = AnimeCardAction.values[actionIndex];
      } else {
        _animeCardAction = AnimeCardAction.synopsis; // 默认值
      }

      // 加载最近观看样式设置
      final styleIndex = prefs.getInt(_recentWatchingStyleKey);
      if (styleIndex != null &&
          styleIndex < RecentWatchingStyle.values.length) {
        _recentWatchingStyle = RecentWatchingStyle.values[styleIndex];
      } else {
        _recentWatchingStyle = RecentWatchingStyle.simple; // 默认值
      }

      notifyListeners();
    } catch (e) {
      debugPrint('加载外观设置时出错: $e');
    }
  }

  Future<void> setEnableWidgetBlurEffect(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_widgetBlurEffectKey, false);
    } catch (e) {
      debugPrint('保存控件模糊效果关闭状态时出错: $e');
    }
  }

  // 设置番剧卡片点击行为
  Future<void> setAnimeCardAction(AnimeCardAction value) async {
    if (_animeCardAction == value) return;

    _animeCardAction = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_animeCardActionKey, value.index);
    } catch (e) {
      debugPrint('保存番剧卡片点击行为设置时出错: $e');
    }
  }

  // 设置是否显示弹幕密度曲线图
  Future<void> setShowDanmakuDensityChart(bool value) async {
    if (_showDanmakuDensityChart == value) return;

    _showDanmakuDensityChart = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showDanmakuDensityKey, value);
    } catch (e) {
      debugPrint('保存弹幕密度图设置时出错: $e');
    }
  }

  // 设置最近观看样式
  Future<void> setRecentWatchingStyle(RecentWatchingStyle value) async {
    if (_recentWatchingStyle == value) return;

    _recentWatchingStyle = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_recentWatchingStyleKey, value.index);
    } catch (e) {
      debugPrint('保存最近观看样式设置时出错: $e');
    }
  }

  Future<void> setUiScale(double value) async {
    final clampedValue = value.clamp(uiScaleMin, uiScaleMax).toDouble();
    if (_uiScale == clampedValue) return;

    _uiScale = clampedValue;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_uiScaleKey, clampedValue);
    } catch (e) {
      debugPrint('保存界面缩放设置时出错: $e');
    }
  }

  Future<void> setShowAnimeCardSummary(bool value) async {
    if (_showAnimeCardSummary == value) return;

    _showAnimeCardSummary = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showAnimeCardSummaryKey, value);
    } catch (e) {
      debugPrint('保存番剧卡片简介显示设置时出错: $e');
    }
  }

  Future<void> setWindowDisplayMode(NipaplayWindowDisplayMode value) async {
    if (_windowDisplayMode == value) return;

    _windowDisplayMode = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_windowDisplayModeKey, value.index);
    } catch (e) {
      debugPrint('保存窗口显示区域设置时出错: $e');
    }
  }

  Future<void> setAccentColorPreset(AppAccentColorPreset value) async {
    if (_accentColorPreset == value) return;

    _accentColorPreset = value;
    AppAccentColors.setCurrent(value);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accentColorPresetKey, value.storageKey);
    } catch (e) {
      debugPrint('保存主题色设置时出错: $e');
    }
  }

  // 设置目录名称显示模式
  Future<void> setFolderNameDisplayMode(FolderNameDisplayMode value) async {
    if (_folderNameDisplayMode == value) return;

    _folderNameDisplayMode = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_folderNameDisplayModeKey, value.index);
    } catch (e) {
      debugPrint('保存目录名称显示模式设置时出错: $e');
    }
  }
}
