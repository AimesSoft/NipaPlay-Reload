class PluginUiActionResult {
  const PluginUiActionResult({
    required this.type,
    required this.title,
    required this.content,
  });

  final String type;
  final String title;
  final String content;

  factory PluginUiActionResult.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    final content = (json['content'] ?? '').toString().trim();
    if (type.isEmpty || title.isEmpty) {
      throw const FormatException('invalid plugin ui action result');
    }
    if (type != 'text') {
      throw FormatException('unsupported plugin ui action type: $type');
    }
    return PluginUiActionResult(
      type: type,
      title: title,
      content: content,
    );
  }
}
