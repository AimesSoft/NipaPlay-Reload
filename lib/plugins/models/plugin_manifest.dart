class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    this.github,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String? github;

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
    return PluginManifest(
      id: id,
      name: name,
      version: version,
      description: description,
      author: author,
      github: (githubRaw == null || githubRaw.isEmpty) ? null : githubRaw,
    );
  }
}
