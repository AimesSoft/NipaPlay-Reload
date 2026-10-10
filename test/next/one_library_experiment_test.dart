// Experiment transcripts are part of the X5 evidence artifact.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
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
  late Database classicDb;
  late SqliteJobStore jobs;
  late MediaRuntime runtime;
  late TaskEngine engine;
  late Harness harness;
  late ChangeNotifier historyChanges;
  late WatchHistoryMetadataPort port;
  final dandanplay = FixtureTransport('dandanplay');
  final tmdb = FixtureTransport('tmdb');

  Future<void> connect({ClassicMetadataPort? classicPort}) async {
    jobs = await SqliteJobStore.open(Directory('${root.path}/next'),
        factory: databaseFactoryFfi);
    runtime = await MediaRuntime.create(root, jobs.database, 'fixture-device',
        classic: classicPort ?? port,
        authorizedRoots: () => [media.path],
        durationProbe: (_) async => 1440000,
        providers: [
          DandanplayMetadataProvider(dandanplay),
          TmdbMetadataProvider(tmdb)
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
    final result =
        await harness.invokeJson(action, input, Invocation(origin: 'mcp'));
    expect(result, isA<Completed>(), reason: jsonEncode(result.toEnvelope()));
    final value = (result as Completed).value.toJson();
    expect(harness.lookup(action)!.spec.output.validate(value), isEmpty);
    return value;
  }

  Future<void> seedRow(String path, int anime, int episode,
      {bool matched = true}) async {
    await classicDb.insert('watch_history', {
      'file_path': path,
      'media_key': 'fixture-key-$episode',
      'anime_id': anime,
      'episode_id': episode,
      'anime_name': matched ? 'Fixture series $anime' : '',
      'episode_title': matched ? 'Fixture episode $episode' : null,
      'watch_progress': 0.63,
      'last_position': 630000,
      'duration': 1000000,
      'last_watch_time': '2026-10-10T00:00:00Z',
      'thumbnail_path': 'fixture-thumbnail.jpg',
      'is_from_scan': 1,
    });
  }

  Future<String> video(String name) async =>
      (await File('${media.path}/$name.mkv')
              .writeAsString('offline fixture video $name'))
          .path;

  Future<JsonMap> identity(String path) async =>
      (await call('media.identity.get', {'path': path}))['identity'] as JsonMap;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('one-library-');
    media = await Directory('${root.path}/media').create();
    StorageService.debugAppStorageDirectoryOverride = root;
    classicDb = await WatchHistoryDatabase.instance.database;
    historyChanges = ChangeNotifier();
    port = WatchHistoryMetadataPort(
        changed: () async => historyChanges.notifyListeners(),
        historyChanges: historyChanges);
  });

  tearDown(() async {
    await disconnect();
    historyChanges.dispose();
    await WatchHistoryDatabase.instance.close();
    StorageService.debugAppStorageDirectoryOverride = null;
    await root.delete(recursive: true);
  });

  test('X5 shared library with production SQLite port and Classic selectors',
      () async {
    dandanplay.responses['/api/v2/bangumi/8000'] = {
      'bangumi': {
        'animeId': 8000,
        'animeTitle': 'Fixture series 8000',
        'episodes': <JsonMap>[]
      }
    };
    await connect();
    await call('media.identity.bind_batch', {
      'requestId': 'preexisting-works',
      'entries': [
        {
          'kind': 'work',
          'workRef': {
            'provider': 'dandanplay',
            'objectType': 'anime',
            'externalId': '8000',
            'scope': ''
          },
          'reason': 'Preexisting Next work'
        },
        {
          'kind': 'work',
          'workRef': mediaWorkRef,
          'reason': 'Preexisting TMDB work'
        },
      ]
    });
    final originalBindings =
        await jobs.database.query('media_bindings', orderBy: 'id');
    final originalReceipts =
        await jobs.database.query('media_binding_operations', orderBy: 'id');
    expect((await call('media.library.works', {}))['works'], hasLength(2));
    await disconnect();
    const counts = [12, 2, 11, 7, 6, 6, 3, 5, 1];
    for (var series = 0; series < counts.length; series++) {
      for (var episode = 1; episode <= counts[series]; episode++) {
        await seedRow(await video('series-$series-$episode'), 8000 + series,
            8000000 + series * 100 + episode);
      }
    }
    for (var i = 0; i < 2; i++) {
      await seedRow(await video('alternate-$i'), 8004, 8000401 + i);
    }
    for (var i = 0; i < 160; i++) {
      await seedRow(
          i < 100
              ? 'jellyfin://fixture-server/item-$i'
              : '${media.path}/cleared-$i.mkv',
          9999,
          99990000 + i,
          matched: i < 100);
    }
    final before = await classicDb.query('watch_history', orderBy: 'id');
    await connect();
    final store = runtime.service.store;
    final works = (await call('media.library.works', {}))['works'] as List;
    final episodeCount = await jobs.database
        .rawQuery("SELECT count(*) n FROM media_entities WHERE kind='episode'");
    expect(works, hasLength(10));
    expect(episodeCount.single['n'], 53);
    expect(await classicDb.query('watch_history', orderBy: 'id'), before);
    print(
        'X5 initial: history=215; Classic matched files=55; Next works=2->${works.length}; Next episodes=${episodeCount.single['n']}; Classic unchanged=true');
    final bindingsAfter = await jobs.database.query('media_bindings');
    for (final row in originalBindings) {
      expect(bindingsAfter.singleWhere((b) => b['id'] == row['id']), row);
    }
    expect(await jobs.database.query('media_binding_operations', orderBy: 'id'),
        originalReceipts);
    print(
        'X5 existing Next data: both original works reused/retained; bindings/operation receipts unchanged=true');
    final tables = [
      'media_entities',
      'media_bindings',
      'media_snapshots',
      'media_classic_observations'
    ];
    final stable = {
      for (final table in tables)
        table: await jobs.database.query(table, orderBy: 'id')
    };
    await call('media.library.import_history', {});
    for (final table in tables) {
      expect(await jobs.database.query(table, orderBy: 'id'), stable[table]);
    }
    print('X5 repeat: entities/bindings/snapshots/observations unchanged=true');

    final agentPath = await video('agent-dandanplay');
    await seedRow(agentPath, 7777, 77770001, matched: false);
    final protected = (await classicDb.query('watch_history',
            where: 'file_path=?', whereArgs: [agentPath]))
        .single;
    final bind = {
      ...dandanplayBinding('')..remove('entityId'),
      'path': agentPath
    };
    await call('media.identity.bind_batch', {
      'requestId': 'agent-dandan',
      'entries': [bind]
    });
    final projected = (await classicDb.query('watch_history',
            where: 'file_path=?', whereArgs: [agentPath]))
        .single;
    for (final key in protected.keys.where((key) => ![
          'anime_id',
          'episode_id',
          'anime_name',
          'episode_title'
        ].contains(key))) {
      expect(projected[key], protected[key], reason: key);
    }
    final item =
        await WatchHistoryDatabase.instance.getHistoryByFilePath(agentPath);
    expect(item!.episodeId, 7101);
    expect(mediaLibraryItemMatchesSource(item, UnifiedMediaLibrarySource.local),
        isTrue);
    print(
        'X5 Agent Dandanplay: Classic episodeId=${item.episodeId}; Classic card visible=true; protected columns unchanged=true');

    final tmdbPath = await video('agent-tmdb');
    final beforeTmdb = await classicDb.query('watch_history', orderBy: 'id');
    await call('media.identity.bind_batch', {
      'requestId': 'agent-tmdb',
      'entries': [
        {...tmdbBinding('')..remove('entityId'), 'path': tmdbPath}
      ]
    });
    expect(await classicDb.query('watch_history', orderBy: 'id'), beforeTmdb);
    expect(await WatchHistoryDatabase.instance.getHistoryByFilePath(tmdbPath),
        isNull);
    print(
        'X5 Agent TMDB: Next binding accepted=true; Classic rows unchanged=true');

    final conflictPath = '${media.path}/series-0-1.mkv';
    final original = (await classicDb.query('watch_history',
            where: 'file_path=?', whereArgs: [conflictPath]))
        .single;
    final outcome = await harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'conflict',
          'entries': [
            {...bind, 'path': conflictPath}
          ]
        },
        Invocation(origin: 'mcp'));
    expect((outcome as Failed).failure.code, FailureCode.conflict);
    final conflict = await identity(conflictPath);
    expect(
        (conflict['bindings'] as List).where((b) => b['status'] == 'accepted'),
        hasLength(2));
    expect((conflict['conflicts'] as List).map((c) => c['type']),
        containsAll(['different_episode', 'classic_projection']));
    expect(
        await classicDb.query('watch_history',
            where: 'file_path=?', whereArgs: [conflictPath]),
        [original]);
    print('X5 conflict: ${jsonEncode({
          'code': outcome.failure.code.name,
          'acceptedSources': (conflict['bindings'] as List)
              .where((b) => b['status'] == 'accepted')
              .map((b) => b['source'])
              .toList(),
          'conflictTypes':
              (conflict['conflicts'] as List).map((c) => c['type']).toList(),
          'ClassicUnchanged': true
        })}');

    await classicDb.update(
        'watch_history',
        {
          'anime_id': 8010,
          'episode_id': 80100001,
          'anime_name': 'Fixture changed series',
          'episode_title': 'Changed episode'
        },
        where: 'file_path=?',
        whereArgs: [conflictPath]);
    historyChanges.notifyListeners();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while ((await store.classicObservations(conflict['id'] as String,
                currentOnly: true))
            .single['animeId'] !=
        8010) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Classic live observation did not arrive');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final changed = await identity(conflictPath);
    final observations = changed['classicObservations'] as List;
    expect(observations.where((o) => o['current'] == true).single['animeId'],
        8010);
    expect(observations.where((o) => o['current'] == false).single['animeId'],
        8000);
    expect(
        (changed['bindings'] as List).any((b) =>
            b['source'] == 'explicit_binding' && b['status'] == 'accepted'),
        isTrue);
    print(
        'X5 live Classic rematch: currentAnime=8010; old observation retained=true; Agent binding retained=true; conflict visible=true');

    final addedPath = await video('classic-added');
    await seedRow(addedPath, 8020, 80200001);
    historyChanges.notifyListeners();
    await runtime.service.syncClassicHistory();
    expect((await identity(addedPath))['bindings'], isNotEmpty);
    await classicDb
        .delete('watch_history', where: 'file_path=?', whereArgs: [addedPath]);
    await runtime.service.syncClassicHistory();
    final removed = await identity(addedPath);
    expect((removed['bindings'] as List).every((b) => b['status'] == 'revoked'),
        isTrue);
    expect(removed['episodes'], isEmpty);
    expect(removed['classicObservations'], hasLength(2));
    expect(await jobs.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    print(
        'X5 Classic add/delete: added identity=true; removed active link=true; observations retained=2; foreign_key_check=[]');
  });

  test('X5 import interruption rolls back current file and resumes on restart',
      () async {
    await connect();
    for (var i = 1; i <= 53; i++) {
      await seedRow(await video('restart-$i'), 8000 + (i ~/ 7), 8000000 + i);
    }
    final db = jobs.database;
    final before = await classicDb.query('watch_history', orderBy: 'id');
    await db.execute(
        "CREATE TRIGGER interrupt_import BEFORE INSERT ON media_classic_observations WHEN json_extract(NEW.payload,'\$.episodeId')=8000018 BEGIN SELECT RAISE(ABORT,'X5 interrupted at row 18'); END");
    await expectLater(runtime.service.syncClassicHistory(),
        throwsA(isA<DatabaseException>()));
    expect(await db.query('media_classic_observations'), hasLength(17));
    expect(await db.query('media_locations'), hasLength(17));
    final committed =
        await db.query('media_classic_observations', orderBy: 'id');
    print(
        'X5 interrupted: committed observations=17; locations=17; row18 fully rolled back=true');
    await db.execute('DROP TRIGGER interrupt_import');
    await disconnect();
    await connect();
    final restored = await jobs.database.query('media_classic_observations');
    expect(restored, hasLength(53));
    for (final row in committed) {
      expect(restored.singleWhere((r) => r['id'] == row['id']), row);
    }
    expect(await classicDb.query('watch_history', orderBy: 'id'), before);
    expect(await jobs.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    print(
        'X5 restarted: observations=53; first17 preserved=true; Classic unchanged=true; foreign_key_check=[]');
    await runtime.service.syncClassicHistory();
    expect(
        await jobs.database.query('media_classic_observations'), hasLength(53));
    print('X5 restarted repeat: observations=53 (no duplicates)');
  });

  test(
      'independent Classic match survives Agent bind and unbind of the same episode',
      () async {
    final path = await video('same-episode');
    await seedRow(path, 7001, 7101);
    final before = await classicDb.query('watch_history', orderBy: 'id');
    await connect();
    await call('media.identity.bind_batch', {
      'requestId': 'same-episode',
      'entries': [
        {...dandanplayBinding('')..remove('entityId'), 'path': path}
      ]
    });
    final bound = await identity(path);
    expect(bound['conflicts'], isEmpty);
    expect(await classicDb.query('watch_history', orderBy: 'id'), before);
    await call('media.identity.unbind_batch', {
      'requestId': 'same-episode-unbind',
      'entries': [
        {'entityId': bound['id'], 'reason': 'Withdraw only Agent decision'}
      ]
    });
    final unbound = await identity(path);
    expect(
        (unbound['bindings'] as List)
            .where((b) => b['status'] == 'accepted')
            .single['source'],
        'classic_match');
    expect(unbound['episodes'], hasLength(1));
    expect(await classicDb.query('watch_history', orderBy: 'id'), before);
  });

  test('X5 delivery restart after Classic committed but readback interrupted',
      () async {
    await connect(classicPort: _InterruptedReadback(port));
    final path = await video('delivery-restart');
    final input = {
      'requestId': 'delivery-restart',
      'entries': [
        {...dandanplayBinding('')..remove('entityId'), 'path': path}
      ]
    };
    final failed = await harness.invokeJson(
        'media.identity.bind_batch', input, Invocation(origin: 'mcp'));
    expect((failed as Failed).failure.code, FailureCode.unavailable);
    expect((await runtime.service.store.pendingProjections()), hasLength(1));
    final classicBefore = await classicDb.query('watch_history', orderBy: 'id');
    expect(classicBefore.single['episode_id'], 7101);
    final bindingsBefore =
        await jobs.database.query('media_bindings', orderBy: 'id');
    print(
        'X5 delivery interrupted: Classic episode=7101; outbox=pending; Agent binding durable=true');
    await disconnect();
    await connect();
    final projectionJobs = await engine.list(type: 'media.project');
    expect(projectionJobs, hasLength(1));
    final job = await waitForJob(
        engine, projectionJobs.single.jobId, JobState.succeeded);
    expect(job.receipt!.details['projectionVerified'], isTrue);
    expect(
        await classicDb.query('watch_history', orderBy: 'id'), classicBefore);
    expect(await jobs.database.query('media_bindings', orderBy: 'id'),
        bindingsBefore);
    expect(await runtime.service.store.pendingProjections(), isEmpty);
    print(
        'X5 delivery restarted: outbox=delivered; receipt.projectionVerified=true; Classic/bindings unchanged=true');
  });
}

final class _InterruptedReadback implements ClassicMetadataPort {
  _InterruptedReadback(this.port);
  final ClassicMetadataPort port;
  @override
  Future<List<JsonMap>> history() => port.history();
  @override
  Future<void> apply(String locator, JsonMap fields) =>
      port.apply(locator, fields);
  @override
  Future<bool> verify(String locator, JsonMap fields) async => false;
}
