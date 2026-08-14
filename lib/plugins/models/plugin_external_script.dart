class PluginExternalScript {
  const PluginExternalScript({
    required this.id,
    required this.url,
    this.sha256,
  });

  final String id;
  final Uri url;
  final String? sha256;

  factory PluginExternalScript.fromJson(
    Map<String, dynamic> json, {
    required int index,
  }) {
    final url = Uri.tryParse((json['url'] ?? '').toString().trim());
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const FormatException('external script must use HTTPS');
    }
    final id = (json['id'] ?? 'require$index').toString().trim();
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id)) {
      throw const FormatException('invalid external script id');
    }
    final rawHash = (json['sha256'] ?? '').toString().trim().toLowerCase();
    if (rawHash.isNotEmpty && !RegExp(r'^[a-f0-9]{64}$').hasMatch(rawHash)) {
      throw const FormatException('sha256 must be 64 hexadecimal characters');
    }
    return PluginExternalScript(
      id: id,
      url: url,
      sha256: rawHash.isEmpty ? null : rawHash,
    );
  }
}
