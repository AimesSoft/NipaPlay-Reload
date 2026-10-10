import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/portable_credentials.dart';
import 'package:nipaplay/services/full_backup_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'memory_vault.dart';

void main() {
  late CredentialStore previous;
  late CredentialStore store;
  late SharedPreferences prefs;
  setUp(() async {
    previous = CredentialStore.instance;
    store = CredentialStore(MemoryVault(), desktop: true);
    CredentialStore.instance = store;
    SharedPreferences.setMockInitialValues({
      'dandanplay_logged_in': true,
      'dandanplay_token': 'sentinel-dandan',
      'bangumi_logged_in': true,
      'bangumi_access_token': 'sentinel-bangumi',
      'spoiler_ai_api_key': 'sentinel-ai',
      'incremental_sync_webdav_password': 'sentinel-sync',
      'plugin_example_token': 'sentinel-plugin',
      'server_profiles': jsonEncode([
        {
          'id': 'server',
          'serverName': 'Public',
          'serverType': 'emby',
          'username': 'public',
          'addresses': [],
          'accessToken': 'sentinel-server',
          'userId': 'public-id'
        }
      ]),
      'webdav_connections': jsonEncode([
        {
          'id': 'webdav',
          'name': 'Public',
          'url': 'https://example.invalid',
          'username': 'public',
          'password': 'sentinel-webdav'
        }
      ]),
      'smb_connections': jsonEncode([
        {
          'id': 'smb',
          'name': 'Public',
          'host': 'example.invalid',
          'username': 'public',
          'password': 'sentinel-smb'
        }
      ]),
    });
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() {
    CredentialStore.instance = previous;
  });

  test(
      'backup and incremental sync collection never export legacy or hydrated secrets',
      () async {
    final service =
        FullBackupService(webDavService: WebDAVService.forTesting());
    for (final migrated in [false, true]) {
      if (migrated) await store.migrate(prefs);
      final data = await service.collectBackupData(categories: {
        BackupCategory.preferences,
        BackupCategory.accounts,
        BackupCategory.mediaLibraries
      });
      expect(jsonEncode(data), isNot(contains('sentinel-')));
      expect(data['accounts']['dandanplay']['token'],
          CredentialStore.preferenceRef('dandanplay_token').placeholder);
      expect(data['mediaLibraries']['webdavConnections'].first['password'],
          const CredentialRef('webdav_connections', 'webdav').placeholder);
      expect(data['mediaLibraries']['smbConnections'].first['password'],
          const CredentialRef('smb_connections', 'smb').placeholder);
      expect(data['accounts']['serverAccounts'].first['accessToken'],
          const CredentialRef('server_profiles', 'server').placeholder);
    }
  });
  test(
      'old backups restore secrets into vault; new backups on a new host require login',
      () async {
    final service = FullBackupService();
    final result = await service.restoreFromData(backupData: {
      'version': 2,
      'accounts': {
        'dandanplay': {
          'isLoggedIn': true,
          'token': 'restore-sentinel',
          'username': 'public'
        },
        'bangumi': {'isLoggedIn': false}
      }
    }, categories: {
      BackupCategory.accounts
    });
    expect(result.success, true);
    expect(prefs.getString('dandanplay_token'),
        isNot(contains('restore-sentinel')));
    expect(await store.read(prefs, 'dandanplay_token'), 'restore-sentinel');
    final backup =
        await service.collectBackupData(categories: {BackupCategory.accounts});
    (store.vault as MemoryVault).values.clear();
    await prefs.remove('dandanplay_token');
    await prefs.remove('dandanplay_logged_in');
    final restored = await service.restoreFromData(
        backupData: backup, categories: {BackupCategory.accounts});
    expect(restored.success, true);
    expect(prefs.getBool('dandanplay_logged_in') ?? false, false);
    expect(store.notices.value.join(), contains('重新登录'));
  });
  test(
      'credential-bearing playback URLs travel only as references and hydrate on the host',
      () async {
    const url = 'https://example.invalid/video?api_key=uri-sentinel';
    final backup = await sealPortableCredentials({'filePath': url}, store);
    expect(jsonEncode(backup), isNot(contains('uri-sentinel')));
    expect(backup['filePath'], isA<String>());
    expect((await hydratePortableCredentials(backup, store))['filePath'], url);
    (store.vault as MemoryVault).values.clear();
    expect(
        (await hydratePortableCredentials(backup, store))['filePath'], isNull);
    expect(store.notices.value.join(), contains('重新登录'));
  });
  test(
      'legacy remote sync payloads become references without overwriting local credentials',
      () async {
    final local = CredentialStore.preferenceRef('dandanplay_token');
    await store.vault.write(local, 'local-sentinel');
    final data = {
      'accounts': {
        'dandanplay': {'token': 'remote-sentinel'}
      },
      'preferences': {'spoiler_ai_api_key': 'remote-ai-sentinel'}
    };
    final sealed = await sealPortableCredentials(data, store);
    expect(jsonEncode(sealed), isNot(contains('sentinel')));
    expect(await store.vault.read(local), 'local-sentinel');
    expect(await hydratePortableCredentials(sealed, store), data);
    expect(await sealPortableCredentials(sealed, store), sealed);
  });
}
