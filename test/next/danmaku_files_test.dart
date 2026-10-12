import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'danmaku_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refresh and revoke collect only unreferenced imported files', () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final first = await f.file();
    final second = await f.file(path: '/fixture/second.mkv');
    const video = DanmakuVideo(
        sourceId: 'youku', videoId: 'x42', title: 'fixture', durationMs: 1000);
    final entries = [
      const DanmakuEntry(
          sourceId: 'youku',
          videoId: 'x42',
          platform: 'youku',
          sourceTimeMs: 200,
          text: '唯一副本',
          mode: 1,
          colorRgb: 0xffffff)
    ];
    final store = f.service.store;
    Future<JsonMap> put(String entity, List<DanmakuEntry> rows) =>
        store.importEntries(entity, video, rows, '/deleted.xml', null,
            Invocation(origin: 'mcp'));
    final a = await put(first, entries);
    final b = await put(second, entries);
    var rows = await store.db.query('danmaku_cache_chunks');
    expect(rows.map((r) => r['file_path']).toSet(), hasLength(1));
    expect(rows.every((r) => r['payload'] == '[]'), true);
    final file = File('${f.root.path}/${rows.first['file_path']}');
    await put(first, []);
    expect(await file.exists(), true,
        reason: 'second binding still owns content');
    expect(await store.entries(b['cache_key'] as String), hasLength(1));
    await store.change(b['id'] as String, b['revision'] as int,
        {'status': 'revoked'}, Invocation(origin: 'mcp'));
    expect(await file.exists(), false);
    final refreshed = await store.binding(a['id'] as String);
    expect(await store.entries(refreshed['cache_key'] as String), isEmpty);
    rows = await store.db.query('danmaku_cache_chunks');
    expect(rows.single['entry_count'], 0);
  });

  test('cache budget excludes imports and removes playback and fetched caches',
      () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final entity = await f.file();
    final store = f.service.store;
    final entries = [
      const DanmakuEntry(
          sourceId: 'dandanplay',
          videoId: '7101',
          platform: 'dandanplay',
          sourceTimeMs: 200,
          text: '保留内容',
          mode: 1,
          colorRgb: 0xffffff)
    ];
    final imported = await store.importEntries(entity, ddpVideo, entries,
        '/deleted.xml', null, Invocation(origin: 'mcp'));
    final other = await f.file(path: '/fixture/automatic.mkv');
    final cacheEntries = [
      DanmakuEntry.fromJson({...entries.single.toJson(), 'text': '可回收内容'})
    ];
    final playback = await store.importEntries(other, ddpVideo, cacheEntries,
        'classic:7101', null, Invocation(origin: 'application:playback'));
    await store.saveChunk('fetch-cache', const DanmakuChunk(0, 0, 1000),
        DanmakuChunkResult(cacheEntries));
    final result = await f.call('danmaku.cache_prune', {'maxBytes': 0});
    expect(result['deletedPools'], 2);
    expect(await store.entries(imported['cache_key'] as String), hasLength(1));
    expect(
        (await store.binding(playback['id'] as String))['cache_key'], isNull);
    expect(await store.db.query('danmaku_cache_chunks'), hasLength(1));
    expect(await store.files.directory.list().length, 1);
  });

  test('cache collection defers while a fetch owns partial results', () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final store = f.service.store;
    await store.saveChunk('partial', const DanmakuChunk(0, 0, 1000),
        const DanmakuChunkResult([]));
    await store.db.insert('jobs', {
      'job_id': 'x42-active', 'type': 'danmaku.fetch', 'state': 'queued',
      'revision': 0, 'created_at': store.now, 'snapshot': '{}'
    });
    expect((await store.files.prune(maxBytes: 0))['deferred'], true);
    expect(await store.db.query('danmaku_cache_chunks'), hasLength(1));
    await store.db.delete('jobs', where: 'job_id=?', whereArgs: ['x42-active']);
    expect((await store.files.prune(maxBytes: 0))['deletedPools'], 1);
  });

  test('interrupted legacy migration resumes exact content and VACUUM',
      () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('x42-migrate-');
    addTearDown(() => root.delete(recursive: true));
    var db = await openNextDatabase(root, factory: databaseFactoryFfi);
    await db.execute('DROP TABLE danmaku_storage_state');
    for (final column in [
      'file_path',
      'entry_count',
      'byte_count',
      'storage_kind'
    ]) {
      await db.execute('ALTER TABLE danmaku_cache_chunks DROP COLUMN $column');
    }
    final payload = jsonEncode(List.generate(
        10000,
        (i) => {
              'sourceId': 'youku',
              'videoId': 'legacy',
              'sourceTimeMs': i,
              'text': '旧导入的每一条都保留 $i',
              'mode': 1,
              'colorRgb': 16777215
            }));
    Future<void> insert(String key, String content) =>
        db.insert('danmaku_cache_chunks', {
          'cache_key': key,
          'chunk_index': 0,
          'start_ms': 0,
          'end_ms': 10000,
          'payload': content,
          'coverage': 'importedPool',
          'fetched_at': '2026-10-13T00:00:00Z'
        });
    await insert('first', payload);
    await insert('second', 'interruption fixture');
    await db.setVersion(14);
    await db.close();
    final before = await File('${root.path}/next.db').length();
    await expectLater(openNextDatabase(root, factory: databaseFactoryFfi),
        throwsA(isA<FormatException>()));
    db = await databaseFactoryFfi.openDatabase('${root.path}/next.db');
    final partial =
        await db.query('danmaku_cache_chunks', orderBy: 'cache_key');
    expect(partial.first['payload'], '[]');
    expect(partial.first['entry_count'], 10000);
    expect(partial.last['file_path'], isNull);
    expect((await db.query('danmaku_storage_state')).single['needs_vacuum'], 1);
    await db.update('danmaku_cache_chunks', {'payload': payload},
        where: 'cache_key=?', whereArgs: ['second']);
    await db.close();
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    final rows = await db.query('danmaku_cache_chunks');
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(row['entry_count'], 10000);
      expect(await File('${root.path}/${row['file_path']}').readAsString(),
          payload);
    }
    expect((await db.query('danmaku_storage_state')).single['needs_vacuum'], 0);
    await db.close();
    expect(await File('${root.path}/next.db').length(), lessThan(before ~/ 2));
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    expect(await db.query('danmaku_cache_chunks'), rows);
    await db.close();
  });

  test(
      'failed refresh preserves old reference and corrupt imported content fails visibly',
      () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final entity = await f.file();
    final store = f.service.store;
    final entries = [
      const DanmakuEntry(
          sourceId: 'dandanplay',
          videoId: '7101',
          platform: 'dandanplay',
          sourceTimeMs: 200,
          text: '原始内容',
          mode: 1,
          colorRgb: 0xffffff)
    ];
    final b = await store.importEntries(entity, ddpVideo, entries,
        '/deleted.xml', null, Invocation(origin: 'mcp'));
    final before = await store.db.query('danmaku_cache_chunks');
    await store.db.execute(
        "CREATE TRIGGER reject_x42 BEFORE INSERT ON danmaku_cache_chunks BEGIN SELECT RAISE(ABORT,'fixture disk commit failure'); END");
    await expectLater(
        store.importEntries(entity, ddpVideo, [], '/deleted.xml', null,
            Invocation(origin: 'mcp')),
        throwsA(isA<DatabaseException>()));
    expect(await store.binding(b['id'] as String), b);
    expect(await store.db.query('danmaku_cache_chunks'), before);
    expect(await store.entries(b['cache_key'] as String), hasLength(1));
    await store.files.collect();
    expect(await store.files.directory.list().length, 1);
    await File('${f.root.path}/${before.single['file_path']}')
        .writeAsString('[]');
    await expectLater(store.entries(b['cache_key'] as String),
        throwsA(isA<FormatException>()));
  });
}
