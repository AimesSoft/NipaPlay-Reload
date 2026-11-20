import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'bounded recent snapshot, concurrent reads, and offline history retention',
      () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('history-startup-');
    StorageService.debugAppStorageDirectoryOverride = root;
    final database = WatchHistoryDatabase.instance;
    final opened =
        await Future.wait(List.generate(8, (_) => database.database));
    expect(opened.every((db) => identical(db, opened.first)), isTrue);
    final db = opened.first;
    addTearDown(() async {
      await db.close();
      StorageService.debugAppStorageDirectoryOverride = null;
      await root.delete(recursive: true);
    });
    expect(await database.getRecentWatchHistory(), isEmpty);
    final batch = db.batch();
    for (var i = 0; i < 1000; i++) {
      batch.insert('watch_history', {
        'file_path': 'https://test.invalid/$i.mp4',
        'anime_name': 'Anime $i',
        'watch_progress': .5,
        'last_position': 500,
        'duration': 1000,
        'last_watch_time':
            DateTime(2026, 1, 1).add(Duration(seconds: i)).toIso8601String(),
        'is_from_scan': 0,
      });
    }
    await batch.commit(noResult: true);
    final recent = await database.getRecentWatchHistory();
    expect(recent, hasLength(40));
    expect(recent.first.filePath, endsWith('/999.mp4'));
    final reads = await Future.wait(
        [database.getAllWatchHistory(), database.getAllWatchHistory()]);
    expect(reads[0], hasLength(1000));
    reads[0].first.filePath = 'changed';
    expect(reads[1].first.filePath, endsWith('/999.mp4'));
    final offline = '${root.path}/offline-disk/episode.mp4';
    await db.insert('watch_history', {
      'file_path': offline,
      'anime_name': 'Offline',
      'watch_progress': .5,
      'last_position': 500,
      'duration': 1000,
      'last_watch_time': DateTime.now().toIso8601String(),
      'is_from_scan': 0,
    });
    final provider = WatchHistoryProvider();
    final publishedCounts = <int>[];
    provider.addListener(() => publishedCounts.add(provider.history.length));
    await provider.loadHistory();
    expect(publishedCounts, contains(40));
    expect(publishedCounts, contains(1001));
    expect(await database.getHistoryByFilePath(offline), isNotNull);
    provider.dispose();
  });
}
