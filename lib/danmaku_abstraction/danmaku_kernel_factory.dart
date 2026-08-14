import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/danmaku_next/next2_platform_support.dart';
import 'package:nipaplay/plugins/models/plugin_danmaku_renderer.dart';
import 'package:nipaplay/utils/linux_nvidia_gpu.dart';

/// 弹幕渲染引擎枚举
enum DanmakuRenderEngine {
  /// CPU 渲染引擎
  cpu,

  /// GPU 渲染引擎
  gpu,

  /// Canvas 弹幕渲染引擎
  canvas,

  /// NipaPlay Next 弹幕逻辑内核
  nipaplayNext,

  /// NipaPlay Next2 弹幕逻辑 + Rust 渲染内核
  next2,

  /// DFM+ 弹幕引擎（B站 DanmakuFlameMaster 算法 + Rust + GPU 渲染）
  dfmPlus,
}

/// 负责读写弹幕渲染引擎设置的工厂类
class DanmakuKernelFactory {
  // Default to Next2 where it is supported; fall back to NipaPlay Next on Web.
  static DanmakuRenderEngine _cachedEngine = _defaultEngine;
  static bool _initialized = false;
  static String? _selectedPluginRendererId;
  static List<PluginDanmakuRenderer> _availablePluginRenderers = const [];

  /// Next++ 激进优化引擎开关
  static bool _enableNextPlusPlus = false;

  static DanmakuRenderEngine get _defaultEngine =>
      Next2PlatformSupport.isKernelSupported &&
              !isLinuxNvidiaGraphicsStackActive()
          ? DanmakuRenderEngine.next2
          : DanmakuRenderEngine.nipaplayNext;

  static bool get isNextPlusPlusEnabled => _enableNextPlusPlus;

  static void _setEnableNextPlusPlus(bool enabled) {
    if (_enableNextPlusPlus == enabled) return;
    _enableNextPlusPlus = enabled;
  }

  /// 保存 Next++ 开关状态，并通知 UI 更新显示名称和渲染路径。
  static Future<void> saveEnableNextPlusPlus(bool enabled) async {
    if (_enableNextPlusPlus == enabled) return;

    _setEnableNextPlusPlus(enabled);
    _kernelChangeController.add(DanmakuRenderEngine.nipaplayNext);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        SettingsKeys.danmakuEnableNextPlusPlusEngine,
        enabled,
      );
    } catch (e) {
      // ignore
    }
  }

  /// 获取 NipaPlay Next 引擎的显示名称
  /// Next++ 打开时显示 "NipaPlay Next++"，关闭时显示 "NipaPlay Next"
  static String get nipaplayNextDisplayName =>
      _enableNextPlusPlus ? 'NipaPlay Next++' : 'NipaPlay Next';

  // 添加StreamController用于广播内核切换事件
  static final StreamController<DanmakuRenderEngine> _kernelChangeController =
      StreamController<DanmakuRenderEngine>.broadcast();
  static Stream<DanmakuRenderEngine> get onKernelChanged =>
      _kernelChangeController.stream;

  /// 初始化方法，在应用启动时尽早调用
  static Future<void> initialize() async {
    await _preloadSettings();
  }

  /// 预加载设置并缓存
  static Future<void> _preloadSettings() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final engineIndex = prefs.getInt(SettingsKeys.danmakuRenderEngine);
      _selectedPluginRendererId =
          prefs.getString(SettingsKeys.danmakuPluginRenderer);
      _setEnableNextPlusPlus(
        prefs.getBool(SettingsKeys.danmakuEnableNextPlusPlusEngine) ?? false,
      );

      if (engineIndex != null &&
          engineIndex >= 0 &&
          engineIndex < DanmakuRenderEngine.values.length) {
        _cachedEngine = _sanitizeEngine(
          DanmakuRenderEngine.values[engineIndex],
        );
      } else {
        _cachedEngine = _defaultEngine;
      }
    } catch (e) {
      _cachedEngine = _defaultEngine;
    }

    _initialized = true;
  }

  /// 获取当前弹幕渲染引擎
  static DanmakuRenderEngine getKernelType() {
    return _cachedEngine;
  }

  static List<PluginDanmakuRenderer> get availablePluginRenderers =>
      List<PluginDanmakuRenderer>.unmodifiable(_availablePluginRenderers);

  static PluginDanmakuRenderer? get activePluginRenderer {
    final selectedId = _selectedPluginRendererId;
    if (selectedId == null) return null;
    for (final renderer in _availablePluginRenderers) {
      if (renderer.selectionId == selectedId &&
          renderer.isSupportedOnCurrentPlatform) {
        return renderer;
      }
    }
    return null;
  }

  static String? get selectedPluginRendererId => _selectedPluginRendererId;

  /// Refreshes renderers exposed by enabled and successfully loaded plugins.
  /// The stored selection is intentionally retained when a plugin is disabled,
  /// but it cannot become active again until that plugin is enabled.
  static void setAvailablePluginRenderers(
    List<PluginDanmakuRenderer> renderers,
  ) {
    final oldActive = activePluginRenderer;
    _availablePluginRenderers = renderers
        .where((renderer) => renderer.isSupportedOnCurrentPlatform)
        .toList(growable: false);
    final newActive = activePluginRenderer;
    if (oldActive?.selectionId != newActive?.selectionId ||
        !identical(oldActive, newActive)) {
      _rendererChangeController.add(null);
    }
  }

  static Future<void> savePluginRenderer(String selectionId) async {
    if (!_availablePluginRenderers.any(
      (renderer) => renderer.selectionId == selectionId,
    )) {
      throw StateError('插件弹幕渲染器不可用: $selectionId');
    }
    if (_selectedPluginRendererId == selectionId) return;
    _selectedPluginRendererId = selectionId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsKeys.danmakuPluginRenderer, selectionId);
    _rendererChangeController.add(null);
  }

  /// 保存弹幕渲染引擎设置
  static Future<void> saveKernelType(DanmakuRenderEngine engine) async {
    try {
      final sanitizedEngine = _sanitizeEngine(engine);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        SettingsKeys.danmakuRenderEngine,
        sanitizedEngine.index,
      );
      final oldEngine = _cachedEngine;
      final hadPluginRenderer = _selectedPluginRendererId != null;
      _cachedEngine = sanitizedEngine;
      _selectedPluginRendererId = null;
      await prefs.remove(SettingsKeys.danmakuPluginRenderer);

      if (oldEngine != sanitizedEngine || hadPluginRenderer) {
        _kernelChangeController.add(sanitizedEngine);
        _rendererChangeController.add(null);
      }
    } catch (e) {
      // ignore
    }
  }

  static DanmakuRenderEngine _sanitizeEngine(DanmakuRenderEngine engine) {
    if ((engine == DanmakuRenderEngine.next2 ||
            engine == DanmakuRenderEngine.dfmPlus) &&
        !Next2PlatformSupport.isKernelSupported) {
      return DanmakuRenderEngine.nipaplayNext;
    }
    return engine;
  }

  static final StreamController<void> _rendererChangeController =
      StreamController<void>.broadcast();
  static Stream<void> get onRendererChanged => _rendererChangeController.stream;
}
