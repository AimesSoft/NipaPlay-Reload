import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/secrets/capability.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _Vault implements CredentialVault {
  final values = <CredentialRef, String>{};
  bool broken = false;
  @override
  Future<String?> read(CredentialRef ref) async {
    if (broken) throw StateError('private-fixture-secret');
    return values[ref];
  }

  @override
  Future<void> write(CredentialRef ref, String secret) async {
    values[ref] = secret;
  }

  @override
  Future<void> delete(CredentialRef ref) async {
    values.remove(ref);
  }
}

final class _Audit implements InvocationObserver {
  final rows = <JsonMap>[];
  @override
  void onInvocation(InvocationRecord record) {
    rows.add(record.toJson());
  }
}

void main() {
  sqfliteFfiInit();
  test(
      'authenticated local endpoint delivers the secret while the audit stays redacted',
      () async {
    final root = await Directory.systemTemp.createTemp('secret-pipe-');
    final db = await openNextDatabase(root, factory: databaseFactoryFfi);
    final audit = _Audit();
    final api = Harness([SecretsCapability(db, _Vault())], observers: [audit]);
    final endpoint = AgentEndpoint(
        harness: api,
        seed: const {},
        appVersion: 'test',
        instanceFacts: () async => {},
        credentialFile: File('${root.path}/endpoint.json'),
        port: 0);
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      client.close(force: true);
      await endpoint.stop();
      await db.close();
      await root.delete(recursive: true);
    });
    await api.invokeJson(
        'secrets.set',
        {
          'name': 'pt',
          'value': 'pipe-fixture-private',
          'userAuthorization': '用户要求保存'
        },
        Invocation(origin: 'test'));
    final running = await endpoint.start(Directory('${root.path}/harness'))
        as AgentEndpointRunning;
    final credentials =
        jsonDecode(await endpoint.credentialFile.readAsString()) as Map;
    final request = await client.postUrl(running.url.replace(path: '/harness'));
    request.headers.set('Authorization', 'Bearer ${credentials['token']}');
    request.write(jsonEncode({
      'operation': 'call',
      'action': 'secrets.get',
      'input': {'name': 'pt'}
    }));
    final result =
        jsonDecode(await utf8.decodeStream(await request.close())) as Map;
    expect(result['result']['value'], 'pipe-fixture-private');
    expect(jsonEncode(audit.rows), isNot(contains('pipe-fixture-private')));
  });
  test(
      'authorized vault CRUD returns values only to caller, never audit or database',
      () async {
    final root = await Directory.systemTemp.createTemp('secrets-');
    final db = await openNextDatabase(root, factory: databaseFactoryFfi);
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final vault = _Vault(), audit = _Audit();
    final api = Harness([SecretsCapability(db, vault)], observers: [audit]);
    Future<Outcome<JsonEncodable>> invoke(String action, JsonMap input) =>
        api.invokeJson(action, input, Invocation(origin: 'script'));
    const private = 'private-fixture-secret';
    expect(await invoke('secrets.set', {'name': 'jackett', 'value': private}),
        isA<Failed>());
    expect(vault.values, isEmpty);
    expect(
        await invoke('secrets.set', {
          'name': 'jackett',
          'value': private,
          'userAuthorization': '用户要求保存 Jackett API Key'
        }),
        isA<Completed>());
    expect(vault.values.keys.single.namespace, 'harness_secrets');
    expect(
        (await invoke('secrets.get', {'name': 'jackett'}) as Completed)
            .value
            .toJson()['value'],
        private);
    expect((await invoke('secrets.list', {}) as Completed).value.toJson(), {
      'names': ['jackett']
    });
    expect(jsonEncode(audit.rows), isNot(contains(private)));
    final names = await db.query('harness_secret_names');
    expect(jsonEncode(names), isNot(contains(private)));
    expect(names.single['user_authorization'], contains('用户要求'));
    expect(meshActionAllowed('secrets.get'), false);
    expect(meshActionAllowed('subscription.set_state'), true);
    vault.broken = true;
    final failure = await invoke('secrets.get', {'name': 'jackett'});
    expect(jsonEncode(failure.toEnvelope()), isNot(contains(private)));
    vault.broken = false;
    await invoke('secrets.remove', {'name': 'jackett'});
    expect(vault.values, isEmpty);
    expect(await db.query('harness_secret_names'), isEmpty);
    expect(await invoke('secrets.get', {'name': 'jackett'}), isA<Failed>());
  });
}
