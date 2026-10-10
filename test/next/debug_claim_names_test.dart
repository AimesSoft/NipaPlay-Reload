import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/mesh/debug_claim_names.dart';
import 'package:nipaplay/security/credential_vault.dart';

final class _Vault implements CredentialVault {
  String? token;
  Object? failure;
  final reads = <CredentialRef>[];

  @override
  Future<String?> read(CredentialRef ref) async {
    reads.add(ref);
    if (failure != null) throw failure!;
    return token;
  }

  @override
  Future<void> write(CredentialRef ref, String secret) async =>
      throw UnimplementedError();
  @override
  Future<void> delete(CredentialRef ref) async => throw UnimplementedError();
}

String _jwt(Object? payload) =>
    'synthetic-header.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.synthetic-signature';

void main() {
  const enabled = {'NIPAPLAY_DEBUG_DANDANPLAY_CLAIM_NAMES': '1'};

  test('disabled diagnostic never reads the vault or writes output', () async {
    final vault = _Vault();
    final output = <String>[];
    for (final environment in [
      <String, String>{},
      {'NIPAPLAY_DEBUG_DANDANPLAY_CLAIM_NAMES': '0'},
      {'NIPAPLAY_DEBUG_DANDANPLAY_CLAIM_NAMES': 'true'}
    ]) {
      await debugDandanplayClaimNames(vault,
          environment: environment, write: output.add, writeError: output.add);
    }
    expect(vault.reads, isEmpty);
    expect(output, isEmpty);
  });

  test('reads only the account token and prints names and JSON types',
      () async {
    final vault = _Vault()
      ..token = _jwt({
        'userId': 424242,
        'name': 'synthetic-private-name',
        'verified': true,
        'optional': null,
        'items': ['synthetic-private-array-value'],
        'identity': {'uid': 'synthetic-private-id'},
        'a/b~c': 'synthetic-private-escaped-value',
      });
    final output = <String>[], errors = <String>[];
    await debugDandanplayClaimNames(vault,
        environment: enabled, write: output.add, writeError: errors.add);
    expect(
        vault.reads, [const CredentialRef('preferences', 'dandanplay_token')]);
    expect(errors, isEmpty);
    expect(output, hasLength(1));
    final claims =
        jsonDecode(output.single.substring('[DandanplayClaimNames] '.length));
    expect(claims, [
      {'pointer': '/a~1b~0c', 'type': 'string'},
      {'pointer': '/identity', 'type': 'object'},
      {'pointer': '/identity/uid', 'type': 'string'},
      {'pointer': '/items', 'type': 'array'},
      {'pointer': '/name', 'type': 'string'},
      {'pointer': '/optional', 'type': 'null'},
      {'pointer': '/userId', 'type': 'number'},
      {'pointer': '/verified', 'type': 'boolean'},
    ]);
    expect(output.single, isNot(contains(vault.token!)));
    expect(output.single, isNot(contains('424242')));
    expect(output.single, isNot(contains('synthetic-private')));
  });

  test('invalid payloads report fixed errors without source or credential',
      () async {
    final vault = _Vault();
    for (final token in [
      'synthetic-private-invalid-token',
      'header.!.signature',
      _jwt(['synthetic-private-array']),
      _jwt(null),
      'header.${base64Url.encode(utf8.encode('synthetic-private-bad-json'))}.signature'
    ]) {
      vault.token = token;
      final output = <String>[], errors = <String>[];
      await debugDandanplayClaimNames(vault,
          environment: enabled, write: output.add, writeError: errors.add);
      expect(output, isEmpty);
      expect(errors, ['[DandanplayClaimNames] invalid_jwt_payload']);
    }
  });

  test('missing token and vault failures reveal no secret or backend text',
      () async {
    final vault = _Vault();
    final output = <String>[], errors = <String>[];
    await debugDandanplayClaimNames(vault,
        environment: enabled, write: output.add, writeError: errors.add);
    vault.failure = StateError('synthetic-private-backend-error');
    await debugDandanplayClaimNames(vault,
        environment: enabled, write: output.add, writeError: errors.add);
    expect(output, isEmpty);
    expect(errors, [
      '[DandanplayClaimNames] token_not_found',
      '[DandanplayClaimNames] vault_read_failed'
    ]);
  });
}
