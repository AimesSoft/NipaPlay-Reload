import 'credential_vault.dart';

/// Values are kept only in process memory, to remove them from diagnostic text.
final class SecretRedactor {
  static final Map<String, CredentialRef> _known = {};
  static void remember(CredentialRef ref, String value) {
    if (value.isNotEmpty) _known[value] = ref;
  }

  static Object? json(Object? value, [String path = '']) {
    if (credentialReference(value) != null) return value;
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key as String:
              RegExp(r'^(password|secret|token|access_?token|api_?key|apiToken|webToken|authorization)$',
                              caseSensitive: false)
                          .hasMatch(entry.key.toString()) &&
                      entry.value != null
                  ? CredentialRef('diagnostic', '$path/${entry.key}')
                      .placeholder
                  : json(entry.value, '$path/${entry.key}')
      };
    }
    if (value is List) {
      return [
        for (var i = 0; i < value.length; i++) json(value[i], '$path/$i')
      ];
    }
    if (value is String) {
      final ref = _known[value];
      if (ref != null) return ref.placeholder;
      if (text(value) != value) {
        return CredentialRef('diagnostic', path).placeholder;
      }
    }
    return value;
  }

  static String text(String message) {
    var result = message;
    final values = _known.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final value in values) {
      final replacement = _known[value]!.toString();
      result = result.replaceAll(value, replacement);
      result = result.replaceAll(Uri.encodeComponent(value), replacement);
      result = result.replaceAll(Uri.encodeQueryComponent(value), replacement);
    }
    result = result.replaceAllMapped(
        RegExp(r'\b(?:Bearer|Basic)\s+[A-Za-z0-9+/_.=-]+',
            caseSensitive: false),
        (_) => 'CredentialRef(diagnostic, authorization)');
    result = result.replaceAllMapped(
        RegExp(
            r'''((?:api[_-]?key|access[_-]?token|webtoken|token|password|authorization)["']?\s*[=:]\s*)(["'])(.*?)\2''',
            caseSensitive: false, dotAll: true),
        (match) =>
            '${match[1]}${match[2]}CredentialRef(diagnostic, secret)${match[2]}');
    result = result.replaceAllMapped(
        RegExp(
            r'''((?:api[_-]?key|access[_-]?token|webtoken|token|password|authorization)["']?\s*[=:]\s*["']?)([^\s&"',}\]]+)''',
            caseSensitive: false),
        (match) => '${match[1]}CredentialRef(diagnostic, secret)');
    result = result.replaceAllMapped(
        RegExp(r'Bearer\s+[^\s"\x27,}]+', caseSensitive: false),
        (_) => 'CredentialRef(diagnostic, authorization)');
    result = result.replaceAllMapped(RegExp(r'(\w+://)[^\s/@]+:[^\s/@]+@'),
        (match) => '${match[1]}CredentialRef(diagnostic, userinfo)@');
    return result;
  }
}
