import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'verified completed receipts expose only their included exact files across restart',
      () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('x35-constraints-');
    final library = await Directory('${root.path}/library').create();
    final downloaded = File('${root.path}/delivered.mp4');
    final sibling = File('${root.path}/unfinished.mp4');
    await downloaded.writeAsString('data');
    await sibling.writeAsString('data');
    var jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    var media = MediaService(
        store: IdentityStore(jobs.database, 'fixture'),
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => [library.path]);
    await expectLater(media.authorizedPath(downloaded.path), throwsA(isA<Failure>()));
    final engine =
        TaskEngine(store: jobs, ownerDeviceId: 'fixture', executors: [
      FakeExecutor(
          type: 'download',
          onExecute: (context) async {
            await context.running();
            await context.succeed(verified(details: {
              'downloadComplete': true,
              'files': [
                {
                  'path': downloaded.path,
                  'canonicalPath': await downloaded.resolveSymbolicLinks(),
                  'actualSize': 4,
                  'expectedSize': 4,
                  'local': true,
                  'included': true
                },
                {
                  'path': sibling.path,
                  'actualSize': 4,
                  'expectedSize': 4,
                  'local': true,
                  'included': false
                }
              ]
            }));
          })
    ]);
    await engine.start();
    final job = await engine.submit(type: 'download', title: 'Fixture');
    await untilState(engine, job.jobId, JobState.succeeded);
    expect(await media.authorizedPath(downloaded.path),
        await downloaded.resolveSymbolicLinks());
    await expectLater(media.authorizedPath(sibling.path), throwsA(isA<Failure>()));
    await expectLater(media.authorizedPath(root.path, directory: true),
        throwsA(isA<Failure>()));
    await engine.close();
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    media = MediaService(
        store: IdentityStore(jobs.database, 'fixture'),
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => [library.path]);
    expect(await media.authorizedPath(downloaded.path),
        await downloaded.resolveSymbolicLinks());
    await downloaded.delete();
    await Link(downloaded.path).create(sibling.path);
    await expectLater(media.authorizedPath(downloaded.path), throwsA(isA<Failure>()));
    await jobs.close();
    await root.delete(recursive: true);
  });

  test(
      'Classic cache refresh preserves bindings and explicit edits without duplicating snapshots',
      () async {
    final f = MediaFixture();
    await f.open();
    final path = await f.file('classic.mp4');
    final location =
        (await f.service.store.locations(path)).single['locator'] as String;
    f.classic.rows[location] = {
      'filePath': location,
      'animeId': 7001,
      'episodeId': 7101,
      'animeName': 'Classic',
      'episodeTitle': '第1集',
      'isFromScan': true,
      'classicMetadata': {
        'language': 'zh-CN',
        'fetchedAt': '2026-10-12T00:00:00Z',
        'fields': {
          'title': '缓存标题',
          'overview': '已有简介',
          'imageUrl': 'https://example.test/poster.jpg'
        }
      }
    };
    await f.service.syncClassicHistory();
    final work =
        (await f.jobs.database.query('media_entities', where: "kind='work'"))
            .single['id'] as String;
    final bindings = await f.jobs.database.query('media_bindings');
    await f.service.store
        .overrideField(work, 'overview', '用户编辑', Invocation(origin: 'test'));
    final cached = f.classic.rows[location]!['classicMetadata'] as Map;
    (cached['fields'] as Map)['overview'] = '更新的缓存';
    await f.service.syncClassicHistory();
    await f.service.syncClassicHistory();
    expect(await f.jobs.database.query('media_bindings'), bindings);
    final metadata = await f.service.store.mergedMetadata(work);
    expect((metadata['fields'] as Map)['overview'], '用户编辑');
    expect((metadata['fields'] as Map)['imageUrl'],
        'https://example.test/poster.jpg');
    final episode = (await f.jobs.database.query('media_entities', where: "kind='episode'")).single['id'];
    final second = await f.file('second.mp4');
    await f.call('media.identity.bind_batch', {'requestId': 'cached-direct', 'entries': [{
      'kind': 'file', 'entityId': second,
      'ref': {'provider': 'dandanplay', 'objectType': 'episode', 'externalId': '7101', 'scope': 'anime/7001'},
      'localEpisodeIds': [episode], 'reason': 'Use existing identity without losing Classic cache'
    }]});
    expect(
        await f.jobs.database.query('media_snapshots',
            where: "json_extract(fields,'\$.source')='classic_cache'"),
        hasLength(2));
    await f.close();
  });
}
