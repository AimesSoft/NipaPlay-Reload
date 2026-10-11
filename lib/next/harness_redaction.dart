import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'state/query.dart' show publicValue;

/// Public source facts retain locator identity, but no URL credentials or queries.
Object? publicHarnessFacts(Object? value) {
  final safe = publicValue(SecretRedactor.json(value),
      const ObjectSchema({}, additionalProperties: true));
  Object? scrub(Object? item) {
    if (item is Map) {
      return <String, Object?>{
        for (final entry in item.entries)
          entry.key as String:
              RegExp(r'password|secret|token|cookie|authorization|api[_-]?key|passkey',
                          caseSensitive: false)
                      .hasMatch(entry.key as String)
                  ? '[redacted]'
                  : scrub(entry.value),
      };
    }
    if (item is List) return item.map(scrub).toList();
    if (item is String) {
      return item.replaceAllMapped(
          RegExp(r'''((?:cookie|secret|passkey)["']?\s*[=:]\s*)([^\r\n]+)''',
              caseSensitive: false),
          (match) => '${match[1]}[redacted]');
    }
    return item;
  }

  return scrub(safe);
}

String redactHarnessText(String value) {
  var result = SecretRedactor.text(value);
  result = result.replaceAll(
      RegExp(r'''\b(?:https?|magnet)://[^\s"<>]+'''), '[redacted URL]');
  return result.replaceAllMapped(
      RegExp(r'''((?:cookie|secret|passkey)["']?\s*[=:]\s*)([^\r\n]+)''',
          caseSensitive: false),
      (match) => '${match[1]}[redacted]');
}

Object? redactHarnessJson(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        redactHarnessText(entry.key as String):
            RegExp(r'password|secret|token|cookie|authorization|api[_-]?key|passkey',
                        caseSensitive: false)
                    .hasMatch(entry.key as String)
                ? '[redacted]'
                : redactHarnessJson(entry.value),
    };
  }
  if (value is List) return value.map(redactHarnessJson).toList();
  return value is String ? redactHarnessText(value) : value;
}
