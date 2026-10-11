// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/next/settings/operations.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/full_backup_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/lab_profile.dart';
import 'package:nipaplay/utils/storage_service.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('X21 disk preferences, real plugin and full backup experiment',
      (tester) async {
    await tester.runAsync(() async {
      final temporary = await Directory.systemTemp.createTemp('nipa-x21-');
      final root = Directory(await temporary.resolveSymbolicLinks());
      final previousStore = CredentialStore.instance;
      final previousPaths = PathProviderPlatform.instance;
      final previousPreferences = SharedPreferencesStorePlatform.instance;
      final previousStorage = StorageService.debugAppStorageDirectoryOverride;
      final vault = MemoryVault();
      final store = CredentialStore(vault, desktop: true);
      CredentialStore.instance = store;
      StorageService.debugAppStorageDirectoryOverride = root;
      PathProviderPlatform.instance = LabPaths(root.path);
      SharedPreferencesStorePlatform.instance =
          LabPreferences(File('${root.path}/preferences.json'));
      SharedPreferences.resetStatic();
      PluginService? plugins;
      PluginService? reloaded;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('plugin_enabled_ids', []);
        await prefs.setBool('plugin_downloader_override', true);
        await prefs.setBool('plugin_switch_setting_demo::enabled', true);
        await store.write(prefs, 'plugin_text_setting_demo::label', '公开文本');
        // Reproduce public text already migrated by the previous classifier.
        const legacyPublic = 'plugin_text_setting_demo::legacy_label';
        final publicRef = CredentialStore.preferenceRef(legacyPublic);
        await store.verifiedWrite(publicRef, '保险库中的公开文本');
        await prefs.setString(legacyPublic, jsonEncode(publicRef.placeholder));
        await store.write(
            prefs, 'plugin_text_setting_demo::api_key', 'x21-plugin-secret');
        await store.write(prefs, 'dandanplay_token', 'x21-login-secret');
        await prefs.setBool('dandanplay_logged_in', true);
        await prefs.setString('dandanplay_username', 'X21 fixture');
        await prefs.setInt('last_token_renew_time', 123);
        final originalVault = Map.of(vault.values);
        final originalStoredPublic = prefs.getString(legacyPublic);
        final backup =
            FullBackupService(webDavService: WebDAVService.forTesting());
        plugins = PluginService();
        await plugins.ready;
        const id = 'builtin.cn_danmaku_regex_filter';
        await plugins.setPluginEnabled(id, true);
        expect(plugins.isPluginEnabled(id), true);
        expect(
            plugins.plugins
                .firstWhere((plugin) => plugin.manifest.id == id)
                .loaded,
            true);
        final enabled = prefs.getStringList('plugin_enabled_ids');
        final path = '${root.path}/full.npb';
        expect(
            await backup.exportBackupToFile(
                filePath: path, categories: BackupCategory.values.toSet()),
            path);
        final text = await File(path).readAsString();
        final data = jsonDecode(text) as Map<String, dynamic>;
        final settings = data['preferences']['settings'] as Map;
        expect(settings['plugin_enabled_ids'], enabled);
        expect(settings['plugin_downloader_override'], true);
        expect(settings['last_token_renew_time'], 123);
        expect(settings['plugin_text_setting_demo::label'], '公开文本');
        expect(settings[legacyPublic], '保险库中的公开文本');
        expect(prefs.getString(legacyPublic), originalStoredPublic);
        expect(vault.values, originalVault);
        expect(text, isNot(contains('x21-login-secret')));
        expect(text, isNot(contains('x21-plugin-secret')));
        print(
            'X21 export: enabled=${jsonEncode(settings['plugin_enabled_ids'])}; override=${settings['plugin_downloader_override']}; switch=${settings['plugin_switch_setting_demo::enabled']}; public=${settings['plugin_text_setting_demo::label']}; vaultedPublic=${settings[legacyPublic]}; storedPublicUnchanged=true; vaultUnchanged=true');
        print(
            'X21 login export: ${jsonEncode(data['accounts']['dandanplay']['token'])}; plugin secret export: ${jsonEncode(settings['plugin_text_setting_demo::api_key'])}; secretBytesAbsent=true');
        await plugins.setPluginEnabled(id, false);
        expect(prefs.getStringList('plugin_enabled_ids'), isEmpty);
        print(
            'X21 before restore: enabled=${jsonEncode(prefs.getStringList('plugin_enabled_ids'))}');
        final result = await backup.importBackup(
            filePath: path, categories: BackupCategory.values.toSet());
        expect(result.success, true);
        expect(result.status, 'completed');
        expect(result.totalSkippedCount, 0);
        expect(prefs.getStringList('plugin_enabled_ids'), enabled);
        expect(prefs.getInt('last_token_renew_time'), 123);
        reloaded = PluginService();
        await reloaded.ready;
        expect(reloaded.isPluginEnabled(id), true);
        expect(
            reloaded.plugins
                .firstWhere((plugin) => plugin.manifest.id == id)
                .loaded,
            true);
        expect(vault.values, originalVault);
        expect(prefs.getString(legacyPublic), originalStoredPublic);
        print(
            'X21 full roundtrip: status=${result.status}; enabled=${jsonEncode(prefs.getStringList('plugin_enabled_ids'))}; reloadedEnabled=${reloaded.isPluginEnabled(id)}; reloadedLoaded=true; skipped=${result.totalSkippedCount}; vaultUnchanged=true; storedPublicUnchanged=true');

        final oldSettings = {
          for (final key in [
            'plugin_enabled_ids',
            'plugin_downloader_override',
            'plugin_text_setting_demo::label'
          ])
            key: CredentialStore.preferenceRef(key).placeholder,
        };
        final oldPath = '${root.path}/old-format.npb';
        await File(oldPath).writeAsString(jsonEncode({
          'version': 2,
          'preferences': {'settings': oldSettings}
        }));
        final current = {
          for (final key in oldSettings.keys) key: prefs.get(key)
        };
        final storedBefore =
            await File('${root.path}/preferences.json').readAsBytes();
        final oldResult = await backup.importBackup(
            filePath: oldPath, categories: {BackupCategory.preferences});
        expect(oldResult.status, 'skipped');
        expect(oldResult.success, false);
        expect(oldResult.totalRestoredCount, 0);
        expect(oldResult.totalSkippedCount, 3);
        expect(
            {for (final key in oldSettings.keys) key: prefs.get(key)}, current);
        expect(await File('${root.path}/preferences.json').readAsBytes(),
            storedBefore);
        expect(vault.values, originalVault);
        print(
            'X21 old-format restore: ${jsonEncode(ClassicOperations.categoryResult(oldResult.preferencesResult!))}; current=${jsonEncode(current)}; preferenceFileUnchanged=true; vaultUnchanged=true');

        final historyDb = await WatchHistoryDatabase.instance.database;
        await historyDb.insert('watch_history', {
          'file_path': '${root.path}/episode.mkv',
          'anime_name': 'X21 current',
          'anime_id': 21,
          'episode_id': 2101,
          'watch_progress': 0.5,
          'last_position': 123000,
          'duration': 246000,
          'last_watch_time': '2026-10-11T00:00:00.000Z',
          'is_from_scan': 0,
        });
        final rowsBefore = await historyDb.query('watch_history');
        final missingPath =
            jsonEncode(const CredentialRef('backup-url', 'absent').placeholder);
        final missingHistory = '${root.path}/missing-history.npb';
        await File(missingHistory).writeAsString(jsonEncode({
          'version': 2,
          'watchHistory': [
            {
              'filePath': missingPath,
              'animeName': 'X21 remote',
              'lastWatchTime': '2026-10-11T00:00:00.000Z',
            }
          ],
          'episodeMatches': [
            {
              'filePath': missingPath,
              'animeId': 99,
              'episodeId': 9901,
            }
          ],
        }));
        final historyResult = await backup.importBackup(
            filePath: missingHistory,
            categories: {
              BackupCategory.watchHistory,
              BackupCategory.episodeMatches
            });
        expect(historyResult.success, false);
        expect(historyResult.status, 'skipped');
        expect(historyResult.totalRestoredCount, 0);
        expect(historyResult.totalSkippedCount, 2);
        expect(historyResult.credentialSkips, hasLength(2));
        expect(await historyDb.query('watch_history'), rowsBefore);
        expect(await File('${root.path}/preferences.json').readAsBytes(),
            storedBefore);
        expect(vault.values, originalVault);
        print(
            'X21 missing history references: status=${historyResult.status}; restored=${historyResult.totalRestoredCount}; skipped=${historyResult.totalSkippedCount}; sqliteRowsUnchanged=true; preferenceFileUnchanged=true; vaultUnchanged=true');
      } finally {
        reloaded?.dispose();
        plugins?.dispose();
        await WatchHistoryDatabase.instance.close();
        CredentialStore.instance = previousStore;
        StorageService.debugAppStorageDirectoryOverride = previousStorage;
        PathProviderPlatform.instance = previousPaths;
        SharedPreferencesStorePlatform.instance = previousPreferences;
        SharedPreferences.resetStatic();
        await root.delete(recursive: true);
        print('X21 cleanup: temporaryDirectoryExists=${await root.exists()}');
      }
    });
  });
}
