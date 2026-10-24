import 'dart:convert';
import 'dart:isolate';

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

/// Reject recognizable secrets on writes and redact them on reads/injection.
String redactMemoryText(String value) => redactHarnessText(value).replaceAll(
    RegExp(r'-----BEGIN (?:[A-Z ]*PRIVATE KEY)-----[\s\S]*?'
        r'-----END (?:[A-Z ]*PRIVATE KEY)-----'),
    '[redacted private key]');

/// [redactMemoryText] on a background isolate, with the secrets this one
/// remembers. Text from a long turn can otherwise do regex work on the UI
/// isolate every time memory context is assembled.
Future<String> redactMemoryTextOffMain(String value) async {
  final remembered = SecretRedactor.remembered();
  try {
    return await Isolate.run(() {
      for (final MapEntry(key: secret, value: ref) in remembered.entries) {
        SecretRedactor.remember(ref, secret);
      }
      return redactMemoryText(value);
    });
  } on ArgumentError {
    return redactMemoryText(value);
  }
}

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

/// [redactHarnessJson] on a background isolate, with the secrets this one
/// remembers, for a value that grows with what it holds (a thread read back).
Future<Object?> redactHarnessJsonOffMain(Object? value) async {
  final remembered = SecretRedactor.remembered();
  try {
    return await Isolate.run(() {
      for (final MapEntry(key: secret, value: ref) in remembered.entries) {
        SecretRedactor.remember(ref, secret);
      }
      return redactHarnessJson(value);
    });
  } on ArgumentError {
    return redactHarnessJson(value);
  }
}

/// Redacts and encodes a value in one background pass. Hooks persist their
/// payload as JSON after delivering it to observers, so returning text avoids
/// a second redaction and encoding turn on the UI isolate.
Future<String> redactAndEncodeHarnessJsonOffMain(Object? value) async {
  final remembered = SecretRedactor.remembered();
  try {
    return await Isolate.run(() {
      for (final MapEntry(key: secret, value: ref) in remembered.entries) {
        SecretRedactor.remember(ref, secret);
      }
      return jsonEncode(redactHarnessJson(value));
    });
  } on ArgumentError {
    return jsonEncode(redactHarnessJson(value));
  }
}

/// Redacts one chat delta and holds back a trailing prefix of a known token.
/// The caller supplies the previous held tail and keeps calls serialized, so
/// the published fragments retain stream order and no token half escapes.
Future<(String, String)> protectChatDeltaOffMain(
    String text, Iterable<String> tokens) async {
  final remembered = SecretRedactor.remembered();
  final holdbacks = List<String>.of(tokens);
  try {
    return await Isolate.run(() {
      for (final MapEntry(key: secret, value: ref) in remembered.entries) {
        SecretRedactor.remember(ref, secret);
      }
      return _protectChatDelta(text, holdbacks);
    });
  } on ArgumentError {
    return _protectChatDelta(text, holdbacks);
  }
}

(String, String) _protectChatDelta(String text, Iterable<String> tokens) {
  final safe = redactHarnessText(text);
  var keep = 0;
  for (final token in tokens) {
    for (var length = 1;
        length < token.length && length <= safe.length;
        length++) {
      if (length > keep && safe.endsWith(token.substring(0, length))) {
        keep = length;
      }
    }
  }
  return (
    safe.substring(0, safe.length - keep),
    safe.substring(safe.length - keep)
  );
}
