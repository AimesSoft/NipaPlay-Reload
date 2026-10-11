import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/credential_file_migration.dart';
import 'package:nipaplay/security/credential_diagnostics_migration.dart';
import 'package:nipaplay/security/portable_credentials.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/security/credential_notice.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:flutter/material.dart';
import 'memory_vault.dart';

void main() {
  late MemoryVault vault;
  late CredentialStore store;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    vault = MemoryVault();
    store = CredentialStore(vault, desktop: true);
  });
  test('all verified scalar and plugin keys migrate without relogin', () async {
    final keys = {
      ...CredentialStore.scalarKeys,
      'plugin_text_setting_demo::key',
      'plugin_demo_token'
    };
    for (final key in keys) {
      await prefs.setString(key, 'test-secret-$key');
    }
    await prefs.setString('dandanplay_username', 'public-user');
    await store.migrate(prefs);
    for (final key in keys) {
      expect(prefs.getString(key), isNot(contains('test-secret')));
      expect(await store.read(prefs, key), 'test-secret-$key');
      expect(store.exportPreference(key, prefs.getString(key)),
          CredentialStore.preferenceRef(key).placeholder);
    }
    expect(prefs.getString('dandanplay_username'), 'public-user');
    await store.migrate(prefs);
    expect(store.failures, isEmpty);
    await store.delete(prefs, 'dandanplay_token');
    expect(await store.read(prefs, 'dandanplay_token'), isNull);
    expect(
        vault.values
            .containsKey(CredentialStore.preferenceRef('dandanplay_token')),
        false);
  });
  test('write error and readback mismatch retain plaintext and retry safely',
      () async {
    await prefs.setString('dandanplay_token', 'old-dandan');
    await prefs.setString('bangumi_access_token', 'old-bangumi');
    vault.failWrite = CredentialStore.preferenceRef('dandanplay_token');
    vault.mismatch = CredentialStore.preferenceRef('bangumi_access_token');
    await store.migrate(prefs);
    expect(prefs.getString('dandanplay_token'), 'old-dandan');
    expect(prefs.getString('bangumi_access_token'), 'old-bangumi');
    expect(await store.read(prefs, 'dandanplay_token'), 'old-dandan');
    expect(store.failures.values,
        containsAll(['system_vault_unavailable', 'vault_readback_mismatch']));
    expect(prefs.getString('vault_migration_failures_v1'),
        isNot(contains('old-')));
    expect(jsonEncode(store.exportPreference('dandanplay_token', 'old-dandan')),
        isNot(contains('old-dandan')));
    vault.failWrite = null;
    vault.mismatch = null;
    await store.migrate(prefs);
    expect(store.failures, isEmpty);
    expect(await store.read(prefs, 'bangumi_access_token'), 'old-bangumi');
  });
  test('nested passwords migrate independently and preserve metadata',
      () async {
    for (final entry in CredentialStore.compositeKeys.entries) {
      final items = [
        {'id': 'first', 'name': 'public', entry.value: 'secret-first'},
        {'id': 'second', 'name': 'public', entry.value: 'secret-second'},
      ];
      await prefs.setString(entry.key, jsonEncode(items));
      vault.failWrite = CredentialRef(entry.key, 'second');
      await store.migrate(prefs);
      final stored = jsonDecode(prefs.getString(entry.key)!) as List;
      expect(credentialReference(stored.first[entry.value]),
          CredentialRef(entry.key, 'first'));
      expect(stored.last[entry.value], 'secret-second');
      final hydrated =
          jsonDecode((await store.read(prefs, entry.key))!) as List;
      expect(hydrated, items);
      expect(jsonEncode(store.exportItems(entry.key, hydrated)),
          isNot(contains('secret-')));
      vault.failWrite = null;
      await store.migrate(prefs);
      expect(prefs.getString(entry.key), isNot(contains('secret-')));
    }
  });
  test('readback refusal retains legacy data and blocks automatic rewrites', () async {
    final ref = CredentialStore.preferenceRef('dandanplay_token');
    await prefs.setString('dandanplay_token', 'existing-secret');
    vault.denied = ref;
    await store.migrate(prefs);
    expect(prefs.getString('dandanplay_token'), 'existing-secret');
    expect(vault.values[ref], 'existing-secret');
    await store.migrate(prefs);
    await expectLater(store.read(prefs, 'dandanplay_token'), throwsStateError);
    expect(vault.reads[ref], 1);
    expect(vault.writes[ref], 1);
    vault.denied = null;
    await store.retry(ref);
    await store.migrate(prefs);
    expect(credentialReference(jsonDecode(prefs.getString('dandanplay_token')!)), ref);
    expect(await store.read(prefs, 'dandanplay_token'), 'existing-secret');
  });
  test('concurrent cancelled reads share one attempt and a new run can read', () async {
    const ref = CredentialRef('smb_connections', 'fixture');
    vault.denied = ref;
    vault.refusal = 'storage_authorization_cancelled';
    await Future.wait([
      for (var i = 0; i < 4; i++)
        expectLater(store.vault.read(ref), throwsStateError),
    ]);
    expect(vault.reads[ref], 1);
    vault.denied = null;
    vault.values[ref] = 'fixture-secret';
    await expectLater(store.vault.read(ref), throwsStateError);
    final nextRun = CredentialStore(vault, desktop: true);
    expect(await nextRun.vault.read(ref), 'fixture-secret');
    expect(vault.reads[ref], 2);
  });
  test('essential login refusal allows startup without clearing persisted login', () async {
    final previousStore = CredentialStore.instance;
    CredentialStore.instance = store;
    addTearDown(() => CredentialStore.instance = previousStore);
    final ref = CredentialStore.preferenceRef('dandanplay_token');
    await prefs.setString('dandanplay_token', jsonEncode(ref.placeholder));
    await prefs.setBool('dandanplay_logged_in', true);
    vault.values[ref] = 'fixture-login';
    vault.denied = ref;
    await DandanplayService.initialize(renewToken: false);
    await DandanplayService.initialize(renewToken: false);
    expect(vault.reads[ref], 1);
    expect(DandanplayService.isLoggedIn, false);
    expect(prefs.getBool('dandanplay_logged_in'), true);
    expect(prefs.getString('dandanplay_token'), jsonEncode(ref.placeholder));
    expect(vault.values[ref], 'fixture-login');
    expect(store.failures[ref], 'storage_access_denied');
  });
  test('failed new writes never create a plaintext preference', () async {
    vault.unavailable = true;
    await expectLater(store.write(prefs, 'plugin_fixture_token', 'fixture-secret'),
        throwsStateError);
    expect(prefs.getString('plugin_fixture_token'), isNull);
    expect(vault.values, isEmpty);
  });
  test(
      'legacy files migrate per entry, preserving failed values and endpoint token',
      () async {
    final root = await Directory.systemTemp.createTemp('vault-migration-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/credentials.json');
    await file.writeAsString(
        jsonEncode({'tmdb': 'test-tmdb', 'other': 'test-other'}));
    await File('${root.path}/endpoint.json')
        .writeAsString(jsonEncode({'token': 'test-endpoint'}));
    vault.failWrite = const CredentialRef('metadata', 'other');
    await migrateCredentialFiles(root, store);
    expect(await file.readAsString(), isNot(contains('test-tmdb')));
    expect(await file.readAsString(), contains('test-other'));
    expect(await vault.read(const CredentialRef('agent', 'token')),
        'test-endpoint');
    vault.failWrite = null;
    await migrateCredentialFiles(root, store);
    expect(await file.readAsString(), isNot(contains('test-other')));
    expect(await root.list().length, 2);
  });
  test('mobile storage retains legacy values through the unified adapter',
      () async {
    final legacy = CredentialStore(vault, desktop: false);
    await legacy.write(prefs, 'dandanplay_token', 'legacy-token');
    await legacy.migrate(prefs);
    expect(prefs.getString('dandanplay_token'), 'legacy-token');
    expect(await legacy.read(prefs, 'dandanplay_token'), 'legacy-token');
    expect(vault.values, isEmpty);
  });
  test('plugin reference-shaped data cannot read another namespace', () async {
    final victim = CredentialStore.preferenceRef('dandanplay_token');
    await vault.write(victim, 'account-sentinel');
    final pluginValue = jsonEncode(victim.placeholder);
    await prefs.setString('plugin_demo_attack', pluginValue);
    expect(await store.read(prefs, 'plugin_demo_attack'), pluginValue);
    await store.migrate(prefs);
    expect(await store.read(prefs, 'plugin_demo_attack'), pluginValue);
    expect(await vault.read(victim), 'account-sentinel');
  });
  test('removing a connection retires its secret after saving metadata',
      () async {
    await store.write(
        prefs,
        'webdav_connections',
        jsonEncode([
          {'id': 'retired', 'password': 'retired-sentinel'}
        ]));
    expect(
        await vault.read(const CredentialRef('webdav_connections', 'retired')),
        'retired-sentinel');
    await store.write(prefs, 'webdav_connections', '[]');
    expect(prefs.getString('webdav_connections'), '[]');
    expect(
        await vault.read(const CredentialRef('webdav_connections', 'retired')),
        null);
  });
  test('host journals, logs and old sync caches are scrubbed after migration',
      () async {
    final root = await Directory.systemTemp.createTemp('vault-diagnostics-');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/next').create();
    await Directory('${root.path}/logs').create();
    await Directory('${root.path}/incremental_sync').create();
    SecretRedactor.remember(
        const CredentialRef('preferences', 'dandanplay_token'),
        'diagnostic-sentinel');
    final journal = File('${root.path}/next/journal.jsonl');
    final log = File('${root.path}/logs/1.txt');
    final cache = File('${root.path}/incremental_sync/1.index.json');
    await journal.writeAsString('${jsonEncode({
          'input': {'token': 'diagnostic-sentinel', 'public': 'visible'}
        })}\n');
    await log.writeAsString(
        'token=diagnostic-sentinel https://example.invalid/?api_key=transient-sentinel');
    await cache.writeAsString(jsonEncode({
      'snapshotSha256': 'old-hash',
      'state': {
        'accounts': {
          'dandanplay': {'token': 'cache-sentinel'}
        }
      }
    }));
    await migrateCredentialDiagnostics(root, root, store);
    for (final file in [journal, log, cache]) {
      expect(await file.readAsString(), isNot(contains('sentinel')));
    }
    expect(
        jsonDecode(await journal.readAsString())['input']['public'], 'visible');
    expect(jsonDecode(await cache.readAsString())['snapshotSha256'],
        'credential-migration-rebuild');
    expect(await Directory('${root.path}/logs').list().length, 1);
  });
  test(
      'portable references use local credentials, missing credentials request login',
      () async {
    final ref = CredentialStore.preferenceRef('dandanplay_token');
    final backup = {'token': ref.placeholder, 'isLoggedIn': true};
    await vault.write(ref, 'local-token');
    expect((await hydratePortableCredentials(backup, store))['token'],
        'local-token');
    await vault.delete(ref);
    final restored = await hydratePortableCredentials(backup, store);
    expect(restored['token'], isNull);
    expect(restored['isLoggedIn'], false);
    expect(store.notices.value.join(), contains('重新登录'));
    expect(backup['token'], ref.placeholder);
  });
  test('diagnostic text removes known, URI encoded and transient credentials',
      () {
    SecretRedactor.remember(
        const CredentialRef('test', 'password'), 'test-p@ss');
    final log = SecretRedactor.text(
        'test-p@ss test-p%40ss https://example/video?token=transient&api_key=another Bearer temporary');
    for (final value in [
      'test-p@ss',
      'test-p%40ss',
      'transient',
      'another',
      'temporary'
    ]) {
      expect(log, isNot(contains(value)));
    }
    expect(log, contains('CredentialRef'));
    expect(SecretRedactor.text('{"token":"transient-json-token"}'),
        isNot(contains('transient-json-token')));
    final authorization = SecretRedactor.text(
        '{"Authorization":"Basic dGVzdDpwYXNz"} {"password":"test pass with spaces"}');
    expect(authorization, isNot(contains('dGVzdDpwYXNz')));
    expect(authorization, isNot(contains('test pass with spaces')));
  });
  testWidgets('unavailable Linux vault gives a persistent user-visible notice',
      (tester) async {
    store = CredentialStore(vault, desktop: true, platform: TargetPlatform.linux);
    final previous = CredentialStore.instance;
    CredentialStore.instance = store;
    addTearDown(() => CredentialStore.instance = previous);
    vault.unavailable = true;
    await store.checkAvailability();
    await tester.pumpWidget(
        const MaterialApp(home: CredentialNotice(child: SizedBox())));
    expect(find.textContaining('Secret Service'), findsOneWidget);
    expect(store.failures.values, contains('system_vault_unavailable'));
  });
}
