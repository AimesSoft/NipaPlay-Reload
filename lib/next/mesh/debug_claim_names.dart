import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:nipaplay/security/credential_vault.dart';

/// Host-only diagnostic. Never attach this to a Harness or journal.
Future<void> debugDandanplayClaimNames(
  CredentialVault vault, {
  Map<String, String>? environment,
  void Function(String)? write,
  void Function(String)? writeError,
}) async {
  if (!kDebugMode) return;
  if ((environment ??
          Platform.environment)['NIPAPLAY_DEBUG_DANDANPLAY_CLAIM_NAMES'] !=
      '1') {
    return;
  }
  final errorOutput = writeError ?? stderr.writeln;
  final String? token;
  try {
    token = await vault
        .read(const CredentialRef('preferences', 'dandanplay_token'));
  } catch (_) {
    errorOutput('[DandanplayClaimNames] vault_read_failed');
    return;
  }
  if (token == null) {
    errorOutput('[DandanplayClaimNames] token_not_found');
    return;
  }
  final Object? payload;
  try {
    final parts = token.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      throw const FormatException();
    }
    payload = jsonDecode(utf8.decode(base64Url.decode(parts[1])));
    if (payload is! Map<String, dynamic>) throw const FormatException();
  } on FormatException {
    errorOutput('[DandanplayClaimNames] invalid_jwt_payload');
    return;
  }
  final claims = <Map<String, String>>[];
  void walk(Map<String, dynamic> fields, String parent) {
    for (final name in fields.keys.toList()..sort()) {
      final value = fields[name];
      final pointer =
          '$parent/${name.replaceAll('~', '~0').replaceAll('/', '~1')}';
      final type = switch (value) {
        null => 'null',
        bool() => 'boolean',
        num() => 'number',
        String() => 'string',
        List() => 'array',
        Map() => 'object',
        _ => throw StateError('invalid_json_type'),
      };
      claims.add({'pointer': pointer, 'type': type});
      if (value is Map<String, dynamic>) walk(value, pointer);
    }
  }

  walk(payload, '');
  (write ?? stdout.writeln)('[DandanplayClaimNames] ${jsonEncode(claims)}');
}
