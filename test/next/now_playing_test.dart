import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'media_test_support.dart';

/// A playing file, as the library knows it: the work and the episode by
/// the names [UiDataService.work] and [UiDataService.episodes] use, so the
/// player can show the work's episodes and mark the one playing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late UiDataService service;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('now-playing-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(store: store, ownerDeviceId: 'fixture', executors: []);
    await engine.start();
    final media = MediaService(
        store: IdentityStore(store.database, 'fixture'),
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path]);
    service = UiDataService(
        media,
        engine,
        StateCapability([
          StateView(
              name: 'library.files',
              description: 'fixture',
              fields: const ObjectSchema({}),
              read: (offset, limit) async => [])
        ]),
        StateSources(),
        root,
        MemoryVault());
    final db = store.database;
    Future<void> entity(String id, String kind, String? parent, Map attrs) =>
        db.insert('media_entities', {
          'id': id,
          'kind': kind,
          'parent_id': parent,
          'attributes': jsonEncode(attrs)
        });
    await entity('w1', 'work', null, {'title': '葬送的芙莉莲', 'localOnly': true});
    await entity('r1', 'release', 'w1', {'season': 1});
    for (final (n, title) in [(4, '灵魂安眠之地'), (5, '死者的幻影')]) {
      await entity('e$n', 'episode', 'r1', {'number': '$n', 'title': title});
    }
    await entity('f5', 'file', null, {});
    await db.insert('media_locations', {
      'id': 'l5',
      'file_id': 'f5',
      'source': 'local',
      'owner_device_id': 'fixture',
      'locator': '/v/Frieren - 05.mkv',
      'available': 1
    });
    await db.insert('media_file_episodes', {
      'file_id': 'f5',
      'episode_id': 'e5',
      'relation': 'exact',
      'ordinal': 0
    });
  });
  tearDown(() async {
    await service.close();
    await engine.close();
    await root.delete(recursive: true);
  });

  test('names the work and the episode, and where to find them', () async {
    final now = (await service.nowPlaying('/v/Frieren - 05.mkv'))!;
    expect(now.work, '葬送的芙莉莲');
    expect(now.episode, '第 5 集 死者的幻影');
    expect(now.workId, 'w1');
    expect(now.episodeId, 'e5');
    expect((await service.work(now.workId))!.title, '葬送的芙莉莲');
    final episodes = await service.episodes(now.workId);
    expect(episodes.map((e) => e.episodeId), ['e4', 'e5']);
    expect(
        episodes.where((e) => e.episodeId == now.episodeId).single.number, 5);
  });

  test('a file the library does not hold is not known', () async {
    expect(await service.nowPlaying('/v/elsewhere.mkv'), isNull);
  });
}
