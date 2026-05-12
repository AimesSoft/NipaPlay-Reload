import 'package:nipaplay/plugins/models/plugin_permission.dart';

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
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String? github;
  final String minHostVersion;
  final List<PluginPermission> permissions;

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
      final permission = PluginPermission.fromId(permissionId.toString().trim());
      if (permission != null) {
        permissions.add(permission);
      }
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
    );
  }
}