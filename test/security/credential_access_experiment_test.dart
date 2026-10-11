import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as harness;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/security/credential_capability.dart';
import 'package:nipaplay/security/credential_notice.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/multi_address_server_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'memory_vault.dart';

void main() {
  testWidgets(
      'X10 experiment: deferred reads, refusal facts and explicit recovery',
      (tester) async {
    const smbRef = CredentialRef('smb_connections', 'smb-one');
    const otherSmbRef = CredentialRef('smb_connections', 'smb-two');
    const embyRef = CredentialRef('server_profiles', 'emby-one');
    const jellyRef = CredentialRef('server_profiles', 'jelly-one');
    const webdavRef = CredentialRef('webdav_connections', 'webdav-one');
    final vault = MemoryVault()
      ..values[smbRef] = 'fixture-password'
      ..values[otherSmbRef] = 'fixture-other-password'
      ..values[embyRef] = 'fixture-emby-token'
      ..values[jellyRef] = 'fixture-jelly-token'
      ..values[webdavRef] = 'fixture-webdav-password'
      ..values[CredentialStore.preferenceRef('dandanplay_token')] =
          'fixture-login';
    final previous = CredentialStore.instance;
    final store =
        CredentialStore(vault, desktop: true, platform: TargetPlatform.macOS);
    CredentialStore.instance = store;
    addTearDown(() => CredentialStore.instance = previous);
    final initial = <String, Object>{
      'dandanplay_token': jsonEncode(
          CredentialStore.preferenceRef('dandanplay_token').placeholder),
      'emby_current_profile_id': 'emby-one',
      'jellyfin_current_profile_id': 'jelly-one',
      'server_profiles': jsonEncode([
        for (final ref in [embyRef, jellyRef])
          {
            'id': ref.key,
            'serverName': ref.key,
            'serverType': ref == embyRef ? 'emby' : 'jellyfin',
            'username': 'fixture-user',
            'userId': 'fixture-user',
            'addresses': [
              {
                'id': 'address',
                'url': 'https://example.invalid',
                'name': 'fixture'
              }
            ],
            'accessToken': ref.placeholder,
          }
      ]),
      'smb_connections': jsonEncode([
        for (final ref in [smbRef, otherSmbRef])
          {
            'id': ref.key,
            'name': ref.key,
            'host': 'example.invalid',
            'username': 'fixture-user',
            'password': ref.placeholder,
          }
      ]),
      'webdav_connections': jsonEncode([
        {
          'id': webdavRef.key,
          'name': 'fixture-webdav',
          'url': 'https://example.invalid',
          'username': 'fixture-user',
          'password': webdavRef.placeholder,
        }
      ]),
    };
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    await store.migrate(prefs, keys: const {'dandanplay_token'});
    await DandanplayService.initialize(renewToken: false);
    await EmbyService.instance.loadSavedSettings(loadCredentials: false);
    await JellyfinService.instance.loadSavedSettings(loadCredentials: false);
    await DandanplayRemoteService.instance
        .loadSavedSettings(loadCredentials: false);
    await SMBService.instance.initialize();
    await WebDAVService.instance.initialize();
    final api = harness.Harness([CredentialCapability(store)]);
    final status = await api.invokeJson(
        'credentials.status', {}, harness.Invocation(origin: 'experiment'));
    expect(
        vault.reads.keys, [CredentialStore.preferenceRef('dandanplay_token')]);
    print(
        'X10 startup: essentialReads=1, nonessentialReads=0, smbMetadata=2, webdavMetadata=1, profiles=2');
    expect(jsonEncode(status.toEnvelope()), isNot(contains('fixture-login')));
    final connection = SMBService.instance.getConnectionByIdOrName(smbRef.key)!;
    final editingPassword = connection.password;
    vault.denied = smbRef;
    await expectLater(connection.resolvePassword(), throwsStateError);
    for (var i = 0; i < 3; i++) {
      await expectLater(store.vault.read(smbRef), throwsStateError);
      await expectLater(connection.resolvePassword(), throwsStateError);
    }
    await tester.pumpWidget(
        const MaterialApp(home: CredentialNotice(child: SizedBox())));
    expect(find.textContaining('访问被拒绝'), findsOneWidget);
    expect(find.textContaining('Secret Service'), findsNothing);
    final refused = (await api.invokeJson(
            'credentials.status', {}, harness.Invocation(origin: 'experiment')))
        .toEnvelope();
    print(
        'X10 refused: backendReads=${vault.reads[smbRef]}, automaticAttempts=6, GUI=访问被拒绝, macOSLinuxText=false');
    print('X10 agent: ${jsonEncode(refused)}');
    expect(vault.reads[smbRef], 1);
    expect(vault.reads[otherSmbRef], isNull);
    for (final key in [
      'server_profiles',
      'smb_connections',
      'webdav_connections'
    ]) {
      expect(prefs.getString(key), initial[key]);
    }
    // A metadata edit must retain the unresolved second entry, without reading it.
    final items = SMBService.instance.connections
        .map((c) => c.copyWith(name: c.name).toJson())
        .toList();
    await store.write(prefs, 'smb_connections', jsonEncode(items));
    await MultiAddressServerService.instance.saveProfiles();
    expect(
        (jsonDecode(prefs.getString('server_profiles')!) as List)
            .map((item) => credentialReference(item['accessToken'])),
        [embyRef, jellyRef]);
    expect(vault.reads[otherSmbRef], isNull);
    vault.denied = null;
    await tester.tap(find.text('重试 $smbRef'));
    await tester.pump();
    await connection.resolvePassword();
    expect(connection.password, 'fixture-password');
    expect(store.failures, isEmpty);
    expect(find.textContaining('访问被拒绝'), findsNothing);
    final edit = SMBConnection(
        id: connection.id,
        name: connection.name,
        host: connection.host,
        username: connection.username,
        password: editingPassword,
        storedPassword: connection.retainPassword(editingPassword,
            original: editingPassword));
    expect(edit.toJson()['password'], smbRef.placeholder);
    print(
        'X10 user retry: backendReads=${vault.reads[smbRef]}, resolved=true, blocked=${store.vault.blocked.length}, notices=${store.notices.value.length}');
    // Agent has the same explicit operation; the result contains no secret.
    final retried = await api.invokeJson('credentials.retry', smbRef.toJson(),
        harness.Invocation(origin: 'experiment'));
    print('X10 agent retry: ${jsonEncode(retried.toEnvelope())}');
    expect(
        jsonEncode(retried.toEnvelope()), isNot(contains('fixture-password')));
    expect(vault.values[smbRef], 'fixture-password');
    expect(vault.values[otherSmbRef], 'fixture-other-password');
    print(
        'X10 preservation: bothSecretsRetained=true, unusedEntryReads=0, plaintextPreferences=false');
    var validations = 0;
    final webdav =
        WebDAVService.forTesting(connectionValidator: (connection) async {
      validations++;
      expect(connection.password, 'fixture-webdav-password');
      return connection;
    });
    await webdav.initialize();
    final selected = webdav.connections.single;
    vault.denied = webdavRef;
    vault.refusal = 'storage_authorization_cancelled';
    await expectLater(webdav.testConnection(selected), throwsStateError);
    await expectLater(webdav.testConnection(selected), throwsStateError);
    expect(vault.reads[webdavRef], 1);
    expect(validations, 0);
    print(
        'X10 cancelled: reference=$webdavRef, backendReads=1, networkValidations=0, automaticRetryBlocked=true');
    vault.denied = null;
    await api.invokeJson('credentials.retry', webdavRef.toJson(),
        harness.Invocation(origin: 'experiment'));
    expect(await webdav.testConnection(selected), true);
    expect(validations, 1);
    print(
        'X10 explicit reconnect: success=true, networkValidations=$validations, otherSMBReads=${vault.reads[otherSmbRef] ?? 0}, otherServerReads=${(vault.reads[embyRef] ?? 0) + (vault.reads[jellyRef] ?? 0)}');
  });
}
