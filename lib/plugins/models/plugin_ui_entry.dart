class PluginTextSetting {
  const PluginTextSetting({
    this.hintText,
    this.defaultValue,
  });

  final String? hintText;
  final String? defaultValue;

  factory PluginTextSetting.fromJson(Map<String, dynamic> json) {
    final hintText = json['hintText']?.toString().trim();
    final defaultValue = json['default']?.toString();
    return PluginTextSetting(
      hintText: (hintText == null || hintText.isEmpty) ? null : hintText,
      defaultValue: defaultValue,
    );
  }
}

class PluginUiEntry {
  const PluginUiEntry({
    required this.id,
    required this.title,
    this.description,
    this.enabled,
    this.textSetting,
  });

  final String id;
  final String title;
  final String? description;
  final bool? enabled;
  final PluginTextSetting? textSetting;

  bool get isSwitch => enabled != null;
  bool get isTextInput => enabled == null && textSetting != null;
  bool get isAction => enabled == null && textSetting == null;

  factory PluginUiEntry.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('invalid plugin ui entry');
    }
    final descriptionRaw = json['description']?.toString().trim();
    final enabledRaw = json['enabled'];

    PluginTextSetting? textSetting;
    if (enabledRaw is! bool && json['textSetting'] is Map) {
      textSetting = PluginTextSetting.fromJson(
        Map<String, dynamic>.from(json['textSetting'] as Map),
      );
    }

    return PluginUiEntry(
      id: id,
      title: title,
      description: (descriptionRaw == null || descriptionRaw.isEmpty)
          ? null
          : descriptionRaw,
      enabled: enabledRaw is bool ? enabledRaw : null,
      textSetting: textSetting,
    );
  }
}
