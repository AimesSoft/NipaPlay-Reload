import 'dart:convert';

class RemotePluginInfo {
  const RemotePluginInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.minHostVersion,
    required this.downloadUrl,
    this.tags = const [],
    this.github,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String minHostVersion;
  final String downloadUrl;
  final List<String> tags;
  final String? github;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'description': description,
      'author': author,
      'minHostVersion': minHostVersion,
      'downloadUrl': downloadUrl,
      'tags': tags,
      'github': github,
    };
  }

  factory RemotePluginInfo.fromJson(Map<String, dynamic> json) {
    return RemotePluginInfo(
      id: (json['id'] ?? '').toString().trim(),
      name: (json['name'] ?? '').toString().trim(),
      version: (json['version'] ?? '1.0.0').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      author: (json['author'] ?? '').toString().trim(),
      minHostVersion: (json['minHostVersion'] ?? '1.0.0').toString().trim(),
      downloadUrl: (json['downloadUrl'] ?? '').toString().trim(),
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .toList() ??
          [],
      github: json['github']?.toString().trim(),
    );
  }

  static List<RemotePluginInfo> fromJsonList(List<dynamic> jsonList) {
    return jsonList
        .map((item) {
          if (item is Map<String, dynamic>) {
            try {
              return RemotePluginInfo.fromJson(item);
            } catch (_) {
              return null;
            }
          }
          return null;
        })
        .where((e) => e != null)
        .map((e) => e!)
        .toList();
  }
}
