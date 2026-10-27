import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File source, marker;
  final database = WatchHistoryDatabase.instance;

  WatchHistoryItem item(String path, int position) => WatchHistoryItem(
      filePath: path,
      animeName: 'Saved $path',
      watchProgress: 0.5,
      lastPosition: position,
      duration: 1000,
      lastWatchTime: DateTime(2026, 10, 27));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('history-scan-bootstrap-');
    StorageService.debugAppStorageDirectoryOverride = root;
    WatchHistoryManager.resetForTesting();
    source = File('${root.path}/watch_history.json');
    marker = File('${source.path}.scan-migration-pending');
    await source.writeAsString(jsonEncode([
      item('/old/one.mkv', 120).toJson(),
      item('/old/two.mkv', 240).toJson(),
    ]));
    expect(await File('${root.path}/watch_history.db').exists(), isFalse);
  });

  tearDown(() async {
    await database.close();
    WatchHistoryManager.resetForTesting();
    StorageService.debugAppStorageDirectoryOverride = null;
    await root.delete(recursive: true);
  });

  Future<void> restart() async {
    await database.close();
    WatchHistoryManager.resetForTesting();
    await WatchHistoryManager.initialize();
  }

  test(
      'first scan preserves all JSON history before making SQLite authoritative',
      () async {
    final original = await source.readAsBytes();
    expect(
        await WatchHistoryManager.commitScanMatch(item('/new.mkv', 0),
            mayCommit: () => true),
        isTrue);
    expect(WatchHistoryManager.isMigratedToDatabase(), isTrue);
    expect(await marker.exists(), isFalse);
    await restart();
    final records = await WatchHistoryManager.getAllHistory();
    expect({
      for (final row in records) row.filePath: row.lastPosition
    }, {
      '/old/one.mkv': 120,
      '/old/two.mkv': 240,
      '/new.mkv': 0,
    });
    expect(await source.readAsBytes(), original);
  });

  test(
      'cancelled first scan retains JSON and restart recovers only the old records',
      () async {
    final original = await source.readAsBytes();
    // Manager checks before entering SQLite; revoke after its legacy batch was
    // inserted but before the scan match, forcing the entire transaction back.
    var sqliteChecks = 0;
    await WatchHistoryManager.initialize();
    expect(WatchHistoryManager.isMigratedToDatabase(), isFalse);
    expect(
        await WatchHistoryManager.commitScanMatch(item('/cancelled.mkv', 0),
            mayCommit: () => ++sqliteChecks < 6),
        isFalse);
    expect(await marker.exists(), isTrue);
    expect(await database.getAllWatchHistory(), isEmpty);
    expect(await source.readAsBytes(), original);
    await restart();
    expect(
        (await WatchHistoryManager.getAllHistory())
            .map((e) => e.filePath)
            .toSet(),
        {'/old/one.mkv', '/old/two.mkv'});
    expect(await marker.exists(), isFalse);
    expect(await source.readAsBytes(), original);
  });

  test(
      'bootstrap never overwrites a newer database row and recovery does not resurrect deleted rows',
      () async {
    await WatchHistoryManager.initialize();
    await database.insertOrUpdateWatchHistory(item('/old/one.mkv', 900));
    expect(
        await WatchHistoryManager.commitScanMatch(item('/new.mkv', 0),
            mayCommit: () => true),
        isTrue);
    expect((await database.getHistoryByFilePath('/old/one.mkv'))!.lastPosition,
        900);
    await database.deleteHistory('/old/two.mkv');
    // Simulate death after SQLite commit and before pending-file cleanup.
    await marker.writeAsString('pending');
    // The committed receipt is authoritative even if the obsolete JSON is now
    // unreadable. Recovery must not re-import it or block the valid database.
    await source.writeAsString('{broken');
    await restart();
    expect(await database.getHistoryByFilePath('/old/two.mkv'), isNull);
    expect((await database.getHistoryByFilePath('/old/one.mkv'))!.lastPosition,
        900);
  });

  test('malformed legacy JSON fails without marking the database migrated',
      () async {
    await WatchHistoryManager.initialize();
    await source.writeAsString('{broken');
    await expectLater(
        WatchHistoryManager.commitScanMatch(item('/new.mkv', 0),
            mayCommit: () => true),
        throwsFormatException);
    expect(WatchHistoryManager.isMigratedToDatabase(), isFalse);
    expect(await File('${root.path}/watch_history.db').exists(), isFalse);
    expect(await source.readAsString(), '{broken');
  });
}
