import 'plugin_manifest.dart';
import 'plugin_danmaku_renderer.dart';
import 'plugin_external_script.dart';
import 'plugin_ui_entry.dart';

class PluginDescriptor {
  const PluginDescriptor({
    required this.manifest,
    required this.assetPath,
    required this.isBuiltin,
    required this.enabled,
    required this.loaded,
    required this.errorMessage,
    required this.blockWords,
    required this.uiEntries,
    this.danmakuRenderers = const <PluginDanmakuRenderer>[],
    this.externalScripts = const <PluginExternalScript>[],
  });

  final PluginManifest manifest;
  final String assetPath;
  final bool isBuiltin;
  final bool enabled;
  final bool loaded;
  final String? errorMessage;
  final List<String> blockWords;
  final List<PluginUiEntry> uiEntries;
  final List<PluginDanmakuRenderer> danmakuRenderers;
  final List<PluginExternalScript> externalScripts;

  PluginDescriptor copyWith({
    PluginManifest? manifest,
    String? assetPath,
    bool? isBuiltin,
    bool? enabled,
    bool? loaded,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<String>? blockWords,
    List<PluginUiEntry>? uiEntries,
    List<PluginDanmakuRenderer>? danmakuRenderers,
    List<PluginExternalScript>? externalScripts,
  }) {
    return PluginDescriptor(
      manifest: manifest ?? this.manifest,
      assetPath: assetPath ?? this.assetPath,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      enabled: enabled ?? this.enabled,
      loaded: loaded ?? this.loaded,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      blockWords: blockWords ?? this.blockWords,
      uiEntries: uiEntries ?? this.uiEntries,
      danmakuRenderers: danmakuRenderers ?? this.danmakuRenderers,
      externalScripts: externalScripts ?? this.externalScripts,
    );
  }
}
