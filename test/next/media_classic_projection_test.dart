import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/next/media/classic_projection.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('next-classic-projection-');
    StorageService.debugAppStorageDirectoryOverride = root;
  });
  tearDown(() async {
    await WatchHistoryDatabase.instance.close();
    StorageService.debugAppStorageDirectoryOverride = null;
    await root.delete(recursive: true);
  });

  test(
      'real Classic SQLite projection changes matching fields while keeping current progress and other columns',
      () async {
    final db = await WatchHistoryDatabase.instance.database;
    final path = '${root.path}/episode.mkv';
    await db.insert('watch_history', {
      'file_path': path,
      'media_key': 'fixture-media-key',
      'anime_name': '',
      'episode_title': null,
      'anime_id': 1,
      'episode_id': 2,
      'watch_progress': 0.4,
      'last_position': 12345,
      'duration': 99999,
      'last_watch_time': '2026-10-10T00:00:00Z',
      'thumbnail_path': '/fixture/thumbnail.jpg',
      'is_from_scan': 0
    });
    final port = WatchHistoryMetadataPort(changed: () async {
      await db.update(
          'watch_history', {'last_position': 23456, 'watch_progress': 0.6},
          where: 'file_path = ?', whereArgs: [path]);
    });
    final fields = {
      'projectionId': 'fixture-projection',
      'animeId': 7001,
      'episodeId': 7101,
      'animeName': 'Animation',
      'episodeTitle': 'Episode 1'
    };
    await port.apply(path, fields);
    expect(await port.verify(path, fields), isTrue);
    final projected = (await db.query('watch_history')).single;
    expect(projected['last_position'], 23456);
    expect(projected['watch_progress'], 0.6);
    expect(projected['duration'], 99999);
    expect(projected['media_key'], 'fixture-media-key');
    expect(DateTime.parse(projected['last_watch_time'] as String),
        DateTime.utc(2026, 10, 10));
    expect(projected['thumbnail_path'], '/fixture/thumbnail.jpg');
    await port.apply(path, {
      ...fields,
      'projectionId': 'independent-confirmation',
      'animeName': 'Refined name'
    });
    expect((await db.query('watch_history')).single['anime_name'], 'Animation');
    await port.apply(
        path, {'clear': true, 'restoreProjectionId': 'fixture-projection'});
    expect(
        await port.verify(
            path, {'clear': true, 'restoreProjectionId': 'fixture-projection'}),
        isTrue);
    final cleared = (await db.query('watch_history')).single;
    expect(cleared['anime_name'], '');
    expect(cleared['anime_id'], 1);
    expect(cleared['episode_id'], 2);
    expect(cleared['last_position'], 23456);
    expect(cleared['duration'], 99999);
    expect((await port.history()).single['lastPosition'], 23456);
  });
}
