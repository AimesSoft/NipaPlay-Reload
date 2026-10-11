import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/settings/download_settings.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Agent settings update the Classic provider and preserve unrelated persisted data',
      () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.downloaderEnabled: true,
      SettingsKeys.torrentDownloadDirectory: '/tmp/old-downloads',
      SettingsKeys.downloaderVerifiedScannedCompletedTaskKeys: [
        'existing|/tmp/old-downloads'
      ],
      'unrelated': 'retained',
    });
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('x19-settings-');
    StorageService.debugAppStorageDirectoryOverride = root;
    final database = await openNextDatabase(root, factory: databaseFactoryFfi);
    final provider = DownloaderSettingsProvider();
    await provider.loaded;
    DownloadSettings.provider = provider;
    final registry = SettingsRegistry(database, DownloadSettings.entries());
    addTearDown(() async {
      DownloadSettings.provider = null;
      StorageService.debugAppStorageDirectoryOverride = null;
      provider.dispose();
      await database.close();
      await root.delete(recursive: true);
    });
    await registry.set('download.enabled', false, Invocation(origin: 'agent'));
    expect(provider.enabled, false);
    await registry.set(
        'download.createFolderForTask', false, Invocation(origin: 'agent'));
    expect(provider.createFolderForTask, false);
    await registry.set(
        'download.autoScanCompletedTasks', false, Invocation(origin: 'agent'));
    expect(provider.autoScanCompletedTasks, false);
    await registry.set('download.directory', '${root.path}/chosen',
        Invocation(origin: 'agent'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsKeys.torrentDownloadDirectory),
        '${root.path}/chosen');
    expect(
        prefs.getStringList(
            SettingsKeys.downloaderVerifiedScannedCompletedTaskKeys),
        ['existing|/tmp/old-downloads']);
    expect(prefs.getString('unrelated'), 'retained');
    await expectLater(
        registry.set(
            'download.directory', 'relative', Invocation(origin: 'agent')),
        throwsA(isA<Failure>()));
    expect(prefs.getString(SettingsKeys.torrentDownloadDirectory),
        '${root.path}/chosen');
    final revisions = await database.query('settings_changes');
    expect(revisions, hasLength(4));
    expect(revisions.every((r) => r['origin'] == 'agent'), true);
    await prefs.remove(SettingsKeys.torrentDownloadDirectory);
    final unset = await registry.get('download.directory');
    expect(unset['value'], '${root.path}/downloads');
    expect(prefs.containsKey(SettingsKeys.torrentDownloadDirectory), false);
    expect(await database.query('settings_changes'), hasLength(4));
  });
}
