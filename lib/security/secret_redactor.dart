import 'credential_vault.dart';

/// Values are kept only in process memory, to remove them from diagnostic text.
final class SecretRedactor {
  static final Map<String, CredentialRef> _known = {};
  static List<String>? _sorted;
  static final Map<String, List<String>> _variants = {};

  static void remember(CredentialRef ref, String value) {
    if (value.isNotEmpty) {
      _known[value] = ref;
      _sorted = null;
    }
  }

  static final _secretKey = RegExp(
      r'^(password|secret|token|access_?token|api_?key|apiToken|webToken|authorization)$',
      caseSensitive: false);

  static Object? json(Object? value, [String path = '']) {
    if (credentialReference(value) != null) return value;
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key as String: _secretKey.hasMatch(entry.key.toString()) &&
                  entry.value != null
              ? CredentialRef('diagnostic', '$path/${entry.key}').placeholder
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

  static final _bearerBasic =
      RegExp(r'\b(?:Bearer|Basic)\s+[A-Za-z0-9+/_.=-]+', caseSensitive: false);

  // A quoted value ends at the first matching quote. Matching "anything but
  // the quote" under a ceiling keeps every candidate bounded; the former lazy
  // `.*?` with a back-reference scanned to the end of the text for each
  // unpaired quote, which was quadratic. A value that is unclosed, or longer
  // than the ceiling, falls through to the unquoted rule below.
  static final _quotedSecret = RegExp(
      r'''((?:api[_-]?key|access[_-]?token|webtoken|token|password|authorization)["']?\s*[=:]\s*)(?:(")[^"]{0,4096}"|(')[^']{0,4096}')''',
      caseSensitive: false);
  static final _bareSecret = RegExp(
      r'''((?:api[_-]?key|access[_-]?token|webtoken|token|password|authorization)["']?\s*[=:]\s*["']?)([^\s&"',}\]]+)''',
      caseSensitive: false);
  static final _bearer =
      RegExp(r'Bearer\s+[^\s"\x27,}]+', caseSensitive: false);
  static final _userinfo = RegExp(r'(\w+://)[^\s/@]+:[^\s/@]+@');

  /// Cheap pre-check: a rule whose literal words are absent cannot match.
  static bool _mentions(String text, List<String> words) {
    final lower = text.toLowerCase();
    for (final word in words) {
      if (lower.contains(word)) return true;
    }
    return false;
  }

  static const _secretWords = ['api', 'token', 'password', 'authorization'];

  static String text(String message) {
    var result = message;
    final values = _sorted ??=
        (_known.keys.toList()..sort((a, b) => b.length.compareTo(a.length)));
    for (final value in values) {
      final replacement = _known[value]!.toString();
      final variants = _variants[value] ??= [
        Uri.encodeComponent(value),
        Uri.encodeQueryComponent(value)
      ];
      result = result.replaceAll(value, replacement);
      result = result.replaceAll(variants[0], replacement);
      result = result.replaceAll(variants[1], replacement);
    }
    if (_mentions(result, const ['bearer', 'basic'])) {
      result = result.replaceAllMapped(
          _bearerBasic, (_) => 'CredentialRef(diagnostic, authorization)');
    }
    if (_mentions(result, _secretWords)) {
      result = result.replaceAllMapped(_quotedSecret, (match) {
        final quote = match[2] ?? match[3]!;
        return '${match[1]}${quote}CredentialRef(diagnostic, secret)$quote';
      });
      result = result.replaceAllMapped(_bareSecret,
          (match) => '${match[1]}CredentialRef(diagnostic, secret)');
    }
    if (_mentions(result, const ['bearer'])) {
      result = result.replaceAllMapped(
          _bearer, (_) => 'CredentialRef(diagnostic, authorization)');
    }
    if (result.contains('://')) {
      result = result.replaceAllMapped(_userinfo,
          (match) => '${match[1]}CredentialRef(diagnostic, userinfo)@');
    }
    return result;
  }
}
