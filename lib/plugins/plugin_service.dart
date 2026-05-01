import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/plugins/js_runtime_factory.dart';
import 'package:nipaplay/plugins/js_runtime_types.dart';
import 'package:nipaplay/plugins/models/plugin_descriptor.dart';
import 'package:nipaplay/plugins/models/plugin_ui_action_result.dart';
import 'package:nipaplay/plugins/models/plugin_ui_entry.dart';
import 'package:nipaplay/plugins/models/plugin_manifest.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PluginService extends ChangeNotifier {
  PluginService() {
    _initialize();
  }

  static const String _enabledPluginsKey = 'plugin_enabled_ids';
  static const List<String> _pluginAssetPrefixes = <String>[
    'assets/plugins/builtin/',
    'assets/plugins/custom/',
  ];
  static const String _defaultBuiltinPluginId =
      'builtin.cn_sensitive_danmaku_filter';

  final List<PluginDescriptor> _plugins = <PluginDescriptor>[];
  final Map<String, PluginJsRuntime> _runtimeByPluginId =
      <String, PluginJsRuntime>{};
  final Map<String, String> _scriptByPluginId = <String, String>{};

  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  List<PluginDescriptor> get plugins => List<PluginDescriptor>.unmodifiable(
        _plugins,
      );

  List<String> get activeDanmakuBlockWords {
    final merged = <String>[];
    for (final plugin in _plugins) {
      if (!plugin.enabled || !plugin.loaded) continue;
      if (plugin.blockWords.isEmpty) continue;
      merged.addAll(plugin.blockWords);
    }
    return merged;
  }

  bool isPluginEnabled(String pluginId) {
    return _plugins.any(
      (plugin) => plugin.manifest.id == pluginId && plugin.enabled,
    );
  }

  Future<void> _initialize() async {
    await _loadPluginsFromAssets();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _loadPluginsFromAssets() async {
    final enabledIds = await _loadEnabledIds();
    final pluginAssets = await _discoverPluginAssets();

    for (final assetPath in pluginAssets) {
      try {
        final script = await rootBundle.loadString(assetPath);
        final parsed = _parsePluginMetadata(script);
        final manifest = parsed.manifest;
        if (_scriptByPluginId.containsKey(manifest.id)) {
          debugPrint('发现重复插件ID(${manifest.id})，已跳过: $assetPath');
          continue;
        }

        _scriptByPluginId[manifest.id] = script;
        final enabled = enabledIds.contains(manifest.id);

        final descriptor = PluginDescriptor(
          manifest: manifest,
          assetPath: assetPath,
          isBuiltin: assetPath.startsWith(_pluginAssetPrefixes.first),
          enabled: enabled,
          loaded: false,
          errorMessage: null,
          blockWords: const <String>[],
          uiEntries: parsed.uiEntries,
        );
        _plugins.add(descriptor);

        if (enabled) {
          await _loadPluginRuntime(manifest.id);
        }
      } catch (e) {
        debugPrint('插件加载失败($assetPath): $e');
      }
    }

    if (_plugins.isEmpty) {
      return;
    }

    final existingIds = _plugins.map((e) => e.manifest.id).toSet();
    final sanitizedEnabled = enabledIds.where(existingIds.contains).toList();
    await _saveEnabledIds(sanitizedEnabled);
  }

  Future<List<String>> _discoverPluginAssets() async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = assetManifest.listAssets();

    final pluginAssets = assets
        .where((asset) => asset.endsWith('.js'))
        .where(
          (asset) => _pluginAssetPrefixes.any(
            (prefix) => asset.startsWith(prefix),
          ),
        )
        .toList()
      ..sort();
    return pluginAssets;
  }

  Future<void> setPluginEnabled(String pluginId, bool enabled) async {
    final index =
        _plugins.indexWhere((plugin) => plugin.manifest.id == pluginId);
    if (index < 0) return;

    final current = _plugins[index];
    if (current.enabled == enabled) {
      return;
    }

    _plugins[index] = current.copyWith(
      enabled: enabled,
      loaded: enabled ? current.loaded : false,
      blockWords: enabled ? current.blockWords : const <String>[],
      clearErrorMessage: !enabled,
    );
    notifyListeners();

    if (enabled) {
      await _loadPluginRuntime(pluginId);
    } else {
      await _unloadPluginRuntime(pluginId);
    }

    final enabledIds = _plugins
        .where((plugin) => plugin.enabled)
        .map((plugin) => plugin.manifest.id)
        .toList();
    await _saveEnabledIds(enabledIds);
  }

  Future<void> _loadPluginRuntime(String pluginId) async {
    final index =
        _plugins.indexWhere((plugin) => plugin.manifest.id == pluginId);
    if (index < 0) return;

    final plugin = _plugins[index];

    try {
      await _unloadPluginRuntime(pluginId);
      final script = _scriptByPluginId[pluginId];
      if (script == null || script.isEmpty) {
        throw StateError('插件脚本不存在: ${plugin.assetPath}');
      }

      final runtime = createPluginRuntime();
      runtime.evaluate(script);

      final blockWords = _extractBlockWords(runtime);
      final uiEntries = _extractUiEntries(runtime);

      _runtimeByPluginId[pluginId] = runtime;
      _plugins[index] = plugin.copyWith(
        loaded: true,
        blockWords: blockWords,
        uiEntries: uiEntries,
        clearErrorMessage: true,
      );
    } catch (e) {
      _plugins[index] = plugin.copyWith(
        loaded: false,
        blockWords: const <String>[],
        errorMessage: e.toString(),
      );
    }
    notifyListeners();
  }

  Future<void> _unloadPluginRuntime(String pluginId) async {
    final runtime = _runtimeByPluginId.remove(pluginId);
    if (runtime != null) {
      try {
        runtime.dispose();
      } catch (_) {}
    }

    final index =
        _plugins.indexWhere((plugin) => plugin.manifest.id == pluginId);
    if (index >= 0) {
      final plugin = _plugins[index];
      _plugins[index] = plugin.copyWith(
        loaded: false,
        blockWords: const <String>[],
      );
      notifyListeners();
    }
  }

  Future<PluginUiActionResult?> invokePluginUiAction(
    String pluginId,
    String actionId,
  ) async {
    final index =
        _plugins.indexWhere((plugin) => plugin.manifest.id == pluginId);
    if (index < 0) {
      throw StateError('插件不存在: $pluginId');
    }
    final plugin = _plugins[index];
    if (!plugin.enabled || !plugin.loaded) {
      throw StateError('插件未启用: ${plugin.manifest.name}');
    }
    if (!plugin.uiEntries.any((entry) => entry.id == actionId)) {
      throw StateError('插件动作不存在: $actionId');
    }

    final runtime = _runtimeByPluginId[pluginId];
    if (runtime == null) {
      throw StateError('插件运行时未加载: ${plugin.manifest.name}');
    }

    final actionIdJson = json.encode(actionId);
    final raw = runtime
        .evaluate(
          '(function() {'
          'if (typeof pluginHandleUIAction !== "function") {'
          'return JSON.stringify(null);'
          '}'
          'var result = pluginHandleUIAction($actionIdJson);'
          'if (typeof result === "string") { return result; }'
          'if (typeof result === "undefined" || result === null) {'
          'return JSON.stringify(null);'
          '}'
          'return JSON.stringify(result);'
          '})()',
        )
        .trim();
    if (raw.isEmpty || raw == 'null' || raw == 'undefined') {
      return null;
    }

    final decoded = json.decode(raw);
    if (decoded is! Map) {
      throw const FormatException('插件动作返回值不是对象');
    }
    return PluginUiActionResult.fromJson(
      Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
    );
  }

  _ParsedPluginMetadata _parsePluginMetadata(String script) {
    final runtime = createPluginRuntime();
    try {
      runtime.evaluate(script);
      return _ParsedPluginMetadata(
        manifest: _extractManifest(runtime),
        uiEntries: _extractUiEntries(runtime),
      );
    } finally {
      try {
        runtime.dispose();
      } catch (_) {}
    }
  }

  PluginManifest _extractManifest(PluginJsRuntime runtime) {
    final manifestJson = runtime
        .evaluate(
          'JSON.stringify((typeof pluginManifest !== "undefined") ? pluginManifest : null)',
        )
        .trim();
    if (manifestJson.isEmpty || manifestJson == 'null') {
      throw const FormatException('pluginManifest not found');
    }
    final decoded = json.decode(manifestJson);
    if (decoded is! Map) {
      throw const FormatException('pluginManifest is not object');
    }
    return PluginManifest.fromJson(
      Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
    );
  }

  List<String> _extractBlockWords(PluginJsRuntime runtime) {
    final raw = runtime
        .evaluate(
          'JSON.stringify((typeof pluginBlockWords !== "undefined" && Array.isArray(pluginBlockWords)) ? pluginBlockWords : [])',
        )
        .trim();
    if (raw.isEmpty) return const <String>[];

    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const <String>[];
      return decoded
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  List<PluginUiEntry> _extractUiEntries(PluginJsRuntime runtime) {
    final raw = runtime
        .evaluate(
          'JSON.stringify((typeof pluginUIEntries !== "undefined" && Array.isArray(pluginUIEntries)) ? pluginUIEntries : [])',
        )
        .trim();
    if (raw.isEmpty) return const <PluginUiEntry>[];

    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const <PluginUiEntry>[];

      final uiEntries = <PluginUiEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final entry = PluginUiEntry.fromJson(
            Map<String, dynamic>.from(item.cast<String, dynamic>()),
          );
          uiEntries.add(entry);
        } catch (e) {
          debugPrint('插件UI入口解析失败: $e');
        }
      }
      return uiEntries;
    } catch (_) {
      return const <PluginUiEntry>[];
    }
  }

  Future<List<String>> _loadEnabledIds() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_enabledPluginsKey);
    if (saved == null || saved.isEmpty) {
      return const <String>[_defaultBuiltinPluginId];
    }
    return saved.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> _saveEnabledIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledPluginsKey, ids);
  }

  @override
  void dispose() {
    for (final runtime in _runtimeByPluginId.values) {
      try {
        runtime.dispose();
      } catch (_) {}
    }
    _runtimeByPluginId.clear();
    _scriptByPluginId.clear();
    super.dispose();
  }
}

class _ParsedPluginMetadata {
  const _ParsedPluginMetadata({
    required this.manifest,
    required this.uiEntries,
  });

  final PluginManifest manifest;
  final List<PluginUiEntry> uiEntries;
}
