import 'plugin_manifest.dart';
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
  });

  final PluginManifest manifest;
  final String assetPath;
  final bool isBuiltin;
  final bool enabled;
  final bool loaded;
  final String? errorMessage;
  final List<String> blockWords;
  final List<PluginUiEntry> uiEntries;

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
    );
  }
}
