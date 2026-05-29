import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
import 'package:nipaplay/plugins/models/plugin_index_entry.dart';
import 'package:nipaplay/plugins/models/remote_plugin_info.dart';
import 'package:nipaplay/plugins/plugin_event_bus.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/github_accel_resolver.dart';
import 'package:nipaplay/plugins/similarity_ffi_service.dart';
import 'package:http/http.dart' as http;

class PluginService extends ChangeNotifier {
  PluginService()
      : _eventBus = PluginEventBus() {
    _initialize();
    _setupEventListeners();
  }

  static const String _enabledPluginsKey = 'plugin_enabled_ids';
  static const String _downloaderOverrideKey = 'plugin_downloader_override';
  static const String _textSettingPrefix = 'plugin_text_setting_';
  static const String _switchSettingPrefix = 'plugin_switch_setting_';
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

  // 播放器状态引用，供插件桥接调用
  static dynamic _playerState;
  static void setPlayerState(dynamic state) => _playerState = state;
  static void clearPlayerState() => _playerState = null;
  static dynamic get playerState => _playerState;

  // BuildContext 引用，供 UI 桥接（如 BlurSnackBar）使用
  static BuildContext? _buildContext;
  static void setBuildContext(BuildContext context) => _buildContext = context;

  static Future<void> _saveDownloaderOverride(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_downloaderOverrideKey, value);
  }

  final List<PluginDescriptor> _plugins = <PluginDescriptor>[];
  final Map<String, PluginJsRuntime> _runtimeByPluginId =
      <String, PluginJsRuntime>{};
  final Map<String, String> _scriptByPluginId = <String, String>{};
  final Map<String, String> _textSettingValues = <String, String>{};
  final Map<String, bool> _switchSettingValues = <String, bool>{};
  final PluginStorage _pluginStorage = createPluginStorage();
  final PluginEventBus _eventBus;

  bool _isLoaded = false;
  Map<String, PluginIndexEntry> _pluginIndex = {};
  Map<String, RemotePluginInfo> _remotePlugins = {};
  List<Map<String, dynamic>>? _pendingDanmakuData;

  bool get isLoaded => _isLoaded;

  List<PluginDescriptor> get plugins => List<PluginDescriptor>.unmodifiable(
        _plugins,
      );

  PluginEventBus get eventBus => _eventBus;

  List<Map<String, dynamic>>? get pendingDanmakuData => _pendingDanmakuData;

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

  String getTextSettingValue(String pluginId, String entryId) {
    return _textSettingValues['$pluginId::$entryId'] ?? '';
  }

  Future<void> setTextSettingValue(
      String pluginId, String entryId, String value) async {
    final key = '$pluginId::$entryId';
    _textSettingValues[key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_textSettingPrefix$key', value);
    notifyListeners();
  }

  bool getSwitchSettingValue(String pluginId, String entryId) {
    return _switchSettingValues['$pluginId::$entryId'] ?? false;
  }

  Future<void> setSwitchSettingValue(
      String pluginId, String entryId, bool value) async {
    final key = '$pluginId::$entryId';
    _switchSettingValues[key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_switchSettingPrefix$key', value);
    notifyListeners();
  }

  Future<void> _loadTextSettingValues() async {
    final prefs = await SharedPreferences.getInstance();
    for (final plugin in _plugins) {
      for (final entry in plugin.uiEntries) {
        if (!entry.isTextInput) continue;
        final key = '${plugin.manifest.id}::${entry.id}';
        final saved = prefs.getString('$_textSettingPrefix$key');
        if (saved != null) {
          _textSettingValues[key] = saved;
        } else {
          final def = entry.textSetting?.defaultValue;
          if (def != null && def.isNotEmpty) {
            _textSettingValues[key] = def;
          }
        }
      }
    }
  }

  Future<void> _loadSwitchSettingValues() async {
    final prefs = await SharedPreferences.getInstance();
    for (final plugin in _plugins) {
      for (final entry in plugin.uiEntries) {
        if (!entry.isSwitch) continue;
        final key = '${plugin.manifest.id}::${entry.id}';
        final saved = prefs.getBool('$_switchSettingPrefix$key');
        if (saved != null) {
          _switchSettingValues[key] = saved;
        } else if (entry.enabled != null) {
          _switchSettingValues[key] = entry.enabled!;
        }
      }
    }
  }

  bool hasPermission(String pluginId, PluginPermission permission) {
    final plugin = _plugins.firstWhere(
      (p) => p.manifest.id == pluginId,
      orElse: () => throw StateError('插件不存在: $pluginId'),
    );
    return plugin.manifest.permissions.contains(permission);
  }

  Future<void> _initialize() async {
    _pluginIndex = await _pluginStorage.loadPluginIndex();
    await _reloadPlugins();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> reloadPlugins() async {
    await _reloadPlugins();
    notifyListeners();
  }

  Map<String, PluginIndexEntry> get pluginIndex =>
      Map.unmodifiable(_pluginIndex);

  PluginIndexEntry? getPluginIndexEntry(String pluginId) {
    return _pluginIndex[pluginId];
  }

  Future<void> _savePluginIndex() async {
    await _pluginStorage.savePluginIndex(_pluginIndex);
  }

  Future<void> addOrUpdatePluginIndex(PluginManifest manifest) async {
    final now = DateTime.now();
    if (_pluginIndex.containsKey(manifest.id)) {
      final existing = _pluginIndex[manifest.id]!;
      _pluginIndex[manifest.id] = existing.copyWith(
        version: manifest.version,
        name: manifest.name,
        description: manifest.description,
        author: manifest.author,
        github: manifest.github,
        lastUpdatedAt: now,
      );
    } else {
      _pluginIndex[manifest.id] = PluginIndexEntry(
        id: manifest.id,
        version: manifest.version,
        name: manifest.name,
        installedAt: now,
        description: manifest.description,
        author: manifest.author,
        github: manifest.github,
      );
    }
    await _savePluginIndex();
  }

  Future<void> removePluginFromIndex(String pluginId) async {
    _pluginIndex.remove(pluginId);
    await _savePluginIndex();
  }

  static const String _pluginsIndexUrl =
      'https://raw.githubusercontent.com/AimesSoft/Nipaplay-plugins/refs/heads/main/plugins.json';

  Future<void> fetchRemotePlugins({String? proxyUrl}) async {
    try {
      if (proxyUrl != null && proxyUrl.trim().isNotEmpty) {
        final url = _applyProxyIfNeeded(_pluginsIndexUrl, proxyUrl);
        await _fetchPluginsFromUrl(url);
        return;
      }

      // Try canonical URL first, fall back to mirrors.
      try {
        final response =
            await http.get(Uri.parse(_pluginsIndexUrl)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          _processPluginIndexResponse(response);
          return;
        }
      } catch (_) {
        // Direct fetch failed, try mirrors below.
      }

      final mirrorUrl =
          await GithubAccelResolver.resolveFirstReachable(_pluginsIndexUrl);
      if (mirrorUrl != null) {
        await _fetchPluginsFromUrl(mirrorUrl);
      }
    } catch (_) {}
  }

  Future<void> _fetchPluginsFromUrl(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      _processPluginIndexResponse(response);
    }
  }

  void _processPluginIndexResponse(http.Response response) {
    final dynamic jsonData = json.decode(response.body);
    List<dynamic> data;
    if (jsonData is List) {
      data = jsonData;
    } else if (jsonData is Map) {
      if (jsonData.containsKey('plugins')) {
        data = jsonData['plugins'] as List;
      } else if (jsonData.containsKey('data')) {
        data = jsonData['data'] as List;
      } else {
        data = [];
      }
    } else {
      data = [];
    }
    final remotePlugins = RemotePluginInfo.fromJsonList(data);
    _remotePlugins = {
      for (final plugin in remotePlugins) plugin.id: plugin,
    };
  }

  String _applyProxyIfNeeded(String url, String? proxyUrl) {
    if (proxyUrl == null || proxyUrl.trim().isEmpty) {
      return url;
    }
    final normalizedProxy = proxyUrl.endsWith('/') ? proxyUrl : '$proxyUrl/';
    return '$normalizedProxy$url';
  }

  String? getAvailableUpdateVersion(String pluginId) {
    RemotePluginInfo? remote = _remotePlugins[pluginId];
    if (remote == null) {
      final dotIndex = pluginId.indexOf('.');
      if (dotIndex >= 0 && dotIndex < pluginId.length - 1) {
        remote = _remotePlugins[pluginId.substring(dotIndex + 1)];
      }
    }
    if (remote == null) return null;

    final localEntry = _pluginIndex[pluginId];
    if (localEntry == null) return null;

    final localVersion = localEntry.version;
    final remoteVersion = remote.version;

    if (_compareVersions(remoteVersion, localVersion) > 0) {
      return remoteVersion;
    }
    return null;
  }

  RemotePluginInfo? getRemotePluginInfo(String pluginId) {
    return _remotePlugins[pluginId];
  }

  Map<String, RemotePluginInfo> get remotePlugins =>
      Map.unmodifiable(_remotePlugins);

  void _setupEventListeners() {
    _eventBus.on(PluginEventType.videoLoaded, _handleEvent);
    _eventBus.on(PluginEventType.play, _handleEvent);
    _eventBus.on(PluginEventType.pause, _handleEvent);
    _eventBus.on(PluginEventType.seek, _handleEvent);
    _eventBus.on(PluginEventType.danmakuShow, _handleEvent);
    _eventBus.on(PluginEventType.danmakuLoaded, _handleDanmakuLoadedEvent);
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

  dynamic _handlePluginBridgeCall(String pluginId, dynamic args) {
    if (args is! Map) return null;

    final method = args['method'] as String? ?? '';
    final callArgs = (args['args'] as List?)?.cast<dynamic>() ?? <dynamic>[];

    switch (method) {
      // ---- 播放器控制 ----
      case 'playerPlay':
        try { _playerState?.play(); } catch (_) {}
        return null;
      case 'playerPause':
        try { _playerState?.pause(); } catch (_) {}
        return null;
      case 'playerSeek':
        if (callArgs.isNotEmpty) {
          final seconds = (callArgs[0] as num?)?.toDouble() ?? 0;
          try { _playerState?.seekTo(Duration(milliseconds: (seconds * 1000).round())); } catch (_) {}
        }
        return null;
      case 'playerGetState':
        try {
          final ps = _playerState;
          if (ps == null) return null;
          return json.encode({
            'position': (ps.position as Duration).inMilliseconds / 1000.0,
            'duration': (ps.duration as Duration).inMilliseconds / 1000.0,
            'status': ps.status.toString().split('.').last,
            'hasVideo': ps.hasVideo,
          });
        } catch (_) { return null; }

      // ---- 弹幕控制 ----
      case 'danmakuShow':
        try { _playerState?.setDanmakuVisible(true); } catch (_) {}
        return null;
      case 'danmakuHide':
        try { _playerState?.setDanmakuVisible(false); } catch (_) {}
        return null;
      case 'danmakuSetOpacity':
        if (callArgs.isNotEmpty) {
          final opacity = (callArgs[0] as num?)?.toDouble().clamp(0.0, 1.0) ?? 1.0;
          try { _playerState?.setDanmakuOpacity(opacity); } catch (_) {}
        }
        return null;
      case 'danmakuAddFilter':
        if (callArgs.length >= 2) {
          final word = callArgs[1]?.toString() ?? '';
          if (word.isNotEmpty) {
            try { unawaited(_playerState?.addDanmakuBlockWord(word)); } catch (_) {}
          }
        }
        return null;
      case 'danmakuRemoveFilter':
        if (callArgs.isNotEmpty) {
          final word = callArgs[0]?.toString() ?? '';
          if (word.isNotEmpty) {
            try { unawaited(_playerState?.removeDanmakuBlockWord(word)); } catch (_) {}
          }
        }
        return null;
      case 'danmakuReplace':
        if (callArgs.isNotEmpty) {
          try {
            final decoded = json.decode(callArgs[0].toString());
            if (decoded is Map) {
              final data = Map<String, dynamic>.from(decoded as Map<String, dynamic>);
              final comments = data['comments'];
              if (comments is List) {
                final normalized = comments.whereType<Map>().map((e) {
                  final m = Map<String, dynamic>.from(e);
                  if (m['time'] is num) {
                    m['time'] = (m['time'] as num).toDouble();
                  }
                  return m;
                }).toList();
                updateDanmakuData(normalized);
                return true;
              }
            }
          } catch (_) {}
        }
        return false;

      // ---- UI ----
      case 'uiShowToast':
        if (callArgs.isNotEmpty) {
          final message = callArgs[0]?.toString() ?? '';
          final ctx = _buildContext;
          if (ctx != null && ctx.mounted) {
            BlurSnackBar.show(ctx, message);
          } else {
            debugPrint('[Plugin:${pluginId}] $message');
          }
        }
        return null;
      case 'uiShowDialog':
        // 需要 BuildContext，暂不支持
        return false;
      case 'uiShowLoading':
        if (callArgs.isNotEmpty) {
          final message = callArgs[0]?.toString() ?? '';
          final ctx = _buildContext;
          if (ctx != null && ctx.mounted) {
            BlurSnackBar.show(ctx, message);
          } else {
            debugPrint('[Plugin:${pluginId}] $message');
          }
        }
        return null;
      case 'uiHideLoading':
        return null;

      // ---- 存储 ----
      case 'storageSet':
        if (callArgs.length >= 2) {
          final key = 'plugin_${pluginId}_${callArgs[0]}';
          final value = callArgs[1]?.toString() ?? '';
          unawaited(SharedPreferences.getInstance().then(
            (prefs) => prefs.setString(key, value),
          ));
          return true;
        }
        return false;
      case 'storageGet':
        if (callArgs.isNotEmpty) {
          final key = 'plugin_${pluginId}_${callArgs[0]}';
          // 同步桥接无法 await，用已缓存的值或返回 null
          // 插件应仅在初始化时读取，此时值应已加载
          return null;
        }
        return null;
      case 'storageRemove':
        if (callArgs.isNotEmpty) {
          final key = 'plugin_${pluginId}_${callArgs[0]}';
          unawaited(SharedPreferences.getInstance().then(
            (prefs) => prefs.remove(key),
          ));
          return true;
        }
        return false;
      case 'storageClear':
        unawaited(SharedPreferences.getInstance().then((prefs) async {
          final keys = prefs.getKeys()
              .where((k) => k.startsWith('plugin_${pluginId}_'))
              .toList();
          for (final k in keys) {
            await prefs.remove(k);
          }
        }));
        return true;

      // ---- 系统 ----
      case 'systemSetDownloaderEnabled':
        if (callArgs.isNotEmpty) {
          final enabled = callArgs[0] == true || callArgs[0]?.toString() == 'true';
          setForceEnableDownloader(enabled);
          notifyListeners();
        }
        return null;

      // ---- 插件设置 ----
      case 'pluginGetTextSetting':
        if (callArgs.isNotEmpty) {
          return getTextSettingValue(pluginId, callArgs[0].toString());
        }
        return '';
      case 'pluginSetTextSetting':
        if (callArgs.length >= 2) {
          unawaited(setTextSettingValue(
            pluginId,
            callArgs[0].toString(),
            callArgs[1].toString(),
          ));
        }
        return null;

      // ---- 插件开关设置 ----
      case 'pluginGetSwitchSetting':
        if (callArgs.isNotEmpty) {
          return getSwitchSettingValue(pluginId, callArgs[0].toString());
        }
        return false;
      case 'pluginSetSwitchSetting':
        if (callArgs.length >= 2) {
          final value = callArgs[1] == true || callArgs[1]?.toString() == 'true';
          unawaited(setSwitchSettingValue(
            pluginId,
            callArgs[0].toString(),
            value,
          ));
        }
        return null;

      // ---- 调试 ----
      case 'devLog':
        if (callArgs.isNotEmpty) {
          debugPrint('[Plugin:${pluginId}] ${callArgs[0]}');
        }
        return null;
      case 'devLogError':
        if (callArgs.isNotEmpty) {
          debugPrint('[Plugin:${pluginId}] ERROR: ${callArgs[0]}');
        }
        return null;

      // ---- 弹幕相似度查重 ----
      case 'danmakuSimilarityAvailable':
        return SimilarityFfiService.instance.available;
      case 'danmakuCheckSimilarity':
        if (callArgs.length >= 2) {
          try {
            final items = json.decode(callArgs[0].toString());
            final config = json.decode(callArgs[1].toString());
            if (items is List && config is Map) {
              final result = SimilarityFfiService.instance.checkSimilarity(
                items.cast<Map<String, dynamic>>(),
                Map<String, dynamic>.from(config),
              );
              return result;
            }
          } catch (e) {
            debugPrint('[Plugin:${pluginId}] danmakuCheckSimilarity 错误: $e');
          }
        }
        return '{}';
      case 'danmakuPairSimilarity':
        if (callArgs.length >= 2) {
          try {
            final textA = callArgs[0]?.toString() ?? '';
            final textB = callArgs[1]?.toString() ?? '';
            final usePinyin = callArgs.length < 3 || callArgs[2] != false;
            final score = SimilarityFfiService.instance.pairSimilarity(
              textA, textB, usePinyin: usePinyin,
            );
            return score.toString();
          } catch (e) {
            debugPrint('[Plugin:${pluginId}] danmakuPairSimilarity 错误: $e');
          }
        }
        return '0';

      default:
        debugPrint('[Plugin:${pluginId}] 未处理的桥接方法: $method');
        return null;
    }
  }

  void _handleDanmakuLoadedEvent(PluginEvent event) {
    final rawDanmaku = event.data['danmaku'];
    if (rawDanmaku is List) {
      _pendingDanmakuData = rawDanmaku
          .whereType<Map<String, dynamic>>()
          .toList();
    } else {
      _pendingDanmakuData = null;
    }
    // 按 priority 升序排列插件，低优先级先执行
    final sortedPlugins = _plugins
        .where((p) =>
            p.enabled &&
            p.loaded &&
            p.manifest.permissions.any((perm) => perm.id == 'danmaku.modify') &&
            _runtimeByPluginId[p.manifest.id] != null)
        .toList()
      ..sort((a, b) => a.manifest.priority.compareTo(b.manifest.priority));

    for (final plugin in sortedPlugins) {
      final runtime = _runtimeByPluginId[plugin.manifest.id]!;

      // 链式管道：将前序插件的累积结果作为本次事件数据传递
      if (_pendingDanmakuData != null) {
        event.data['danmaku'] = _pendingDanmakuData;
      }

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
    notifyListeners();
  }

  void updateDanmakuData(List<Map<String, dynamic>>? newDanmaku) {
    _pendingDanmakuData = newDanmaku;
    notifyListeners();
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

    await _loadTextSettingValues();
    await _loadSwitchSettingValues();

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

  static const String _downloaderUnlockPluginId = 'custom.downloader_unlock';

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

    if (pluginId == _downloaderUnlockPluginId) {
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

      runtime.setupBridge('PluginBridge', (args) {
        return _handlePluginBridgeCall(pluginId, args);
      });

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
      function flutter_invokeMethod(method) {
        var args = [];
        for (var i = 1; i < arguments.length; i++) {
          args.push(arguments[i]);
        }
        var result = sendMessage('PluginBridge', JSON.stringify({ method: method, args: args }));
        return result;
      }

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
          return flutter_invokeMethod('playerPlay');
        },
        pause: function() {
          if (!plugin.hasPermission('player.control')) return false;
          return flutter_invokeMethod('playerPause');
        },
        seek: function(time) {
          if (!plugin.hasPermission('player.control')) return false;
          return flutter_invokeMethod('playerSeek', time);
        },
        getState: function() {
          if (!plugin.hasPermission('player.control')) return null;
          return JSON.parse(flutter_invokeMethod('playerGetState') || 'null');
        },
      };

      const danmaku = {
        show: function() {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return flutter_invokeMethod('danmakuShow');
        },
        hide: function() {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return flutter_invokeMethod('danmakuHide');
        },
        setOpacity: function(opacity) {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return flutter_invokeMethod('danmakuSetOpacity', opacity);
        },
        addFilter: function(filterId, pattern) {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return flutter_invokeMethod('danmakuAddFilter', filterId, pattern);
        },
        removeFilter: function(filterId) {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return flutter_invokeMethod('danmakuRemoveFilter', filterId);
        },
        replace: function(newDanmaku) {
          if (!plugin.hasPermission('danmaku.modify')) return false;
          return flutter_invokeMethod('danmakuReplace', JSON.stringify(newDanmaku));
        },
        similarityAvailable: function() {
          return !!flutter_invokeMethod('danmakuSimilarityAvailable');
        },
        checkSimilarity: function(danmakuList, config) {
          if (!plugin.hasPermission('danmaku.modify')) return null;
          var result = flutter_invokeMethod('danmakuCheckSimilarity',
            JSON.stringify(danmakuList), JSON.stringify(config || {}));
          return result ? JSON.parse(result) : null;
        },
        pairSimilarity: function(textA, textB, usePinyin) {
          if (!plugin.hasPermission('danmaku.modify')) return 0;
          var result = flutter_invokeMethod('danmakuPairSimilarity',
            textA, textB, usePinyin !== false);
          return result ? parseFloat(result) : 0;
        },
      };

      const ui = {
        showSnackBar: function(message) {
          if (!plugin.hasPermission('ui.dialog')) return;
          flutter_invokeMethod('uiShowToast', message);
        },
        showDialog: function(title, content) {
          if (!plugin.hasPermission('ui.dialog')) return false;
          return JSON.parse(flutter_invokeMethod('uiShowDialog', title, content) || 'false');
        },
        showLoading: function(message) {
          if (!plugin.hasPermission('ui.dialog')) return;
          flutter_invokeMethod('uiShowLoading', message);
        },
        hideLoading: function() {
          if (!plugin.hasPermission('ui.dialog')) return;
          flutter_invokeMethod('uiHideLoading');
        },
      };

      const storage = {
        set: function(key, value) {
          if (!plugin.hasPermission('storage')) return false;
          return flutter_invokeMethod('storageSet', key, JSON.stringify(value));
        },
        get: function(key) {
          if (!plugin.hasPermission('storage')) return null;
          var result = flutter_invokeMethod('storageGet', key);
          return result ? JSON.parse(result) : null;
        },
        remove: function(key) {
          if (!plugin.hasPermission('storage')) return false;
          return flutter_invokeMethod('storageRemove', key);
        },
        clear: function() {
          if (!plugin.hasPermission('storage')) return false;
          return flutter_invokeMethod('storageClear');
        },
      };

      const dev = {
        log: function(message) {
          flutter_invokeMethod('devLog', message);
        },
        logError: function(error) {
          flutter_invokeMethod('devLogError', error);
        },
      };

      const system = {
        setDownloaderEnabled: function(enabled) {
          if (!plugin.hasPermission('system.override')) return false;
          return flutter_invokeMethod('systemSetDownloaderEnabled', enabled);
        },
      };

      const settings = {
        getText: function(entryId) {
          return flutter_invokeMethod('pluginGetTextSetting', entryId) || '';
        },
        setText: function(entryId, value) {
          flutter_invokeMethod('pluginSetTextSetting', entryId, String(value));
        },
        getSwitch: function(entryId) {
          return !!flutter_invokeMethod('pluginGetSwitchSetting', entryId);
        },
        setSwitch: function(entryId, value) {
          flutter_invokeMethod('pluginSetSwitchSetting', entryId, !!value);
        },
      };

      const __pluginServices = {
        player,
        danmaku,
        ui,
        storage,
        dev,
        system,
        settings,
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

  Future<String?> importPluginFromContent(String script,
      {String? updateForId}) async {
    return _importPluginFromContent(script, updateForId: updateForId);
  }

  Future<String?> _importPluginFromContent(String script,
      {String? updateForId}) async {
    final parsed = _parsePluginMetadata(script);
    final manifest = parsed.manifest;
    final minVersion = manifest.minHostVersion;
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    if (_compareVersions(currentVersion, minVersion) < 0) {
      throw StateError(
        '当前应用版本 $currentVersion 低于插件要求的最低版本 $minVersion',
      );
    }

    String? existingLocalId;
    if (_pluginIndex.containsKey(manifest.id)) {
      existingLocalId = manifest.id;
    } else if (updateForId != null && _pluginIndex.containsKey(updateForId)) {
      existingLocalId = updateForId;
    } else {
      for (final prefix in ['custom.', 'builtin.']) {
        final prefixedId = '$prefix${manifest.id}';
        if (_pluginIndex.containsKey(prefixedId)) {
          existingLocalId = prefixedId;
          break;
        }
      }
    }

    if (existingLocalId != null) {
      final existing = _pluginIndex[existingLocalId]!;
      if (_compareVersions(manifest.version, existing.version) <= 0) {
        throw StateError(
          '当前已安装版本 ${existing.version} 不低于插件版本 ${manifest.version}',
        );
      }
      if (existingLocalId != manifest.id) {
        final pluginDir = await _pluginStorage.getPluginDirectoryPath();
        if (pluginDir != null) {
          await _pluginStorage
              .deleteScript('$pluginDir/${existingLocalId}.js');
        }
        await removePluginFromIndex(existingLocalId);
        final enabledIds = await _loadEnabledIds();
        if (enabledIds.contains(existingLocalId)) {
          enabledIds.remove(existingLocalId);
          if (!enabledIds.contains(manifest.id)) {
            enabledIds.add(manifest.id);
          }
          await _saveEnabledIds(enabledIds);
        }
      }
    }

    final fileName = '${manifest.id}.js';
    await _pluginStorage.saveScript(fileName, script);
    await addOrUpdatePluginIndex(manifest);
    await reloadPlugins();
    final loaded = _plugins.any((p) => p.manifest.id == manifest.id);
    return loaded ? manifest.id : null;
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

    await removePluginFromIndex(pluginId);

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
          x.enabled != y.enabled ||
          x.textSetting?.hintText != y.textSetting?.hintText ||
          x.textSetting?.defaultValue != y.textSetting?.defaultValue) {
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
