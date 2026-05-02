class PluginUiEntry {
  const PluginUiEntry({
    required this.id,
    required this.title,
    this.description,
  });

  final String id;
  final String title;
  final String? description;

  factory PluginUiEntry.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('invalid plugin ui entry');
    }
    final descriptionRaw = json['description']?.toString().trim();
    return PluginUiEntry(
      id: id,
      title: title,
      description: (descriptionRaw == null || descriptionRaw.isEmpty)
          ? null
          : descriptionRaw,
    );
  }
}
