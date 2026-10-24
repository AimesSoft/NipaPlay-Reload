import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/local_library_operations.dart';
import 'package:nipaplay/next/media/identity_store.dart' show stableMediaId;
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/settings/application_settings.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late SettingsRegistry settings;
  late Harness harness;
  late ScanService scan;
  late WatchHistoryProvider history;

  setUp(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nipa-local-constraints-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => root.path);
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    settings = SettingsRegistry(db, ApplicationSettings.entries());
    SettingsAccess.registry = settings;
    scan = ScanService.forTesting(completedFilesProcessor: (_) async => []);
    history = WatchHistoryProvider();
    harness = Harness([
      LocalLibraryOperations(scan, history)
    ]);
  });

  tearDown(() async {
    scan.dispose();
    history.dispose();
    await settings.drain();
    SettingsAccess.registry = null;
    await db.close();
    await root.delete(recursive: true);
  });

  test('a bad root in a batch does not persist earlier roots', () async {
    await invokeFailed(
        harness,
        'media.library.roots.add',
        {
          'paths': [root.path, '${root.path}/missing']
        },
        FailureCode.invalidInput);
    expect(scan.scannedFolders, isEmpty);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('nipaplay_scanned_folders'),
        isNull);
    await invokeCompleted(harness, 'media.library.roots.add', {
      'paths': [root.path, root.path]
    });
    expect(scan.scannedFolders, [root.path]);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('nipaplay_scanned_folders'),
        [root.path]);
  });

  test('history selection is required and confirmation fields are rejected',
      () async {
    await invokeFailed(harness, 'history.remove', {}, FailureCode.invalidInput);
    await invokeFailed(
        harness,
        'history.remove',
        {
          'paths': ['/unused'],
          'confirm': true
        },
        FailureCode.invalidInput);
  });

  test('history union and root removal preserve files and unselected progress',
      () async {
    StorageService.debugAppStorageDirectoryOverride = root;
    addTearDown(() async {
      await WatchHistoryDatabase.instance.close();
      StorageService.debugAppStorageDirectoryOverride = null;
    });
    final one = await Directory('${root.path}/one').create();
    final two = await Directory('${root.path}/two').create();
    final paths = [
      '${one.path}/a.mp4',
      '${one.path}/b.mp4',
      '${two.path}/c.mp4'
    ];
    for (final path in paths) {
      await File(path).writeAsString('preserve video');
    }
    await WatchHistoryDatabase.instance.database;
    await WatchHistoryManager.initialize();
    WatchHistoryManager.setMigratedToDatabase(false);
    await LocalLibraryOperations(scan, history).attachClassicHistory();
    for (var i = 0; i < paths.length; i++) {
      await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(
          watchItem(paths[i], animeId: i < 2 ? -27 : -28, positionMs: 1234));
    }
    await invokeCompleted(harness, 'media.library.roots.add', {
      'paths': [one.path, two.path]
    });
    final deleted = await invokeCompleted(harness, 'history.remove', {
      'paths': [paths[0]],
      'animeIds': [-27, -27]
    });
    expect(deleted['removedCount'], 2);
    final survivor = (await WatchHistoryManager.getAllHistory()).single;
    expect(survivor.filePath, paths[2]);
    expect(survivor.lastPosition, 1234);
    final hidden = '${root.path}/unavailable.mkv';
    await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(watchItem(hidden));
    final forgotten = await invokeCompleted(harness, 'history.remove', {
      'entryIds': [stableMediaId('history', hidden)]
    });
    expect(forgotten['removedCount'], 1);
    expect(forgotten['removedEntryIds'], [stableMediaId('history', hidden)]);
    expect(forgotten['removedPaths'], isEmpty);
    expect((await WatchHistoryManager.getAllHistory()).single.filePath, paths[2]);
    await invokeCompleted(harness, 'media.library.roots.remove', {
      'paths': [two.path]
    });
    expect(await WatchHistoryManager.getAllHistory(), isEmpty);
    expect(scan.scannedFolders, [one.path]);
    for (final path in paths) {
      expect(await File(path).readAsString(), 'preserve video');
    }
  });
}
