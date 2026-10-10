import 'package:nipaplay/security/secret_redactor.dart';

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
