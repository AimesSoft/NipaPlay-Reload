import 'dart:convert';

class PluginIndexEntry {
  const PluginIndexEntry({
    required this.id,
    required this.version,
    required this.name,
    required this.installedAt,
    this.lastUpdatedAt,
    this.description,
    this.author,
    this.github,
  });

  final String id;
  final String version;
  final String name;
  final DateTime installedAt;
  final DateTime? lastUpdatedAt;
  final String? description;
  final String? author;
  final String? github;

  PluginIndexEntry copyWith({
    String? id,
    String? version,
    String? name,
    DateTime? installedAt,
    DateTime? lastUpdatedAt,
    String? description,
    String? author,
    String? github,
  }) {
    return PluginIndexEntry(
      id: id ?? this.id,
      version: version ?? this.version,
      name: name ?? this.name,
      installedAt: installedAt ?? this.installedAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      description: description ?? this.description,
      author: author ?? this.author,
      github: github ?? this.github,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'name': name,
      'installedAt': installedAt.toIso8601String(),
      'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
      'description': description,
      'author': author,
      'github': github,
    };
  }

  factory PluginIndexEntry.fromJson(Map<String, dynamic> json) {
    return PluginIndexEntry(
      id: json['id'] as String,
      version: json['version'] as String,
      name: json['name'] as String,
      installedAt: DateTime.parse(json['installedAt'] as String),
      lastUpdatedAt: json['lastUpdatedAt'] != null
          ? DateTime.parse(json['lastUpdatedAt'] as String)
          : null,
      description: json['description'] as String?,
      author: json['author'] as String?,
      github: json['github'] as String?,
    );
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }

  factory PluginIndexEntry.fromJsonString(String jsonString) {
    return PluginIndexEntry.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}
