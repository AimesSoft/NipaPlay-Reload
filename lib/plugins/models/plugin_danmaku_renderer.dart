import 'package:flutter/foundation.dart';

import 'plugin_external_script.dart';
import '../danmaku/titan_danmaku_settings.dart';

/// A web-based danmaku renderer declared by an installed plugin.
///
/// The plugin control script is still evaluated by the normal plugin runtime;
/// Its external scripts and [bootstrap] adapter are loaded in an isolated
/// WebView only while this renderer is selected.
class PluginDanmakuRenderer {
  const PluginDanmakuRenderer({
    required this.pluginId,
    required this.id,
    required this.name,
    required this.description,
    required this.bootstrap,
    required this.externalScripts,
    required this.platforms,
    this.supportsRealtimeAdd = false,
    this.apiVersion = 1,
  });

  static const int supportedApiVersion = 1;
  static const String titanLocalSendPrefix = '🟩 ';
  static const String titanLocalSendSuffix = ' 🟩';

  final String pluginId;
  final String id;
  final String name;
  final String description;
  final String bootstrap;
  final List<PluginExternalScript> externalScripts;
  final Set<String> platforms;
  final bool supportsRealtimeAdd;
  final int apiVersion;

  String get selectionId => 'plugin:$pluginId/$id';

  /// Native danmaku owned by the active playback kernel (currently Erika)
  /// always takes precedence over a persisted plugin renderer selection.
  /// The selection itself is retained so it becomes effective again after
  /// switching back to a playback kernel without native danmaku.
  static PluginDanmakuRenderer? resolveForPlayback({
    required PluginDanmakuRenderer? selectedRenderer,
    required bool nativeDanmakuActive,
  }) {
    return nativeDanmakuActive ? null : selectedRenderer;
  }

  bool get usesTitanSettings =>
      pluginId == titanDanmakuPluginId && id == titanDanmakuRendererId;

  /// Prepares the transient copy sent to a renderer's realtime API.
  ///
  /// The submitted danmaku and the copy retained in the host timeline remain
  /// untouched. Titan receives a copy wrapped in self-colored green emoji
  /// because its bundled engine supports only one text color per danmaku. This
  /// keeps the user's selected color for the text while making the local send
  /// recognizable without requiring rich-text support from the engine.
  Map<String, dynamic> prepareRealtimeItem(Map<String, dynamic> item) {
    if (!usesTitanSettings) return item;
    final content = item['content']?.toString() ?? '';
    return <String, dynamic>{
      ...item,
      'content': '$titanLocalSendPrefix$content$titanLocalSendSuffix',
    };
  }

  bool shouldUseRealtimeAdd({
    required bool force,
    required int listVersion,
    required int locallySentListVersion,
    required int locallySentRevision,
    required int lastLocallySentRevision,
  }) {
    return !force &&
        supportsRealtimeAdd &&
        listVersion == locallySentListVersion &&
        locallySentRevision != lastLocallySentRevision;
  }

  bool get isSupportedOnCurrentPlatform {
    if (kIsWeb || apiVersion != supportedApiVersion) return false;
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => '',
    };
    return platform.isNotEmpty && platforms.contains(platform);
  }

  factory PluginDanmakuRenderer.fromJson({
    required String pluginId,
    required List<PluginExternalScript> availableScripts,
    required Map<String, dynamic> json,
  }) {
    final id = (json['id'] ?? '').toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    final bootstrap = (json['bootstrap'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty || bootstrap.isEmpty) {
      throw const FormatException('invalid plugin danmaku renderer');
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id)) {
      throw const FormatException('invalid renderer id');
    }
    final rawPlatforms = json['platforms'];
    final platforms = rawPlatforms is List
        ? rawPlatforms
            .map((item) => item.toString().trim().toLowerCase())
            .where((item) => item == 'android' || item == 'ios')
            .toSet()
        : <String>{};
    final requestedIds = (json['requires'] as List?)
        ?.map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final externalScripts = requestedIds == null
        ? availableScripts
        : availableScripts
            .where((script) => requestedIds.contains(script.id))
            .toList(growable: false);
    if (requestedIds != null && externalScripts.length != requestedIds.length) {
      throw const FormatException(
        'renderer references an unknown manifest dependency',
      );
    }

    return PluginDanmakuRenderer(
      pluginId: pluginId,
      id: id,
      name: name,
      description: (json['description'] ?? '').toString().trim(),
      bootstrap: bootstrap,
      externalScripts: externalScripts,
      platforms: platforms,
      supportsRealtimeAdd: json['supportsRealtimeAdd'] == true,
      apiVersion: (json['apiVersion'] as num?)?.toInt() ?? 1,
    );
  }
}
