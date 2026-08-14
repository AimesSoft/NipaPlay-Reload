import 'package:nipaplay/plugins/models/plugin_permission.dart';
import 'package:nipaplay/plugins/models/plugin_external_script.dart';

class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    this.github,
    this.minHostVersion = '1.0.0',
    this.permissions = const [],
    this.requires = const <PluginExternalScript>[],
    this.priority = 50,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String? github;
  final String minHostVersion;
  final List<PluginPermission> permissions;
  final List<PluginExternalScript> requires;
  final int priority;

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    final version = (json['version'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty || version.isEmpty) {
      throw const FormatException('invalid plugin manifest');
    }
    final description = (json['description'] ?? '').toString().trim();
    final author = (json['author'] ?? '').toString().trim();
    final githubRaw = json['github']?.toString().trim();
    final minHostVersion =
        (json['minHostVersion'] ?? '1.0.0').toString().trim();

    final permissionsJson = json['permissions'] as List? ?? [];
    final permissions = <PluginPermission>[];
    for (final permissionId in permissionsJson) {
      final permission =
          PluginPermission.fromId(permissionId.toString().trim());
      if (permission != null) {
        permissions.add(permission);
      }
    }

    final priority = json['priority'];
    final priorityValue = priority is num ? priority.toInt() : 50;

    final requiresJson = json['requires'] as List? ?? const [];
    final requires = <PluginExternalScript>[];
    final requireIds = <String>{};
    final requireUrls = <String>{};
    for (var i = 0; i < requiresJson.length; i++) {
      final item = requiresJson[i];
      if (item is! Map) {
        throw const FormatException(
            'pluginManifest.requires item is not object');
      }
      final script = PluginExternalScript.fromJson(
        Map<String, dynamic>.from(item),
        index: i,
      );
      if (!requireIds.add(script.id)) {
        throw FormatException('duplicate external script id: ${script.id}');
      }
      if (!requireUrls.add(script.url.toString())) {
        throw FormatException('duplicate external script URL: ${script.url}');
      }
      requires.add(script);
    }

    return PluginManifest(
      id: id,
      name: name,
      version: version,
      description: description,
      author: author,
      github: (githubRaw == null || githubRaw.isEmpty) ? null : githubRaw,
      minHostVersion: minHostVersion,
      permissions: permissions,
      requires: requires,
      priority: priorityValue,
    );
  }
}
