import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

/// Revoking Classic's automatic recognition of a file from Next only, with the
/// production Classic SQLite port and the real identity store.
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

  Future<void> connect() async {
    jobs = await SqliteJobStore.open(Directory('${root.path}/next'),
        factory: databaseFactoryFfi);
    runtime = await MediaRuntime.create(root, jobs.database, 'fixture-device',
        classic: port,
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

  Future<Outcome<JsonEncodable>> invoke(String action, JsonMap input,
          {String origin = 'mcp'}) =>
      harness.invokeJson(action, input, Invocation(origin: origin));

  Future<JsonMap> call(String action, JsonMap input,
      {String origin = 'mcp'}) async {
    final result = await invoke(action, input, origin: origin);
    expect(result, isA<Completed>(), reason: jsonEncode(result.toEnvelope()));
    return (result as Completed).value.toJson();
  }

  Future<void> seedRow(String path, int anime, int episode) =>
      classicDb.insert('watch_history', {
        'file_path': path,
        'media_key': 'fixture-key-$episode',
        'anime_id': anime,
        'episode_id': episode,
        'anime_name': 'Fixture series $anime',
        'episode_title': 'Fixture episode $episode',
        'watch_progress': 0.63,
        'last_position': 630000,
        'duration': 1000000,
        'last_watch_time': '2026-10-10T00:00:00Z',
        'thumbnail_path': 'fixture-thumbnail.jpg',
        'is_from_scan': 1,
      }).then((_) {});

  Future<String> video(String name) async =>
      (await File('${media.path}/$name.mkv')
              .writeAsString('offline fixture video $name'))
          .path;

  var requests = 0;
  Future<JsonMap> bind(String path, JsonMap entry,
      {String origin = 'mcp'}) async {
    final fileId = await runtime.service.store.ensureFile(path);
    final result = await runtime.service.bindBatch({
      'requestId': 'bind-${requests++}',
      'entries': [
        {...entry, 'entityId': fileId}
      ]
    }, Invocation(origin: origin, id: 'invocation-$requests'));
    return (result['entries'] as List).single as JsonMap;
  }

  Future<List<String>> workIdsOf(String path) async {
    final fileId = await runtime.service.store.ensureFile(path);
    return [
      for (final row in await jobs.database.rawQuery(
          'SELECT DISTINCT r.parent_id AS w FROM media_file_episodes fe '
          'JOIN media_entities e ON e.id=fe.episode_id '
          'JOIN media_entities r ON r.id=e.parent_id WHERE fe.file_id=?',
          [fileId]))
        row['w'] as String
    ];
  }

  Future<String> classicBindingOf(String fileId) async =>
      (await jobs.database.query('media_bindings',
              where:
                  "entity_id=? AND source='classic_match' AND status='accepted'",
              whereArgs: [fileId]))
          .single['id'] as String;

  Future<JsonMap> unbindClassic(String fileId, String bindingId,
          {String requestId = 'unbind-classic'}) =>
      call('media.identity.unbind_batch', {
        'requestId': requestId,
        'entries': [
          {
            'entityId': fileId,
            'bindingIds': [bindingId],
            'reason': 'Classic matched the wrong series'
          }
        ]
      });

  Future<JsonMap> restoreClassic(String fileId,
          {String requestId = 'restore-classic', List<String>? bindingIds}) =>
      call('media.identity.restore_classic_batch', {
        'requestId': requestId,
        'entries': [
          {
            'entityId': fileId,
            if (bindingIds != null) 'bindingIds': bindingIds,
            'reason': 'The match was right'
          }
        ]
      });

  Future<JsonMap> classicRow(String path) async => (await classicDb.query(
          'watch_history',
          where: 'file_path=?',
          whereArgs: [path]))
      .single;

  Future<List<JsonMap>> outbox() => jobs.database
      .query('media_projection_outbox', orderBy: 'id');

  // The library rule of mesh/library.dart: a work without a localOnly mark is
  // shown only with an accepted binding or a file link somewhere in its tree.
  Future<bool> viewerShows(String workId) async => (await jobs.database.rawQuery(
          'WITH RECURSIVE t(id) AS (SELECT ? UNION ALL SELECT e.id FROM media_entities e JOIN t ON e.parent_id=t.id) '
          "SELECT EXISTS(SELECT 1 FROM media_bindings WHERE entity_id IN (SELECT id FROM t) AND status='accepted') "
          'OR EXISTS(SELECT 1 FROM media_file_episodes WHERE episode_id IN (SELECT id FROM t)) AS kept',
          [workId]))
      .single['kept'] ==
      1;

  Future<JsonMap> currentObservation(String path) async {
    final fileId = await runtime.service.store.ensureFile(path);
    return (await runtime.service.store.classicObservations(fileId,
            currentOnly: true))
        .single;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('classic-revoke-');
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

  test('revoking the Classic match leaves the explicit episode, the Classic '
      'record and its progress; later syncs do not attach it again', () async {
    final path = await video('ep7');
    await seedRow(path, 7001, 7107);
    await connect();
    final store = runtime.service.store;
    final fileId = await store.ensureFile(path);
    final classicWork = (await workIdsOf(path)).single;
    final explicitWork = (await bind(path, tmdbBinding(''))) ['workId'] as String;
    final classicBinding = await classicBindingOf(fileId);
    final before = await classicRow(path);
    final outboxBefore = await outbox();

    final result = await unbindClassic(fileId, classicBinding);
    final entry = (result['entries'] as List).single as Map;
    expect(entry['bindingIds'], [classicBinding]);
    expect(entry['classicProjectionId'], isNull);
    // The Classic work held only this file: episode, release and work lose
    // their Classic identity bindings too.
    expect(entry['releasedBindingIds'], hasLength(3));

    expect(await workIdsOf(path), [explicitWork]);
    final links = await store.linkSources(fileId);
    expect(links, hasLength(1));
    expect(links.values.single.single['source'], 'explicit_binding');
    expect(await classicRow(path), before);
    expect(await outbox(), outboxBefore);
    final observation = await currentObservation(path);
    expect(observation['provenance'], 'classic_match_revoked');
    expect(observation['animeId'], 7001);
    expect(observation['episodeId'], 7107);
    final identity =
        (await call('media.identity.get', {'path': path}))['identity'] as Map;
    expect(identity['conflicts'], isEmpty);
    final revoked = (identity['bindings'] as List)
        .singleWhere((b) => b['bindingId'] == classicBinding);
    expect(revoked['status'], 'revoked');
    expect(revoked['source'], 'classic_match');
    final audit = (identity['evidence'] as List).where((e) =>
        e['bindingId'] == classicBinding && e['event'] == 'unbind');
    expect(audit, hasLength(1));
    expect(audit.single['origin'], 'mcp');
    expect(audit.single['reason'], 'Classic matched the wrong series');

    // Sync again, by every way in: nothing is attached again.
    await runtime.service.syncClassicHistory();
    await call('media.library.import_history', {});
    await call('media.identity.get', {'path': path});
    expect(await workIdsOf(path), [explicitWork]);
    expect(await store.classicObservations(fileId), hasLength(1));
    expect(await classicRow(path), before);
    expect(await outbox(), outboxBefore);

    // Library: the work Classic made has nothing left; the explicit one stays.
    expect(await viewerShows(classicWork), isFalse);
    expect(await viewerShows(explicitWork), isTrue);
  });

  test('a Classic work that still has another file is not emptied', () async {
    final a = await video('a'), b = await video('b');
    await seedRow(a, 7001, 7107);
    await seedRow(b, 7001, 7108);
    await connect();
    final store = runtime.service.store;
    final fileA = await store.ensureFile(a);
    final work = (await workIdsOf(a)).single;
    final result = await unbindClassic(fileA, await classicBindingOf(fileA));
    final entry = (result['entries'] as List).single as Map;
    // Only the episode of file a loses its identity; release and work keep
    // the other episode.
    expect(entry['releasedBindingIds'], hasLength(1));
    expect(await workIdsOf(a), isEmpty);
    expect(await workIdsOf(b), [work]);
    expect(await viewerShows(work), isTrue);
  });

  test('Classic recording a different recognition imports the new one',
      () async {
    final path = await video('ep7');
    await seedRow(path, 7001, 7107);
    await connect();
    final store = runtime.service.store;
    final fileId = await store.ensureFile(path);
    final binding = await classicBindingOf(fileId);
    await unbindClassic(fileId, binding);
    expect(await workIdsOf(path), isEmpty);

    await classicDb.update(
        'watch_history',
        {
          'anime_id': 7002,
          'episode_id': 7202,
          'anime_name': 'Fixture series 7002',
          'episode_title': 'Fixture episode 7202'
        },
        where: 'file_path=?',
        whereArgs: [path]);
    await runtime.service.syncClassicHistory();
    final linked = await store.linkSources(fileId);
    expect(linked.values.single.single['source'], 'classic_match');
    expect(linked.values.single.single['bindingId'], isNot(binding));
    expect(await workIdsOf(path), hasLength(1));
    final observations = await store.classicObservations(fileId);
    expect(observations.map((o) => o['provenance']),
        ['classic_match_revoked', 'classic_match']);
    expect(observations.last['current'], isTrue);
    // The revoked binding is not revoked a second time by the change.
    final unbinds = await jobs.database.query('media_evidence',
        where: 'binding_id=?', whereArgs: [binding]);
    expect(
        unbinds.where((e) =>
            (jsonDecode(e['payload'] as String) as Map)['event'] == 'unbind'),
        hasLength(1));

    // The old recognition is no longer Classic's: it cannot come back.
    final refused = await invoke('media.identity.restore_classic_batch', {
      'requestId': 'restore-late',
      'entries': [
        {'entityId': fileId, 'bindingIds': [binding], 'reason': 'late'}
      ]
    });
    expect(refused, isA<Failed>());
    expect((await store.linkSources(fileId)).values.single.single['bindingId'],
        isNot(binding));
  });

  test('the revocation can be restored, and replays change nothing', () async {
    final path = await video('ep7');
    await seedRow(path, 7001, 7107);
    await connect();
    final store = runtime.service.store;
    final fileId = await store.ensureFile(path);
    final classicWork = (await workIdsOf(path)).single;
    final binding = await classicBindingOf(fileId);
    final before = await classicRow(path);
    final outboxBefore = await outbox();

    final first = await unbindClassic(fileId, binding);
    // Replay: same requestId and input is the same answer, new input is not.
    expect(await unbindClassic(fileId, binding), first);
    final changed = await invoke('media.identity.unbind_batch', {
      'requestId': 'unbind-classic',
      'entries': [
        {'entityId': fileId, 'bindingIds': [binding], 'reason': 'another'}
      ]
    });
    expect(changed, isA<Failed>());
    // A new request naming the already revoked binding is refused.
    final again = await invoke('media.identity.unbind_batch', {
      'requestId': 'unbind-classic-2',
      'entries': [
        {'entityId': fileId, 'bindingIds': [binding], 'reason': 'again'}
      ]
    });
    expect(again, isA<Failed>());
    expect(await workIdsOf(path), isEmpty);
    expect(await viewerShows(classicWork), isFalse);

    final restored = await restoreClassic(fileId, bindingIds: [binding]);
    final entry = (restored['entries'] as List).single as Map;
    expect(entry['bindingIds'], [binding]);
    expect(entry['restoredBindingIds'], hasLength(4));
    expect(await workIdsOf(path), [classicWork]);
    expect(await viewerShows(classicWork), isTrue);
    expect((await currentObservation(path))['provenance'], 'classic_match');
    final links = await store.linkSources(fileId);
    expect(links.values.single.single['bindingId'], binding);
    expect(await classicRow(path), before);
    expect(await outbox(), outboxBefore);

    // Replaying the restore, and syncing, change nothing.
    expect(await restoreClassic(fileId, bindingIds: [binding]), restored);
    await runtime.service.syncClassicHistory();
    expect(await store.classicObservations(fileId), hasLength(1));
    expect(await workIdsOf(path), [classicWork]);
    // Nothing is revoked, so a restore without bindingIds finds nothing.
    final none = await restoreClassic(fileId, requestId: 'restore-none');
    expect(((none['entries'] as List).single as Map)['bindingIds'], isEmpty);

    // And it can be revoked again.
    await unbindClassic(fileId, binding, requestId: 'unbind-classic-3');
    expect(await workIdsOf(path), isEmpty);
    expect((await currentObservation(path))['provenance'],
        'classic_match_revoked');
  });

  test('explicit bindings still go the old way; Classic bindings are not '
      'selected by omission, and only a file can name one', () async {
    final path = await video('ep7');
    await seedRow(path, 7001, 7107);
    await connect();
    final store = runtime.service.store;
    final fileId = await store.ensureFile(path);
    final classicBinding = await classicBindingOf(fileId);
    final explicitWork = (await bind(path, tmdbBinding('')))['workId'] as String;

    final result = await call('media.identity.unbind_batch', {
      'requestId': 'unbind-explicit',
      'entries': [
        {'entityId': fileId, 'reason': 'wrong episode'}
      ]
    });
    final entry = (result['entries'] as List).single as Map;
    expect(entry['bindingIds'], isNot(contains(classicBinding)));
    expect(entry['bindingIds'], hasLength(1));
    expect(entry.containsKey('releasedBindingIds'), isFalse);
    expect(await workIdsOf(path), isNot(contains(explicitWork)));
    expect((await store.linkSources(fileId)).values.single.single,
        containsPair('source', 'classic_match'));
    expect((await currentObservation(path))['provenance'], 'classic_match');

    // A Classic binding of an episode cannot be named through the episode.
    final episode = (await jobs.database.query('media_bindings',
            where:
                "source='classic_match' AND status='accepted' AND entity_id!=?",
            whereArgs: [fileId]))
        .firstWhere((b) => b['entity_id'] != fileId);
    final refused = await invoke('media.identity.unbind_batch', {
      'requestId': 'unbind-episode',
      'entries': [
        {
          'entityId': episode['entity_id'],
          'bindingIds': [episode['id']],
          'reason': 'test'
        }
      ]
    });
    expect(refused, isA<Failed>());
  });

  test('a dandanplay binding of the same episode keeps the link and writes '
      'nothing to Classic when the Classic match is revoked', () async {
    final path = await video('same');
    await seedRow(path, 7001, 7101);
    await connect();
    final store = runtime.service.store;
    final fileId = await store.ensureFile(path);
    await bind(path, dandanplayBinding(''), origin: 'gui');
    final binding = await classicBindingOf(fileId);
    final before = await classicRow(path);
    final outboxBefore = await outbox();
    expect(outboxBefore, isNotEmpty);

    final result = await unbindClassic(fileId, binding);
    final entry = (result['entries'] as List).single as Map;
    expect(entry['classicProjectionId'], isNull);
    expect(entry.containsKey('releasedBindingIds'), isFalse);
    final links = await store.linkSources(fileId);
    expect(links.values.single.map((s) => s['source']), ['explicit_binding']);
    expect(await classicRow(path), before);
    expect(await outbox(), outboxBefore);
    await runtime.service.syncClassicHistory();
    expect(await classicRow(path), before);
    expect(await outbox(), outboxBefore);
    expect((await store.linkSources(fileId)).values.single.map((s) => s['source']),
        ['explicit_binding']);
  });
}
