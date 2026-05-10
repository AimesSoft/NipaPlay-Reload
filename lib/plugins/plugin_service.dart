import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nipaplay/plugins/js_runtime_factory.dart';
import 'package:nipaplay/plugins/plugin_storage.dart';
import 'package:nipaplay/plugins/js_runtime_types.dart';
import 'package:nipaplay/plugins/models/plugin_descriptor.dart';
import 'package:nipaplay/plugins/models/plugin_ui_action_result.dart';
import 'package:nipaplay/plugins/models/plugin_ui_entry.dart';
import 'package:nipaplay/plugins/models/plugin_manifest.dart';
import 'package:nipaplay/plugins/models/plugin_event.dart';
import 'package:nipaplay/plugins/models/plugin_permission.dart';
import 'package:nipaplay/plugins/plugin_event_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PluginService extends ChangeNotifier {
  PluginService()
      : _eventBus = PluginEventBus() {
    _initialize();
    _setupEventListeners();
  }

  static const String _enabledPluginsKey = 'plugin_enabled_ids';
  static const String _downloaderOverrideKey = 'plugin_downloader_override';
  static const List<String> _pluginAssetPrefixes = <String>[
    'assets/plugins/builtin/',
    'assets/plugins/custom/',
  ];
  static const String _defaultBuiltinPluginId =
      'builtin.cn_sensitive_danmaku_filter';
  static const String _loadedAssetPrefix = 'asset:';
  static const String _loadedFilePrefix = 'file:';

  static bool _forceEnableDownloader = false;

  static void setForceEnableDownloader(bool value) {
    _forceEnableDownloader = value;
    _saveDownloaderOverride(value);
  }

  static bool get forceEnableDownloader => _forceEnableDownloader;

  static Future<void> loadDownloaderOverride() async {
    final prefs = await SharedPreferences.getInstance();
    _forceEnableDownloader = prefs.getBool(_downloaderOverrideKey) ?? false;
  }

  static Future<void> _saveDownloaderOverride(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_downloaderOverrideKey, value);
  }

  final List<PluginDescriptor> _plugins = <PluginDescriptor>[];
  final Map<String, PluginJsRuntime> _runtimeByPluginId =
      <String, PluginJsRuntime>{};
  final Map<String, String> _scriptByPluginId = <String, String>{};
  final PluginStorage _pluginStorage = createPluginStorage();
  final PluginEventBus _eventBus;

  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  List<PluginDescriptor> get plugins => List<PluginDescriptor>.unmodifiable(
        _plugins,
      );

  PluginEventBus get eventBus => _eventBus;

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

  bool hasPermission(String pluginId, PluginPermission permission) {
    final plugin = _plugins.firstWhere(
      (p) => p.manifest.id == pluginId,
      orElse: () => throw StateError('插件不存在: $pluginId'),
    );
    return plugin.manifest.permissions.contains(permission);
  }

  Future<void> _initialize() async {
    await _reloadPlugins();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> reloadPlugins() async {
    await _reloadPlugins();
    notifyListeners();
  }

  void _setupEventListeners() {
    _eventBus.on(PluginEventType.videoLoaded, _handleEvent);
    _eventBus.on(PluginEventType.play, _handleEvent);
    _eventBus.on(PluginEventType.pause, _handleEvent);
    _eventBus.on(PluginEventType.seek, _handleEvent);
    _eventBus.on(PluginEventType.danmakuShow, _handleEvent);
    _eventBus.on(PluginEventType.settingsChanged, _handleEvent);
    _eventBus.on(PluginEventType.appResumed, _handleEvent);
    _eventBus.on(PluginEventType.appPaused, _handleEvent);
  }

  void _handleEvent(PluginEvent event) {
    for (final plugin in _plugins) {
      if (!plugin.enabled || !plugin.loaded) continue;
      final runtime = _runtimeByPluginId[plugin.manifest.id];
      if (runtime == null) continue;

      try {
        final eventJson = event.toJson();
        runtime.evaluate(
          '''
          if (typeof pluginOnEvent === "function") {
            try {
              pluginOnEvent($eventJson);
            } catch(e) {}
          }
          ''',
        );
      } catch (_) {}
    }
  }

  Future<void> _reloadPlugins() async {
    await _disposeAllRuntimes();
    _plugins.clear();
    _scriptByPluginId.clear();

    final enabledIds = await _loadEnabledIds();
    final discoveredPlugins = await _discoverPlugins();

    for (final discovered in discoveredPlugins) {
      try {
        final parsed = _parsePluginMetadata(discovered.script);
        final manifest = parsed.manifest;
        if (_scriptByPluginId.containsKey(manifest.id)) {
          continue;
        }

        _scriptByPluginId[manifest.id] = discovered.script;
        final enabled = enabledIds.contains(manifest.id);

        final descriptor = PluginDescriptor(
          manifest: manifest,
          assetPath: discovered.path,
          isBuiltin: discovered.path.startsWith(_loadedAssetPrefix),
          enabled: enabled,
          loaded: false,
          errorMessage: null,
          blockWords: const <String>[],
          uiEntries: parsed.uiEntries,
        );
        _plugins.add(descriptor);

        if (enabled) {
          await _loadPluginRuntime(manifest.id);
          await _invokeLifecycleEvent(manifest.id, 'initialize');
        }
      } catch (_) {}
    }

    if (_plugins.isEmpty) {
      return;
    }

    final existingIds = _plugins.map((e) => e.manifest.id).toSet();
    final sanitizedEnabled = enabledIds.where(existingIds.contains).toList();
    await _saveEnabledIds(sanitizedEnabled);
  }

  Future<List<_DiscoveredPluginScript>> _discoverPlugins() async {
    final assets = await _discoverAssetPlugins();
    final files = await _discoverFilePlugins();
    return <_DiscoveredPluginScript>[
      ...assets,
      ...files,
    ];
  }

  Future<List<_DiscoveredPluginScript>> _discoverAssetPlugins() async {
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
    final discovered = <_DiscoveredPluginScript>[];
    for (final assetPath in pluginAssets) {
      final script = await rootBundle.loadString(assetPath);
      discovered.add(
        _DiscoveredPluginScript(
          path: '$_loadedAssetPrefix$assetPath',
          script: script,
        ),
      );
    }
    return discovered;
  }

  Future<List<_DiscoveredPluginScript>> _discoverFilePlugins() async {
    final scripts = await _pluginStorage.listScripts();
    return scripts
        .map(
          (script) => _DiscoveredPluginScript(
            path: '$_loadedFilePrefix${script.path}',
            script: script.content,
          ),
        )
        .toList();
  }

  Future<void> setPluginEnabled(String pluginId, bool enabled) async {
    final index =
        _plugins.indexWhere((plugin) => plugin.manifest.id == pluginId);
    if (index < 0) {
      return;
    }

    final current = _plugins[index];
    if (current.enabled == enabled) {
      return;
    }

    _plugins[index] = current.copyWith(
      enabled: enabled,
      loaded: current.loaded,
      blockWords: enabled ? current.blockWords : const <String>[],
      clearErrorMessage: !enabled,
    );
    notifyListeners();

    if (enabled) {
      await _loadPluginRuntime(pluginId);
      await _invokeLifecycleEvent(pluginId, 'initialize');
    } else {
      await _invokeLifecycleEvent(pluginId, 'destroy');
      await _unloadPluginRuntime(pluginId);
    }

    if (pluginId.contains('downloader_unlock')) {
      setForceEnableDownloader(enabled);
      notifyListeners();
    }

    final enabledIds = _plugins
        .where((plugin) => plugin.enabled)
        .map((plugin) => plugin.manifest.id)
        .toList();
    await _saveEnabledIds(enabledIds);
  }

  Future<void> _invokeLifecycleEvent(String pluginId, String event) async {
    final runtime = _runtimeByPluginId[pluginId];
    if (runtime == null) return;

    try {
      runtime.evaluate(
        '''
        if (typeof pluginOn${event[0].toUpperCase()}${event.substring(1)} === "function") {
          try {
            pluginOn${event[0].toUpperCase()}${event.substring(1)}();
          } catch(e) {}
        }
        ''',
      );
    } catch (_) {}
  }

  Future<void> handleAppLifecycleStateChange(bool resumed) async {
    if (resumed) {
      _eventBus.emitAppResumed();
    } else {
      _eventBus.emitAppPaused();
    }

    for (final plugin in _plugins) {
      if (!plugin.enabled || !plugin.loaded) continue;
      await _invokeLifecycleEvent(
        plugin.manifest.id,
        resumed ? 'resume' : 'suspend',
      );
    }
  }

  Future<void> _loadPluginRuntime(String pluginId) async {
    final index =
        _plugins.indexWhere((plugin) => plugin.manifest.id == pluginId);
    if (index < 0) {
      return;
    }

    final plugin = _plugins[index];

    try {
      await _unloadPluginRuntime(pluginId);
      final script = _scriptByPluginId[pluginId];
      if (script == null || script.isEmpty) {
        throw StateError('插件脚本不存在: ${plugin.assetPath}');
      }

      final runtime = createPluginRuntime();

      await _injectPluginApi(runtime, pluginId);

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

  Future<void> _injectPluginApi(PluginJsRuntime runtime, String pluginId) async {
    final plugin = _plugins.firstWhere(
      (p) => p.manifest.id == pluginId,
      orElse: () => throw StateError('插件不存在: $pluginId'),
    );

    final apiCode = '''
      const plugin = {
        id: ${json.encode(plugin.manifest.id)},
        name: ${json.encode(plugin.manifest.name)},
        version: ${json.encode(plugin.manifest.version)},
        hasPermission: function(permissionId) {
          return ${json.encode(plugin.manifest.permissions.map((p) => p.id).toList())}.includes(permissionId);
        },
        permissions: ${json.encode(plugin.manifest.permissions.map((p) => p.id).toList())},
      };

      const player = {
        play: function() {
          if (!plugin.hasPermission('player.control')) return false;
          return window.flutter_invokeMethod('playerPlay');
        },
        pause: function() {
          if (!plugin.hasPermission('player.control')) return false;
          return window.flutter_invokeMethod('playerPause');
        },
        seek: function(time) {
          if (!plugin.hasPermission('player.control')) return false;
          return window.flutter_invokeMethod('playerSeek', time);
        },
        getState: function() {
          if (!plugin.hasPermission('player.control')) return null;
          return JSON.parse(window.flutter_invokeMethod('playerGetState') || 'null');
        },
      };

      const danmaku = {
        show: function() {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return window.flutter_invokeMethod('danmakuShow');
        },
        hide: function() {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return window.flutter_invokeMethod('danmakuHide');
        },
        setOpacity: function(opacity) {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return window.flutter_invokeMethod('danmakuSetOpacity', opacity);
        },
        addFilter: function(filterId, pattern) {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return window.flutter_invokeMethod('danmakuAddFilter', filterId, pattern);
        },
        removeFilter: function(filterId) {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return window.flutter_invokeMethod('danmakuRemoveFilter', filterId);
        },
      };

      const ui = {
        showToast: function(message) {
          if (!plugin.hasPermission('ui.dialog')) return;
          window.flutter_invokeMethod('uiShowToast', message);
        },
        showDialog: function(title, content) {
          if (!plugin.hasPermission('ui.dialog')) return false;
          return JSON.parse(window.flutter_invokeMethod('uiShowDialog', title, content) || 'false');
        },
        showLoading: function(message) {
          if (!plugin.hasPermission('ui.dialog')) return;
          window.flutter_invokeMethod('uiShowLoading', message);
        },
        hideLoading: function() {
          if (!plugin.hasPermission('ui.dialog')) return;
          window.flutter_invokeMethod('uiHideLoading');
        },
      };

      const storage = {
        set: function(key, value) {
          if (!plugin.hasPermission('storage')) return false;
          return window.flutter_invokeMethod('storageSet', key, JSON.stringify(value));
        },
        get: function(key) {
          if (!plugin.hasPermission('storage')) return null;
          const result = window.flutter_invokeMethod('storageGet', key);
          return result ? JSON.parse(result) : null;
        },
        remove: function(key) {
          if (!plugin.hasPermission('storage')) return false;
          return window.flutter_invokeMethod('storageRemove', key);
        },
        clear: function() {
          if (!plugin.hasPermission('storage')) return false;
          return window.flutter_invokeMethod('storageClear');
        },
      };

      const dev = {
        log: function(message) {
          window.flutter_invokeMethod('devLog', message);
        },
        logError: function(error) {
          window.flutter_invokeMethod('devLogError', error);
        },
      };

      const system = {
        setDownloaderEnabled: function(enabled) {
          if (!plugin.hasPermission('system.override')) return false;
          return window.flutter_invokeMethod('systemSetDownloaderEnabled', enabled);
        },
      };

      const __pluginServices = {
        player,
        danmaku,
        ui,
        storage,
        dev,
        system,
      };
    ''';

    runtime.evaluate(apiCode);
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

  Future<void> _disposeAllRuntimes() async {
    final pluginIds = _runtimeByPluginId.keys.toList();
    for (final pluginId in pluginIds) {
      await _unloadPluginRuntime(pluginId);
    }
    _runtimeByPluginId.clear();
  }

  Future<String?> importPluginScript({
    required String sourceFilePath,
  }) async {
    final script = await _pluginStorage.readTextFile(sourceFilePath);
    return _importPluginFromContent(script);
  }

  Future<String?> importPluginFromContent(String script) async {
    return _importPluginFromContent(script);
  }

  Future<String?> _importPluginFromContent(String script) async {
    final parsed = _parsePluginMetadata(script);
    final minVersion = parsed.manifest.minHostVersion;
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    if (_compareVersions(currentVersion, minVersion) < 0) {
      throw StateError(
        '当前应用版本 $currentVersion 低于插件要求的最低版本 $minVersion',
      );
    }
    final fileName = '${parsed.manifest.id}.js';
    await _pluginStorage.saveScript(fileName, script);
    await reloadPlugins();
    final loaded = _plugins.any((p) => p.manifest.id == parsed.manifest.id);
    return loaded ? parsed.manifest.id : null;
  }

  static int _compareVersions(String a, String b) {
    final partsA = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final partsB = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < len; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va > vb) return 1;
      if (va < vb) return -1;
    }
    return 0;
  }

  Future<bool> deletePlugin(String pluginId) async {
    final index =
        _plugins.indexWhere((p) => p.manifest.id == pluginId);
    if (index < 0) return false;

    final plugin = _plugins[index];
    if (plugin.isBuiltin) return false;

    if (plugin.enabled) {
      await setPluginEnabled(pluginId, false);
    }
    await _unloadPluginRuntime(pluginId);

    final filePath = plugin.assetPath;
    if (filePath.startsWith(_loadedFilePrefix)) {
      final realPath = filePath.substring(_loadedFilePrefix.length);
      try {
        await _pluginStorage.deleteScript(realPath);
      } catch (_) {}
    }

    _plugins.removeAt(index);

    final enabledIds = _plugins
        .where((p) => p.enabled)
        .map((p) => p.manifest.id)
        .toList();
    await _saveEnabledIds(enabledIds);

    notifyListeners();
    return true;
  }

  Future<String?> getPluginDirectoryPath() async {
    return _pluginStorage.getPluginDirectoryPath();
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
    final result = PluginUiActionResult.fromJson(
      Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
    );

    final newBlockWords = _extractBlockWords(runtime);
    final newUiEntries = _extractUiEntries(runtime);
    if (newBlockWords.length != plugin.blockWords.length ||
        !_listEquals(newBlockWords, plugin.blockWords) ||
        !_pluginUiEntriesListEquals(newUiEntries, plugin.uiEntries)) {
      _plugins[index] = plugin.copyWith(
        blockWords: newBlockWords,
        uiEntries: newUiEntries,
      );
      notifyListeners();
    }

    return result;
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _pluginUiEntriesListEquals(
    List<PluginUiEntry> a,
    List<PluginUiEntry> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.title != y.title ||
          x.description != y.description ||
          x.enabled != y.enabled) {
        return false;
      }
    }
    return true;
  }

  _ParsedPluginMetadata _parsePluginMetadata(String script) {
    final runtime = createPluginRuntime();
    try {
      runtime.evaluate(script);
      final manifest = _extractManifest(runtime);
      final uiEntries = _extractUiEntries(runtime);
      return _ParsedPluginMetadata(
        manifest: manifest,
        uiEntries: uiEntries,
      );
    } catch (_) {
      rethrow;
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
        } catch (_) {}
      }
      return uiEntries;
    } catch (_) {
      return const <PluginUiEntry>[];
    }
  }

  Future<List<String>> _loadEnabledIds() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_enabledPluginsKey);
    if (saved == null) {
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
    _eventBus.dispose();
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

class _DiscoveredPluginScript {
  const _DiscoveredPluginScript({
    required this.path,
    required this.script,
  });

  final String path;
  final String script;
}