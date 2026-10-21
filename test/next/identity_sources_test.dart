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

/// Where a file's episode links come from, beside Classic's automatic match,
/// with the production Classic SQLite port and the real identity store.
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
  Future<JsonMap> bind(String path, JsonMap entry, {String origin = 'mcp'}) async {
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('identity-sources-');
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

  test('a file with no link has no sources, a Classic match says so, and an '
      'explicit binding beside it says who made it', () async {
    final path = await video('ep7');
    await connect();
    final store = runtime.service.store;
    final fileId = await store.ensureFile(path);
    expect(await store.linkSources(fileId), isEmpty);

    await seedRow(path, 7001, 7107);
    await runtime.service.syncClassicHistory();
    final classicWork = (await workIdsOf(path)).single;
    final classic = await store.linkSources(fileId);
    expect(classic, hasLength(1));
    expect(classic.values.single, [
      {
        'bindingId': isA<String>(),
        'source': 'classic_match',
        'boundBy': null,
      }
    ]);

    final entry = await bind(path, tmdbBinding(''));
    expect(entry['workId'], isNot(classicWork));
    final both = await store.linkSources(fileId);
    expect(both, hasLength(2));
    final sources = both.values.map((s) => s.single).toList();
    expect(sources.map((s) => s['source']),
        unorderedEquals(['classic_match', 'explicit_binding']));
    final explicit = sources.singleWhere((s) => s['source'] != 'classic_match');
    expect(explicit['boundBy'], 'agent');
    expect(explicit['origin'], 'mcp');
    final identity =
        (await call('media.identity.get', {'path': path}))['identity'] as Map;
    expect((identity['conflicts'] as List).map((c) => c['type']),
        contains('different_episode'));
  });

  test('an explicit binding of the very episode Classic matched is both', () async {
    final path = await video('same');
    await seedRow(path, 7001, 7101);
    await connect();
    final store = runtime.service.store;
    final fileId = await store.ensureFile(path);
    await bind(path, dandanplayBinding(''), origin: 'gui');
    final links = await store.linkSources(fileId);
    expect(links, hasLength(1));
    expect(links.values.single.map((s) => s['source']),
        unorderedEquals(['classic_match', 'explicit_binding']));
    expect(
        links.values.single
            .singleWhere((s) => s['source'] == 'explicit_binding')['boundBy'],
        'user');
  });

  test('unbind_batch leaves the Classic match; deleting its watch record and '
      'syncing removes only that link', () async {
    final path = await video('rm');
    await seedRow(path, 7001, 7107);
    await connect();
    final store = runtime.service.store;
    final fileId = await store.ensureFile(path);
    final classicWork = (await workIdsOf(path)).single;
    final entry = await bind(path, tmdbBinding(''));
    final explicitWork = entry['workId'] as String;
    expect(await workIdsOf(path), hasLength(2));

    // The Classic binding cannot be named for revocation, and omitting
    // bindingIds revokes explicit bindings only.
    final classicBinding = (await jobs.database.query('media_bindings',
            where: "entity_id=? AND source='classic_match' AND status='accepted'",
            whereArgs: [fileId]))
        .single['id'] as String;
    final refused = await invoke('media.identity.unbind_batch', {
      'requestId': 'unbind-classic',
      'entries': [
        {'entityId': fileId, 'bindingIds': [classicBinding], 'reason': 'test'}
      ]
    });
    expect(refused, isA<Failed>());
    expect(await workIdsOf(path), hasLength(2));

    await classicDb.delete('watch_history',
        where: 'file_path=?', whereArgs: [path]);
    await runtime.service.syncClassicHistory();
    expect(await workIdsOf(path), [explicitWork]);
    expect(await workIdsOf(path), isNot(contains(classicWork)));
    final links = await store.linkSources(fileId);
    expect(links.values.single.single['source'], 'explicit_binding');
    final identity =
        (await call('media.identity.get', {'path': path}))['identity'] as Map;
    expect(identity['conflicts'], isEmpty);
  });
}
