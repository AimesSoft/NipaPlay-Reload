import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 弹幕内核类型枚举
enum DanmakuKernelType {
  /// 内置弹幕渲染器
  nipaPlay,

  /// Canvas_Danmaku 渲染器
  canvasDanmaku,
}

/// 负责读写弹幕内核设置以及提供默认值的工厂类。
///
/// 与现有的 `PlayerFactory` 设计保持一致，便于在设置界面与业务代码中统一调用。
class DanmakuKernelFactory {
  static const String _danmakuKernelTypeKey = 'danmaku_kernel_type';
  static DanmakuKernelType? _cachedType;
  static bool _hasLoaded = false;

  /// 初始化方法，在应用启动时尽早调用（如 main.dart 的 runApp 之前）。
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_danmakuKernelTypeKey);
      if (index != null && index < DanmakuKernelType.values.length) {
        _cachedType = DanmakuKernelType.values[index];
        debugPrint('[DanmakuKernelFactory] 预加载内核设置: \\${_cachedType.toString()}');
      } else {
        _cachedType = DanmakuKernelType.nipaPlay;
        debugPrint('[DanmakuKernelFactory] 无内核设置，使用默认: NipaPlay');
      }
      _hasLoaded = true;
    } catch (e) {
      debugPrint('[DanmakuKernelFactory] 初始化读取设置出错: $e');
      _cachedType = DanmakuKernelType.nipaPlay;
      _hasLoaded = true;
    }
  }

  /// 同步加载设置。在 `initialize` 调用前读取时使用临时默认值，避免空指针。
  static void _loadSettingsSync() {
    _cachedType = DanmakuKernelType.nipaPlay;
    _hasLoaded = true;
    // 异步纠正
    SharedPreferences.getInstance().then((prefs) {
      final index = prefs.getInt(_danmakuKernelTypeKey);
      if (index != null && index < DanmakuKernelType.values.length) {
        _cachedType = DanmakuKernelType.values[index];
        debugPrint('[DanmakuKernelFactory] 异步更新内核设置: \\${_cachedType.toString()}');
      }
    });
  }

  /// 获取当前弹幕内核类型
  static DanmakuKernelType getKernelType() {
    if (!_hasLoaded) {
      _loadSettingsSync();
    }
    return _cachedType ?? DanmakuKernelType.nipaPlay;
  }

  /// 保存弹幕内核设置
  static Future<void> saveKernelType(DanmakuKernelType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_danmakuKernelTypeKey, type.index);
      _cachedType = type;
      debugPrint('[DanmakuKernelFactory] 保存内核设置: \\${type.toString()}');
    } catch (e) {
      debugPrint('[DanmakuKernelFactory] 保存内核设置出错: $e');
    }
  }
} 