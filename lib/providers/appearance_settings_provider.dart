import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class AppearanceSettingsProvider extends ChangeNotifier {
  static const String _widgetBlurEffectKey = 'enable_widget_blur_effect';
  static const String _animeCardActionKey = 'anime_card_action';
  static const String _showDanmakuDensityKey = 'show_danmaku_density_chart';
  static const String _recentWatchingStyleKey = 'recent_watching_style';

  late bool _enableWidgetBlurEffect;
  late AnimeCardAction _animeCardAction;
  late bool _showDanmakuDensityChart;
  late RecentWatchingStyle _recentWatchingStyle;

  // 获取设置值
  // 页面滑动动画始终启用
  bool get enablePageAnimation => true;
  
  bool get enableWidgetBlurEffect => _enableWidgetBlurEffect;
  AnimeCardAction get animeCardAction => _animeCardAction;
  bool get showDanmakuDensityChart => _showDanmakuDensityChart;
  RecentWatchingStyle get recentWatchingStyle => _recentWatchingStyle;

  // 构造函数
  AppearanceSettingsProvider() {
    // 初始化默认值
    _enableWidgetBlurEffect = true; // 默认开启控件毛玻璃效果
    _animeCardAction = AnimeCardAction.synopsis; // 默认行为是显示简介
    _showDanmakuDensityChart = true; // 默认显示弹幕密度曲线图
    _recentWatchingStyle = RecentWatchingStyle.simple; // 默认简洁版
    _loadSettings();
  }

  // 从SharedPreferences加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enableWidgetBlurEffect = prefs.getBool(_widgetBlurEffectKey) ?? true;
      _showDanmakuDensityChart = prefs.getBool(_showDanmakuDensityKey) ?? true;

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

  // 设置是否启用控件毛玻璃效果
  Future<void> setEnableWidgetBlurEffect(bool value) async {
    if (_enableWidgetBlurEffect == value) return;

    _enableWidgetBlurEffect = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_widgetBlurEffectKey, value);
    } catch (e) {
      debugPrint('保存控件毛玻璃效果设置时出错: $e');
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
}