import 'dart:convert';
import 'dart:typed_data';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';

/// SQLite values that JSON cannot carry are tagged: blobs and non-finite reals.
Object? jsonSafe(Object? value) {
  if (value is Uint8List) return {r'$blob': base64Encode(value)};
  if (value is List<int>) return {r'$blob': base64Encode(value)};
  if (value is double && !value.isFinite) return {r'$real': value.toString()};
  return value;
}

/// The inverse of [jsonSafe], for values read back from audit JSON.
Object? fromJsonSafe(Object? value) {
  if (value is Map && value.length == 1) {
    if (value[r'$blob'] is String) {
      return Uint8List.fromList(base64Decode(value[r'$blob'] as String));
    }
    if (value[r'$real'] is String) return double.parse(value[r'$real'] as String);
  }
  return value;
}

Map<String, Object?> safeRow(Map<String, Object?> row) =>
    {for (final e in row.entries) e.key: jsonSafe(e.value)};

Map<String, Object?> unsafeRow(Map row) =>
    {for (final e in row.entries) e.key as String: fromJsonSafe(e.value)};

/// Cells shown to the caller: long text is cut, blobs are summarised, and
/// cells holding secrets are masked. Whatever is cut is counted by the caller.
final class CellView {
  CellView(this.limit);
  final int limit;
  int cut = 0;

  Object? cell(Object? value) {
    if (value is Uint8List || value is List<int>) {
      final bytes = value as List<int>;
      return {
        r'$blob': base64Encode(bytes.take(48).toList()),
        'bytes': bytes.length,
        if (bytes.length > 48) 'truncated': true,
      };
    }
    if (value is String) {
      // A cell that holds a secret is replaced whole, before it is cut.
      final masked = SecretRedactor.json(value);
      if (masked is! String) return masked;
      final text = masked;
      if (text.length > limit) {
        cut++;
        return '${text.substring(0, limit)}…[+${text.length - limit} chars]';
      }
      return text;
    }
    return jsonSafe(value);
  }

  Map<String, Object?> row(Map<String, Object?> row) =>
      {for (final e in row.entries) e.key: cell(e.value)};
}

/// Masks secrets in a whole structure; failure details are masked the same way.
JsonMap redactedOutput(JsonMap value) =>
    Map<String, Object?>.from(SecretRedactor.json(value) as Map);
