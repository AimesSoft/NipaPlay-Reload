// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/next/media/classic_projection.dart';
import 'package:nipaplay/next/media/media_runtime.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root, media;
  late Database classic;
  late SqliteJobStore jobs;
  late MediaRuntime runtime;
  late TaskEngine engine;
  late Harness harness;
  late WatchHistoryMetadataPort port;
  late FixtureTransport source;

  Future<void> connect({bool interruptUndo = false, ClassicMetadataPort? projectionPort}) async {
    jobs = await SqliteJobStore.open(Directory('${root.path}/next'),
        factory: databaseFactoryFfi);
    runtime = await MediaRuntime.create(root, jobs.database, 'fixture-device',
        classic: projectionPort ?? (interruptUndo ? _InterruptUndoReadback(port) : port),
        authorizedRoots: () => [media.path],
        durationProbe: (_) async => 1440000,
        providers: [
          DandanplayMetadataProvider(source),
          TmdbMetadataProvider(FixtureTransport('tmdb'))
        ]);
    engine = TaskEngine(
        store: jobs,
        ownerDeviceId: 'fixture-device',
        executors: runtime.executors);
    runtime.attach(engine);
    harness = Harness([runtime.capability, TaskCapability(engine)]);
    await engine.start();
    await runtime.start();
  }

  Future<void> disconnect() async {
    await runtime.quiesce();
    runtime.close();
    await engine.close();
  }

  Future<JsonMap> call(String action, JsonMap input) async {
    final outcome =
        await harness.invokeJson(action, input, Invocation(origin: 'mcp'));
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    final value = (outcome as Completed).value.toJson();
    expect(harness.lookup(action)!.spec.output.validate(value), isEmpty);
    return value;
  }

  Future<String> seed() async {
    final file = await File('${media.path}/original-filename.mkv')
        .writeAsString('fixture video');
    await classic.insert('watch_history', {
      'file_path': file.path,
      'anime_id': null,
      'episode_id': null,
      'anime_name': 'original-filename.mkv',
      'episode_title': null,
      'media_key': 'fixture-media-key',
      'watch_progress': 0.63,
      'last_position': 630000,
      'duration': 1000000,
      'last_watch_time': '2026-10-10T00:00:00Z',
      'thumbnail_path': 'fixture-thumbnail.jpg',
      'is_from_scan': 0
    });
    return file.path;
  }

  Future<JsonMap> bind(String path, {String request = 'bind'}) async =>
      call('media.identity.bind_batch', {
        'requestId': request,
        'entries': [
          {...dandanplayBinding('')..remove('entityId'), 'path': path}
        ]
      });
  JsonMap undo(String id, {String request = 'undo'}) => {
        'requestId': request,
        'entries': [
          {'entityId': id, 'reason': 'Withdraw temporary fixture binding'}
        ]
      };
  JsonMap matching(JsonMap row) => {
        for (final key in [
          'anime_id',
          'episode_id',
          'anime_name',
          'episode_title'
        ])
          key: row[key]
      };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('x8-projection-');
    media = await Directory('${root.path}/media').create();
    StorageService.debugAppStorageDirectoryOverride = root;
    classic = await WatchHistoryDatabase.instance.database;
    port = WatchHistoryMetadataPort(changed: () async {});
    source = FixtureTransport('dandanplay');
  });
  tearDown(() async {
    await disconnect();
    await WatchHistoryDatabase.instance.close();
    StorageService.debugAppStorageDirectoryOverride = null;
    await root.delete(recursive: true);
  });

  test('one batch resolves the Classic history path index once', () async {
    await connect();
    var histories = 0;
    final calls = <String, int>{};
    final lookup = ClassicProjectionLookup(() async {
      histories++;
      return [for (var i = 0; i < 100; i++)
        {'filePath': '${root.path}/history-$i'}];
    }, resolvePath: (path) async {
      calls[path] = (calls[path] ?? 0) + 1;
      return path.replaceAll('/history-', '/content-');
    });
    for (var i = 0; i < 40; i++) {
      final result = await lookup.resolve('${root.path}/content-$i');
      expect(result.locator, '${root.path}/history-$i');
    }
    expect(histories, 1);
    expect(calls.values.fold<int>(0, (a, b) => a + b), 140);
    expect(calls.values.every((count) => count == 1), true);
  });

  test('a multi-file bind shares one Classic lookup across projection drains', () async {
    final first = await seed();
    final template = (await classic.query('watch_history')).single;
    await classic.delete('watch_history');
    final entries = <JsonMap>[];
    for (var i = 0; i < 40; i++) {
      final file = await File('${media.path}/batch-$i.mkv').writeAsString('video $i');
      final alias = await Link('${media.path}/alias-$i.mkv').create(file.path);
      await classic.insert('watch_history', {...template}..remove('id')
        ..['file_path'] = alias.path..['media_key'] = 'batch-$i');
      entries.add({...dandanplayBinding('')..remove('entityId'), 'path': file.path});
    }
    await File(first).delete();
    final counting = _CountingProjectionPort(port);
    await connect(projectionPort: counting);
    await call('media.identity.bind_batch', {'requestId': 'forty-files', 'entries': entries});
    expect(counting.historyReads, 1);
    expect(await classic.query('watch_history'), hasLength(40));
    expect(await jobs.database.query('media_classic_observations'), isEmpty);
  }, skip: Platform.isWindows ? 'Symlink creation requires host privileges' : false);

  test('projection keeps the original Classic alias for delivery, undo and receipts', () async {
    final path = await seed();
    final alias = await Link('${media.path}/classic-alias.mkv').create(path);
    await classic.update('watch_history', {'file_path': alias.path});
    final before = await classic.query('watch_history');
    await connect();
    final bound = await bind(path);
    final entry = (bound['entries'] as List).single as Map;
    final fileId = entry['fileId'] as String;
    expect((entry['classicProjection'] as List).single['locator'], alias.path);
    expect(await classic.query('watch_history'), hasLength(1));
    final read = (await call('media.identity.get', {'path': path}))['identity'] as Map;
    expect(read['id'], fileId);
    expect(await jobs.database.query('media_classic_observations'), isEmpty);
    final projection = (await jobs.database.query('media_projection_outbox')).single;
    final delivery = ((jsonDecode(projection['payload'] as String) as Map)
        ['deliveryLocators'] as Map).values.single as Map;
    expect(delivery['locator'], alias.path);
    expect(delivery['canonicalPath'], await File(path).resolveSymbolicLinks());
    final restored = await call('media.identity.unbind_batch', undo(fileId));
    expect(((restored['entries'] as List).single['classicProjection'] as List)
        .single['locator'], alias.path);
    expect(await classic.query('watch_history'), before);
  }, skip: Platform.isWindows ? 'Symlink creation requires host privileges' : false);

  for (final change in ['retargeted', 'removed']) {
    test('a $change projection alias cannot redirect undo', () async {
      final path = await seed();
      final alias = await Link('${media.path}/classic-alias.mkv').create(path);
      await classic.update('watch_history', {'file_path': alias.path});
      await connect();
      final bound = await bind(path);
      final fileId = (bound['entries'] as List).single['fileId'] as String;
      final projected = await classic.query('watch_history');
      await alias.delete();
      if (change == 'retargeted') {
        final other = await File('${media.path}/other.mkv').writeAsString('other video');
        await alias.create(other.path);
      }
      final input = undo(fileId);
      final refused = await harness.invokeJson('media.identity.unbind_batch',
          input, Invocation(origin: 'mcp'));
      expect(refused, isA<Failed>());
      expect((refused as Failed).failure.code, FailureCode.conflict);
      expect(await classic.query('watch_history'), projected);
      if (change == 'retargeted') await alias.delete();
      await alias.create(path);
      final retried = await call('media.identity.unbind_batch', input);
      expect(((retried['entries'] as List).single['classicProjection'] as List)
          .single['restored'], true);
      expect((await classic.query('watch_history')).single['anime_id'], isNull);
    }, skip: Platform.isWindows ? 'Symlink creation requires host privileges' : false);
  }

  test('multiple equivalent Classic paths are not chosen arbitrarily', () async {
    final path = await seed();
    final a = await Link('${media.path}/alias-a.mkv').create(path);
    final b = await Link('${media.path}/alias-b.mkv').create(path);
    final row = (await classic.query('watch_history')).single;
    await classic.update('watch_history', {'file_path': a.path});
    await classic.insert('watch_history', {...row}..remove('id')
      ..['file_path'] = b.path..['media_key'] = 'other-alias');
    final before = await classic.query('watch_history');
    await connect();
    final refused = await harness.invokeJson('media.identity.bind_batch', {
      'requestId': 'ambiguous-alias', 'entries': [
        {...dandanplayBinding('')..remove('entityId'), 'path': path}]
    }, Invocation(origin: 'mcp'));
    expect(refused, isA<Failed>());
    expect((refused as Failed).failure.code, FailureCode.conflict);
    expect(await classic.query('watch_history'), before);
    expect(await jobs.database.query('media_classic_observations'), isEmpty);
  }, skip: Platform.isWindows ? 'Symlink creation requires host privileges' : false);

  test('X8 unbind restores the entire original row and replay is idempotent',
      () async {
    final path = await seed();
    final before = (await classic.query('watch_history')).single;
    await connect();
    final bound = await bind(path);
    final id = (bound['entries'] as List).single['fileId'] as String;
    final projected = (await classic.query('watch_history')).single;
    expect(projected['anime_name'], '动画样本');
    expect(projected['episode_id'], 7101);
    print('X8 bind: ${jsonEncode(matching(projected))}');
    final result = await call('media.identity.unbind_batch', undo(id));
    expect((await classic.query('watch_history')).single, before);
    final outcome =
        (result['entries'] as List).single['classicProjection'] as List;
    expect(outcome.single['restored'], true);
    expect(await call('media.identity.unbind_batch', undo(id)), result);
    await disconnect();
    await connect();
    expect(await call('media.identity.unbind_batch', undo(id)), result);
    expect((await classic.query('watch_history')).single, before);
    print(
        'X8 undo: ${jsonEncode(matching(before))}; restored=${outcome.single['restored']}; wholeRowEqual=true; retry/restart=true');
    await bind(path, request: 'bind-again');
    expect(await call('media.identity.unbind_batch', undo(id)), result);
    expect((await classic.query('watch_history')).single['episode_id'], 7101);
    await call('media.identity.unbind_batch', undo(id, request: 'undo-again'));
    expect((await classic.query('watch_history')).single, before);
    expect(await jobs.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    print('X8 reentry: second bind/undo restored=true; foreign_key_check=[]');
  });

  for (final change in ['title', 'ids', 'delete', 'recreate']) {
    test('X8 Classic $change edits remain untouched and conflict is visible',
        () async {
      final path = await seed();
      await connect();
      final id =
          ((await bind(path))['entries'] as List).single['fileId'] as String;
      if (change == 'delete' || change == 'recreate') {
        final original = (await classic.query('watch_history')).single;
        await classic
            .delete('watch_history', where: 'file_path=?', whereArgs: [path]);
        if (change == 'recreate') {
          final recreated = {...original}..remove('id');
          await classic.insert('watch_history', recreated);
        }
      } else {
        await classic.update(
            'watch_history',
            change == 'title'
                ? {'anime_name': 'User edited title'}
                : {
                    'anime_id': 8000,
                    'episode_id': 80000001,
                    'anime_name': 'User rematched series'
                  },
            where: 'file_path=?',
            whereArgs: [path]);
      }
      final edited = await classic.query('watch_history');
      final outcome = await harness.invokeJson(
          'media.identity.unbind_batch', undo(id), Invocation(origin: 'mcp'));
      expect((outcome as Failed).failure.code, FailureCode.conflict);
      expect(outcome.failure.message, contains('Classic not restored'));
      expect(await classic.query('watch_history'), edited);
      final identity =
          ((await call('media.identity.get', {'entityId': id}))['identity']
              as JsonMap);
      expect(
          (identity['bindings'] as List)
              .where((b) => b['source'] == 'explicit_binding')
              .every((b) => b['status'] == 'revoked'),
          true);
      expect(
          (identity['conflicts'] as List)
              .any((c) => c['type'] == 'classic_projection'),
          true);
      final retry = await harness.invokeJson(
          'media.identity.unbind_batch', undo(id), Invocation(origin: 'mcp'));
      expect((retry as Failed).failure.code, FailureCode.conflict);
      expect(await classic.query('watch_history'), edited);
      print(
          'X8 $change conflict: code=${outcome.failure.code.name}; NextRevoked=true; ClassicUnchanged=true; identityConflict=true; retry=conflict; message=${outcome.failure.message}');
    });
  }

  test('X8 progress changes survive restoration', () async {
    final path = await seed();
    final before = (await classic.query('watch_history')).single;
    await connect();
    final id =
        ((await bind(path))['entries'] as List).single['fileId'] as String;
    await classic.update(
        'watch_history', {'last_position': 900000, 'watch_progress': 0.9},
        where: 'file_path=?', whereArgs: [path]);
    await call('media.identity.unbind_batch', undo(id));
    expect((await classic.query('watch_history')).single,
        {...before, 'last_position': 900000, 'watch_progress': 0.9});
    print(
        'X8 progress: restored matching=true; last_position=900000; watch_progress=0.9; other columns unchanged=true');
  });

  test(
      'X8 repeated projection retains ownership across a second source binding',
      () async {
    final path = await seed();
    final before = await classic.query('watch_history');
    await connect();
    final original = ((await bind(path))['entries'] as List).single as JsonMap;
    final id = original['fileId'] as String;
    await call('media.identity.bind_batch', {
      'requestId': 'map-tmdb',
      'entries': [
        {
          ...tmdbBinding(id),
          'workId': original['workId'],
          'releaseId': original['releaseId'],
          'localEpisodeIds': original['episodeIds']
        }
      ]
    });
    final identity =
        ((await call('media.identity.get', {'entityId': id}))['identity']
            as JsonMap);
    final tmdbId = (identity['bindings'] as List)
        .singleWhere((b) => b['ref']['provider'] == 'tmdb')['bindingId'];
    await call('media.identity.unbind_batch', {
      'requestId': 'unmap-tmdb',
      'entries': [
        {
          'entityId': id,
          'bindingIds': [tmdbId],
          'reason': 'Withdraw secondary mapping'
        }
      ]
    });
    expect((await classic.query('watch_history')).single['episode_id'], 7101);
    await call('media.identity.unbind_batch', undo(id));
    expect(await classic.query('watch_history'), before);
    print(
        'X8 repeated projection: secondary source bind/unbind kept Classic match=true; final undo restored original row=true');
  });

  for (final change in ['title', 'ids']) {
    test('X8 repeated projection cannot hide a Classic $change conflict',
        () async {
      final path = await seed();
      await connect();
      final original =
          ((await bind(path))['entries'] as List).single as JsonMap;
      final id = original['fileId'] as String;
      await classic.update(
          'watch_history',
          change == 'title'
              ? {'anime_name': 'User changed title'}
              : {
                  'anime_id': 8000,
                  'episode_id': 80000001,
                  'anime_name': 'User rematched'
                },
          where: 'file_path=?',
          whereArgs: [path]);
      final edited = await classic.query('watch_history');
      final secondaryBind = await harness.invokeJson(
          'media.identity.bind_batch',
          {
            'requestId': 'map-tmdb-after-edit',
            'entries': [
              {
                ...tmdbBinding(id),
                'workId': original['workId'],
                'releaseId': original['releaseId'],
                'localEpisodeIds': original['episodeIds']
              }
            ]
          },
          Invocation(origin: 'mcp'));
      expect((secondaryBind as Failed).failure.code, FailureCode.conflict);
      final unbind = await harness.invokeJson(
          'media.identity.unbind_batch', undo(id), Invocation(origin: 'mcp'));
      expect((unbind as Failed).failure.code, FailureCode.conflict);
      expect(await classic.query('watch_history'), edited);
      print(
          'X8 repeated projection after Classic $change edit: secondary bind=conflict; final undo=conflict; Classic untouched=true');
    });
  }

  test('X8 Classic row and undo evidence roll back together on journal failure',
      () async {
    final path = await seed();
    final before = await classic.query('watch_history');
    await connect();
    final id =
        ((await bind(path))['entries'] as List).single['fileId'] as String;
    await call('media.identity.unbind_batch', undo(id));
    final evidence = await classic.query('next_classic_projection_journal');
    await classic.execute(
        "CREATE TRIGGER interrupt_journal BEFORE INSERT ON next_classic_projection_journal BEGIN SELECT RAISE(ABORT,'X8 journal interrupted'); END");
    final input = {
      'requestId': 'journal-failure',
      'entries': [
        {...dandanplayBinding('')..remove('entityId'), 'path': path}
      ]
    };
    await expectLater(
        runtime.service.bindBatch(input, Invocation(origin: 'mcp')),
        throwsA(isA<DatabaseException>()));
    expect(await classic.query('watch_history'), before);
    expect(await classic.query('next_classic_projection_journal'), evidence);
    await classic.execute('DROP TRIGGER interrupt_journal');
    await call('media.identity.bind_batch', input);
    await call(
        'media.identity.unbind_batch', undo(id, request: 'undo-journal-retry'));
    expect(await classic.query('watch_history'), before);
    print(
        'X8 journal interruption: Classic write rolled back=true; prior evidence retained=true; same-request retry restored=true');
  });

  test('X8 newly created history keeps subsequent progress on undo', () async {
    final path =
        (await File('${media.path}/new-file.mkv').writeAsString('fixture'))
            .path;
    await connect();
    final id =
        ((await bind(path))['entries'] as List).single['fileId'] as String;
    final created = (await classic.query('watch_history')).single;
    expect(
        await classic.update(
            'watch_history', {'last_position': 900000, 'watch_progress': 0.9},
            where: 'id=?', whereArgs: [created['id']]),
        1);
    await call('media.identity.unbind_batch', undo(id));
    final row = (await classic.query('watch_history')).single;
    expect(row['anime_id'], null);
    expect(row['episode_id'], null);
    expect(row['anime_name'], 'new-file.mkv');
    expect(row['last_position'], 900000);
    print(
        'X8 new row undo: IDs=null; anime_name=new-file.mkv; retained history/progress=true');
  });

  test('X8 empty upstream titles never clear existing titles', () async {
    final path = await seed();
    (source.responses['/api/v2/bangumi/7001'] as Map)['bangumi']['animeTitle'] =
        '';
    await connect();
    final bound = await bind(path);
    final id = (bound['entries'] as List).single['fileId'] as String;
    expect((await classic.query('watch_history')).single['anime_name'],
        'original-filename.mkv');
    await call('media.identity.unbind_batch', undo(id));
    print(
        'X8 empty upstream anime title: projected anime_name=original-filename.mkv; restored=true');
    (source.responses['/api/v2/bangumi/7001'] as Map)['bangumi']['episodes'][0]
        ['episodeTitle'] = '';
    final before = await classic.query('watch_history');
    final rejected = await harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'missing-episode-title',
          'entries': [
            {...dandanplayBinding('')..remove('entityId'), 'path': path}
          ]
        },
        Invocation(origin: 'mcp'));
    // A previous nonempty provider snapshot is valid evidence for this same episode.
    expect(rejected, isA<Completed>());
    expect(
        (await classic.query('watch_history')).single['episode_title'], '第一话');
    await call('media.identity.unbind_batch', undo(id, request: 'undo-title'));
    expect(await classic.query('watch_history'), before);
    print(
        'X8 empty newer episode title: retained earlier provider title=第一话; original row restored=true');
  });

  test('X8 undo resumes after Classic committed but readback failed', () async {
    final path = await seed();
    final before = await classic.query('watch_history');
    await connect(interruptUndo: true);
    final id =
        ((await bind(path))['entries'] as List).single['fileId'] as String;
    final failed = await harness.invokeJson(
        'media.identity.unbind_batch', undo(id), Invocation(origin: 'mcp'));
    expect((failed as Failed).failure.code, FailureCode.unavailable);
    expect(await classic.query('watch_history'), before);
    expect(await runtime.service.store.pendingProjections(), hasLength(1));
    await disconnect();
    await connect();
    final job = (await engine.list(type: 'media.project')).single;
    await waitForJob(engine, job.jobId, JobState.succeeded);
    final receipt = await call('media.identity.unbind_batch', undo(id));
    expect(
        (receipt['entries'] as List).single['classicProjection'][0]['restored'],
        true);
    expect(await classic.query('watch_history'), before);
    expect(await runtime.service.store.pendingProjections(), isEmpty);
    print(
        'X8 interrupted undo: readback=unavailable; Classic already restored=true; restart outbox=delivered; receipt.restored=true; row unchanged=true');
  });

  test('X8 old projection without journal is preserved and reports conflict',
      () async {
    final path = await seed();
    await connect();
    final id =
        ((await bind(path))['entries'] as List).single['fileId'] as String;
    await classic.execute('DROP TABLE next_classic_projection_journal');
    final queued =
        (await jobs.database.query('media_projection_outbox')).single;
    final payload = jsonDecode(queued['payload'] as String) as Map;
    payload.remove('journalVersion');
    await jobs.database.update(
        'media_projection_outbox', {'payload': jsonEncode(payload)},
        where: 'id=?', whereArgs: [queued['id']]);
    final before = await classic.query('watch_history');
    final outcome = await harness.invokeJson(
        'media.identity.unbind_batch', undo(id), Invocation(origin: 'mcp'));
    expect((outcome as Failed).failure.code, FailureCode.conflict);
    expect(outcome.failure.message, contains('no atomic undo evidence'));
    expect(await classic.query('watch_history'), before);
    print(
        'X8 legacy projection: conflict=no atomic undo evidence; Classic untouched=true');
  });

  test(
      'X8 missing episode evidence leaves Classic intact and undo reports not written',
      () async {
    final path = await seed();
    final before = await classic.query('watch_history');
    (source.responses['/api/v2/bangumi/7001'] as Map)['bangumi']['episodes'][0]
        ['episodeTitle'] = '';
    await connect();
    final failure = await harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'empty-title',
          'entries': [
            {...dandanplayBinding('')..remove('entityId'), 'path': path}
          ]
        },
        Invocation(origin: 'mcp'));
    expect((failure as Failed).failure.code, FailureCode.conflict);
    expect(await classic.query('watch_history'), before);
    final id = ((await call('media.identity.get', {'path': path}))['identity']
        as JsonMap)['id'] as String;
    final receipt = await call('media.identity.unbind_batch', undo(id));
    expect(
        (receipt['entries'] as List).single['classicProjection'][0]['status'],
        'not_written');
    expect(
        (receipt['entries'] as List).single['classicProjection'][0]['restored'],
        false);
    expect(await classic.query('watch_history'), before);
    print(
        'X8 missing title evidence: bind=conflict; Classic unchanged=true; undo.status=not_written; undo.restored=false');
  });
}

final class _InterruptUndoReadback implements ClassicMetadataPort {
  _InterruptUndoReadback(this.port);
  final ClassicMetadataPort port;
  @override
  Future<List<JsonMap>> history() => port.history();
  @override
  Future<void> apply(String locator, JsonMap fields) =>
      port.apply(locator, fields);
  @override
  Future<bool> verify(String locator, JsonMap fields) async =>
      fields['clear'] == true ? false : await port.verify(locator, fields);
}


final class _CountingProjectionPort implements ReversibleClassicMetadataPort {
  _CountingProjectionPort(this.port);
  final ReversibleClassicMetadataPort port;
  int historyReads = 0;
  @override
  Future<List<JsonMap>> history() {
    historyReads++;
    return port.history();
  }
  @override
  Future<void> apply(String locator, JsonMap fields) => port.apply(locator, fields);
  @override
  Future<bool> verify(String locator, JsonMap fields) => port.verify(locator, fields);
  @override
  Future<JsonMap> projectionOutcome(String locator, JsonMap fields) =>
      port.projectionOutcome(locator, fields);
}
