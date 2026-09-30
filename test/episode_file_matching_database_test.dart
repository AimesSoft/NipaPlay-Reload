import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/concurrent_video_processor.dart';
import 'package:nipaplay/utils/storage_service.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform previousPaths;
  late Database db;
  final historyDatabase = WatchHistoryDatabase.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'macos_storage_migration_completed': true,
      'macos_storage_migration_version': 1,
    });
    temp = await Directory.systemTemp.createTemp('episode_file_matching_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    StorageService.debugAppStorageDirectoryOverride = temp;
    db = await historyDatabase.database;
    expect(db.path, File('${temp.path}/watch_history.db').path);
  });

  tearDown(() async {
    await historyDatabase.close();
    PathProviderPlatform.instance = previousPaths;
    StorageService.debugAppStorageDirectoryOverride = null;
    await temp.delete(recursive: true);
  });

  Future<void> seed(String path,
      {int animeId = 10,
      int episodeId = 100,
      String animeName = '测试番剧',
      String time = '2026-09-30T12:00:00.000'}) async {
    await db.insert('watch_history', {
      'file_path': path,
      'media_key': 'identity:$path',
      'anime_name': animeName,
      'episode_title': '第一集',
      'anime_id': animeId,
      'episode_id': episodeId,
      'watch_progress': 0.5,
      'last_position': 600000,
      'duration': 1200000,
      'last_watch_time': time,
      'thumbnail_path': '/poster.png',
      'is_from_scan': 1,
    });
  }

  Future<Map<String, dynamic>> matchedInfo(String _) async => {
        'isMatched': true,
        'matches': [
          {
            'animeId': 10,
            'episodeId': 100,
            'animeTitle': '测试番剧',
            'episodeTitle': '第一集',
          }
        ],
      };

  test('matching version 2 keeps version 1 and its own progress', () async {
    await seed('/media/version-1.mkv');
    final version1Before = (await db.query('watch_history',
            where: 'file_path = ?', whereArgs: ['/media/version-1.mkv']))
        .single;

    final result = await ConcurrentVideoProcessor.processVideoPaths(
      ['/media/version-2.mkv'],
      getVideoInfo: matchedInfo,
    );
    expect(result.single.success, isTrue);
    final versions =
        await historyDatabase.getMatchedHistoriesByEpisode(10, 100);
    expect(versions.map((item) => item.filePath).toSet(),
        {'/media/version-1.mkv', '/media/version-2.mkv'});
    expect(
        versions
            .firstWhere((item) => item.filePath == '/media/version-2.mkv')
            .lastPosition,
        0);
    expect(
        (await db.query('watch_history',
                where: 'file_path = ?', whereArgs: ['/media/version-1.mkv']))
            .single,
        version1Before);
    expect(await historyDatabase.getClearedHistoryByEpisode(10, 100), isNull);
  }, skip: !Platform.isLinux);

  test('a deliberately cleared version can still donate its progress',
      () async {
    await seed('/media/old-path.mkv');
    final old =
        await historyDatabase.getHistoryByFilePath('/media/old-path.mkv');
    expect(await historyDatabase.clearMatchInfoForFile(old!), isTrue);
    expect(
        (await historyDatabase.getClearedHistoryByEpisode(10, 100))?.filePath,
        '/media/old-path.mkv');

    final result = await ConcurrentVideoProcessor.processVideoPaths(
      ['/media/new-path.mkv'],
      getVideoInfo: matchedInfo,
    );
    expect(result.single.success, isTrue);
    final versions =
        await historyDatabase.getMatchedHistoriesByEpisode(10, 100);
    expect(versions.single.filePath, '/media/new-path.mkv');
    expect(versions.single.lastPosition, 600000);
    expect(await historyDatabase.getHistoryByFilePath('/media/old-path.mkv'),
        isNull);
  }, skip: !Platform.isLinux);

  test('previously cleared unwatched files remain eligible for matching',
      () async {
    await seed('/media/cleared.mkv');
    final old =
        await historyDatabase.getHistoryByFilePath('/media/cleared.mkv');
    await historyDatabase.clearMatchInfoForFile(old!);
    await db.update(
      'watch_history',
      {'watch_progress': 0.0},
      where: 'file_path = ?',
      whereArgs: ['/media/cleared.mkv'],
    );

    var lookups = 0;
    final result = await ConcurrentVideoProcessor.processVideoPaths(
      ['/media/cleared.mkv'],
      skipPreviouslyMatchedUnwatched: true,
      getVideoInfo: (path) async {
        lookups++;
        return matchedInfo(path);
      },
    );
    expect(lookups, 1);
    expect(result.single.success, isTrue);
    expect(
        (await historyDatabase.getMatchedHistoriesByEpisode(10, 100))
            .single
            .filePath,
        '/media/cleared.mkv');
  }, skip: !Platform.isLinux);

  test('queries every active file of exactly this anime and episode', () async {
    await seed('/media/local.mkv', time: '2026-09-30T10:00:00.000');
    await seed('webdav://dav/first.mkv');
    await seed('smb://smb/first.mkv');
    await seed('/media/other-anime.mkv', animeId: 20);
    await seed('/media/second.mkv', episodeId: 200);
    await seed('/media/unmatched.mkv', animeName: '');
    final matches = await historyDatabase.getMatchedHistoriesByEpisode(10, 100);
    expect(matches.map((item) => item.filePath),
        ['smb://smb/first.mkv', 'webdav://dav/first.mkv', '/media/local.mkv']);
    expect((await db.query('watch_history')).length, 6);
  });

  test('unlinking one file preserves all progress and identity columns',
      () async {
    await seed('/media/first.mkv');
    await seed('webdav://dav/first.mkv');
    final expected =
        (await historyDatabase.getMatchedHistoriesByEpisode(10, 100))
            .firstWhere((item) => item.filePath == '/media/first.mkv');
    // Progress advances while the chooser is open. Unlink must not replay its snapshot.
    await db.update(
        'watch_history', {'last_position': 700000, 'watch_progress': 0.6},
        where: 'file_path = ?', whereArgs: [expected.filePath]);
    final before = (await db.query('watch_history',
            where: 'file_path = ?', whereArgs: [expected.filePath]))
        .single;
    expect(await historyDatabase.clearMatchInfoForFile(expected), isTrue);
    final after = (await db.query('watch_history',
            where: 'file_path = ?', whereArgs: [expected.filePath]))
        .single;
    expect(after, {
      ...before,
      'anime_name': '',
      'episode_title': null,
      'is_from_scan': 0
    });
    expect(
        (await historyDatabase.getMatchedHistoriesByEpisode(10, 100))
            .single
            .filePath,
        'webdav://dav/first.mkv');
  });

  test('does not clear a file rematched while the chooser was open', () async {
    await seed('/media/first.mkv');
    final expected =
        (await historyDatabase.getMatchedHistoriesByEpisode(10, 100)).single;
    await db.update('watch_history', {'anime_id': 20, 'episode_id': 200},
        where: 'file_path = ?', whereArgs: [expected.filePath]);
    expect(await historyDatabase.clearMatchInfoForFile(expected), isFalse);
    expect(
        (await historyDatabase.getMatchedHistoriesByEpisode(20, 200))
            .single
            .animeName,
        '测试番剧');
  });

  test('cleared record retains IDs for existing progress recovery queries',
      () async {
    await seed('/media/first.mkv');
    final expected =
        (await historyDatabase.getMatchedHistoriesByEpisode(10, 100)).single;
    await historyDatabase.clearMatchInfoForFile(expected);
    final recovery = await historyDatabase.getHistoryByEpisode(10, 100);
    expect(recovery, isNotNull);
    expect(recovery!.lastPosition, 600000);
    expect(recovery.animeName, isEmpty);
    expect(
        await historyDatabase.getMatchedHistoriesByEpisode(10, 100), isEmpty);
  });

  test(
      'model clears matching fields while keeping scan file identity and progress',
      () {
    final original = WatchHistoryItem(
      filePath: 'smb://server/first.mkv',
      animeName: '测试番剧',
      episodeTitle: '第一集',
      animeId: 10,
      episodeId: 100,
      watchProgress: 0.5,
      lastPosition: 600000,
      duration: 1200000,
      lastWatchTime: DateTime(2026, 9, 30),
      isFromScan: true,
      videoHash: 'hash',
      mediaKey: 'smb-key',
      thumbnailPath: '/poster.png',
    );
    expect(original.withoutMatchInfo().toJson(), {
      ...original.toJson(),
      'animeName': '',
      'episodeTitle': null,
      'isFromScan': false,
    });
  });
}
