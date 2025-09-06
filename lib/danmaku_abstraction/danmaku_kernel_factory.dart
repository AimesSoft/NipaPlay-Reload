import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

/// 弹幕渲染引擎枚举
enum DanmakuRenderEngine {
  /// CPU 渲染引擎
  cpu,

  /// GPU 渲染引擎
  gpu,

  /// Canvas 弹幕渲染引擎
  canvas,
}

/// 负责读写弹幕渲染引擎设置的工厂类
class DanmakuKernelFactory {
  static const String _danmakuRenderEngineKey = 'danmaku_render_engine';
  // Default to Canvas if no user setting exists
  static DanmakuRenderEngine _cachedEngine = DanmakuRenderEngine.canvas;
  static bool _initialized = false;

  // 添加StreamController用于广播内核切换事件
  static final StreamController<DanmakuRenderEngine> _kernelChangeController = StreamController<DanmakuRenderEngine>.broadcast();
  static Stream<DanmakuRenderEngine> get onKernelChanged => _kernelChangeController.stream;

  /// 初始化方法，在应用启动时尽早调用
  static Future<void> initialize() async {
    await _preloadSettings();
  }

  /// 预加载设置并缓存
  static Future<void> _preloadSettings() async {
    if (_initialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final engineIndex = prefs.getInt(_danmakuRenderEngineKey);
      
      if (engineIndex != null && engineIndex >= 0 && engineIndex < DanmakuRenderEngine.values.length) {
        _cachedEngine = DanmakuRenderEngine.values[engineIndex];
      } else {
        _cachedEngine = DanmakuRenderEngine.canvas; // 默认使用 Canvas
      }
    } catch (e) {
      _cachedEngine = DanmakuRenderEngine.canvas;
    }
    
    _initialized = true;
  }

  /// 获取当前弹幕渲染引擎
  static DanmakuRenderEngine getKernelType() {
    return _cachedEngine;
  }

  /// 保存弹幕渲染引擎设置
  static Future<void> saveKernelType(DanmakuRenderEngine engine) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_danmakuRenderEngineKey, engine.index);
      final oldEngine = _cachedEngine;
      _cachedEngine = engine;

      if (oldEngine != engine) {
        _kernelChangeController.add(engine);
      }
    } catch (e) {
      // ignore
    }
  }
} 