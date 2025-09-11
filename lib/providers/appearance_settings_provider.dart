import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' if (dart.library.html) 'dart:io';

// 定义番剧卡片点击行为的枚举
enum AnimeCardAction {
  synopsis, // 简介
  episodeList, // 剧集列表
}

class AppearanceSettingsProvider extends ChangeNotifier {
  static const String _enablePageAnimationKey = 'enable_page_animation';
  static const String _widgetBlurEffectKey = 'enable_widget_blur_effect';
  static const String _animeCardActionKey = 'anime_card_action';
  static const String _showDanmakuDensityKey = 'show_danmaku_density_chart';

  // 默认值根据平台决定
  late bool _enablePageAnimation;
  late bool _enableWidgetBlurEffect;
  late AnimeCardAction _animeCardAction;
  late bool _showDanmakuDensityChart;

  // 获取设置值
  bool get enablePageAnimation => _enablePageAnimation;
  bool get enableWidgetBlurEffect => _enableWidgetBlurEffect;
  AnimeCardAction get animeCardAction => _animeCardAction;
  bool get showDanmakuDensityChart => _showDanmakuDensityChart;

  // 构造函数
  AppearanceSettingsProvider() {
    // 初始化默认值
    _enablePageAnimation = _getDefaultAnimationValue();
    _enableWidgetBlurEffect = true; // 默认开启控件毛玻璃效果
    _animeCardAction = AnimeCardAction.synopsis; // 默认行为是显示简介
    _showDanmakuDensityChart = true; // 默认显示弹幕密度曲线图
    _loadSettings();
  }

  // 根据平台返回默认动画设置
  bool _getDefaultAnimationValue() {
    if (kIsWeb) {
      return false; // Web平台默认禁用动画
    }
    // 在移动端设备上默认启用动画
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      return true;
    }
    // 在桌面端设备上默认禁用动画
    else if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return false;
    }
    // 其他未知平台，默认禁用
    return false;
  }

  // 从SharedPreferences加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 从存储加载时使用平台相关的默认值
      _enablePageAnimation = prefs.getBool(_enablePageAnimationKey) ?? _getDefaultAnimationValue();
      _enableWidgetBlurEffect = prefs.getBool(_widgetBlurEffectKey) ?? true;
      _showDanmakuDensityChart = prefs.getBool(_showDanmakuDensityKey) ?? true;
      
      // 加载番剧卡片点击行为设置
      final actionIndex = prefs.getInt(_animeCardActionKey);
      if (actionIndex != null && actionIndex < AnimeCardAction.values.length) {
        _animeCardAction = AnimeCardAction.values[actionIndex];
      } else {
        _animeCardAction = AnimeCardAction.synopsis; // 默认值
      }
      
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
} 