import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'state/query.dart' show publicValue;
import 'public_url.dart';

final _secretName = RegExp(
    r'password|secret|token|cookie|authorization|api[_-]?key|passkey',
    caseSensitive: false);
final _cookieLine = RegExp(
    r'''((?:cookie|secret|passkey)["']?\s*[=:]\s*)([^\r\n]+)''',
    caseSensitive: false);

String _scrubLines(String value) {
  final lower = value.toLowerCase();
  if (!lower.contains('cookie') &&
      !lower.contains('secret') &&
      !lower.contains('passkey')) {
    return value;
  }
  return value.replaceAllMapped(
      _cookieLine, (match) => '${match[1]}[redacted]');
}

/// Public source facts retain public locators and remove secrets.
Object? publicHarnessFacts(Object? value) {
  final safe = publicValue(SecretRedactor.json(value),
      const ObjectSchema({}, additionalProperties: true));
  Object? scrub(Object? item) {
    if (item is Map) {
      return <String, Object?>{
        for (final entry in item.entries)
          entry.key as String: _secretName.hasMatch(entry.key as String)
              ? '[redacted]'
              : scrub(entry.value),
      };
    }
    if (item is List) return item.map(scrub).toList();
    if (item is String) return _scrubLines(item);
    return item;
  }

  return scrub(safe);
}

String redactHarnessText(String value) =>
    _scrubLines(SecretRedactor.text(redactPrivateUrls(value)));

Object? redactHarnessJson(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        redactHarnessText(entry.key as String):
            _secretName.hasMatch(entry.key as String)
                ? '[redacted]'
                : redactHarnessJson(entry.value),
    };
  }
  if (value is List) return value.map(redactHarnessJson).toList();
  return value is String ? redactHarnessText(value) : value;
}
