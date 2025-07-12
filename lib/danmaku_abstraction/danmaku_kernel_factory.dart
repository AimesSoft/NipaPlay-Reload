import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../utils/settings_storage.dart';

/// 弹幕内核类型枚举
enum DanmakuKernelType {
  /// 内置弹幕渲染器
  nipaPlay,

  /// Canvas_Danmaku 渲染器
  canvasDanmaku,

  /// Flutter GPU + Custom Shaders 渲染器
  flutterGPUDanmaku,
}

/// 负责读写弹幕内核设置以及提供默认值的工厂类。
///
/// 与现有的 `PlayerFactory` 设计保持一致，便于在设置界面与业务代码中统一调用。
class DanmakuKernelFactory {
  static const String _danmakuKernelTypeKey = 'danmaku_kernel_type';
  static DanmakuKernelType _cachedType = DanmakuKernelType.nipaPlay;
  static bool _initialized = false;

  /// 初始化方法，在应用启动时尽早调用（如 main.dart 的 runApp 之前）。
  static Future<void> initialize() async {
    await _preloadSettings();
  }

  /// 预加载设置并缓存，避免每次都读取SharedPreferences
  static Future<void> _preloadSettings() async {
    if (_initialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final typeIndex = prefs.getInt(_danmakuKernelTypeKey);
      
      if (typeIndex != null && typeIndex >= 0 && typeIndex < DanmakuKernelType.values.length) {
        _cachedType = DanmakuKernelType.values[typeIndex];
      } else {
        // 如果没有保存的值或值无效，使用默认值
        _cachedType = DanmakuKernelType.nipaPlay;
      }
    } catch (e) {
      _cachedType = DanmakuKernelType.nipaPlay;
    }
    
    _initialized = true;
  }

  /// 获取当前弹幕内核类型
  static DanmakuKernelType getKernelType() {
    return _cachedType;
  }

  /// 保存弹幕内核设置
  static Future<void> saveKernelType(DanmakuKernelType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_danmakuKernelTypeKey, type.index);
      _cachedType = type;
    } catch (e) {
      // ignore
    }
  }
} 