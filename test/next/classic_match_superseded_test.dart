import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/next/capabilities/download_capability.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_executor.dart';
import 'package:nipaplay/next/downloads/download_service.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/next/headless/downloads.dart';
import 'package:nipaplay/next/media/classic_projection.dart';
import 'package:nipaplay/next/media/media_runtime.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';
import 'media_test_support.dart';

/// A declared identity against Classic's automatic dandanplay match, with
/// the production Classic SQLite port and the real identity store.
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

  var requests = 0;
  Future<Outcome<JsonEncodable>> invoke(String action, JsonMap input,
          {String origin = 'mcp'}) =>
      harness.invokeJson(action, input, Invocation(origin: origin));

  Future<JsonMap> call(String action, JsonMap input,
      {String origin = 'mcp'}) async {
    final result = await invoke(action, input, origin: origin);
    expect(result, isA<Completed>(), reason: jsonEncode(result.toEnvelope()));
    final value = (result as Completed).value.toJson();
    expect(harness.lookup(action)!.spec.output.validate(value), isEmpty);
    return value;
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

  /// Binds a file as a download declaration does ([supersede]) or as a plain
  /// `bind_batch` does.
  Future<JsonMap> bind(String path, JsonMap entry,
      {String origin = 'mcp', bool supersede = true}) async {
    final fileId = await runtime.service.store.ensureFile(path);
    final result = await runtime.service.bindBatch(
        {
          'requestId': 'bind-${requests++}',
          'entries': [
            {...entry, 'entityId': fileId}
          ]
        },
        Invocation(origin: origin, id: 'invocation-$requests'),
        supersedeClassicMatch: supersede);
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

  Future<List<String>> shownWorkIds() async => [
        for (final work
            in (await call('media.library.works', {}))['works'] as List)
          (work as Map)['workId'] as String
      ];

  /// The rule the merged library applies to a stored work, as in
  /// `MeshLibrary._buildLocal`.
  Future<bool> mergedShows(String workId) async =>
      (await jobs.database.rawQuery(
              'WITH RECURSIVE t(id) AS (SELECT ? UNION ALL SELECT e.id FROM media_entities e JOIN t ON e.parent_id=t.id) '
              "SELECT EXISTS(SELECT 1 FROM media_bindings WHERE entity_id IN (SELECT id FROM t) AND status='accepted') "
              'OR EXISTS(SELECT 1 FROM media_file_episodes WHERE episode_id IN (SELECT id FROM t)) AS kept',
              [workId]))
          .single['kept'] ==
      1;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('classic-superseded-');
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

  test(
      'a declaration replaces the Classic match: one work, no empty shell, '
      'and Classic syncs do not bring it back', () async {
    final path = await video('ep7');
    await seedRow(path, 7001, 7107);
    await connect();
    final store = runtime.service.store;
    final fileId = await store.ensureFile(path);
    expect(await store.classicMatchOnly(fileId), isTrue);
    final classicWork = (await workIdsOf(path)).single;
    expect(await shownWorkIds(), [classicWork]);
    final classicRow = await classicDb.query('watch_history');

    final entry = await bind(path, tmdbBinding(''));
    final declared = entry['workId'] as String;
    expect(declared, isNot(classicWork));
    final superseded = entry['supersededClassic'] as Map;
    expect(superseded['source'], 'classic_match');
    expect(superseded['workIds'], [classicWork]);
    expect(superseded['emptiedWorkIds'], [classicWork]);
    expect(superseded['episodeIds'], hasLength(1));

    Future<void> expectDeclaredOnly() async {
      expect(await workIdsOf(path), [declared]);
      expect(await shownWorkIds(), [declared]);
      expect(await mergedShows(classicWork), isFalse);
      expect(await mergedShows(declared), isTrue);
      final identity = (await call('media.identity.get', {'path': path}))[
          'identity'] as Map;
      expect(identity['conflicts'], isEmpty);
      expect(
          (identity['bindings'] as List)
              .where((b) => b['status'] == 'accepted')
              .map((b) => b['source']),
          everyElement('explicit_binding'));
      expect(await store.classicMatchOnly(fileId), isFalse);
    }

    await expectDeclaredOnly();
    // Classic's own watch-history row is untouched.
    expect(await classicDb.query('watch_history'), classicRow);

    await runtime.service.syncClassicHistory();
    await call('media.library.import_history', {});
    await expectDeclaredOnly();

    // Classic's row changes: a new observation, still nothing attached.
    await classicDb.update('watch_history',
        {'episode_id': 7108, 'episode_title': 'Fixture episode 7108'},
        where: 'file_path=?', whereArgs: [path]);
    await runtime.service.syncClassicHistory();
    await expectDeclaredOnly();
    final observations = await store.classicObservations(fileId);
    expect(observations.last['provenance'], 'classic_superseded');

    // The same call again is a replay with the same receipt.
    final replay = await call('media.identity.bind_batch', {
      'requestId': 'bind-0',
      'entries': [
        {...tmdbBinding(''), 'entityId': fileId}
      ]
    });
    expect((replay['entries'] as List).single, entry);

    // Another file Classic matches to the same dandanplay series brings that
    // work back, now with that file.
    final other = await video('ep8');
    await seedRow(other, 7001, 7108);
    await runtime.service.syncClassicHistory();
    expect(await workIdsOf(other), [classicWork]);
    expect(await shownWorkIds(), unorderedEquals([classicWork, declared]));
    expect(await workIdsOf(path), [declared]);
  });

  test('a work that still holds another file stays when one file is declared',
      () async {
    final first = await video('keep-1'), second = await video('keep-2');
    await seedRow(first, 7001, 7101);
    await seedRow(second, 7001, 7102);
    await connect();
    final classicWork = (await workIdsOf(first)).single;
    expect(await workIdsOf(second), [classicWork]);

    final entry = await bind(first, tmdbBinding(''));
    final superseded = entry['supersededClassic'] as Map;
    expect(superseded['workIds'], [classicWork]);
    expect(superseded['emptiedWorkIds'], isEmpty);
    expect(await workIdsOf(first), [entry['workId']]);
    expect(await workIdsOf(second), [classicWork]);
    expect(await shownWorkIds(),
        unorderedEquals([classicWork, entry['workId']]));
    final stays = (await call('media.library.work', {'workId': classicWork}))[
        'work'] as Map;
    final files = [
      for (final release in stays['releases'] as List)
        for (final episode in release['episodes'] as List)
          ...episode['files'] as List
    ];
    expect(files, hasLength(1));
  });

  test('a declaration of the very identity Classic matched supersedes nothing',
      () async {
    final path = await video('same');
    await seedRow(path, 7001, 7101);
    await connect();
    final classicWork = (await workIdsOf(path)).single;
    final entry = await bind(path, dandanplayBinding(''));
    expect(entry.containsKey('supersededClassic'), isFalse);
    expect(entry['workId'], classicWork);
    expect(await workIdsOf(path), [classicWork]);
    expect(await shownWorkIds(), [classicWork]);
  });

  test('a plain bind_batch leaves the Classic match beside the binding and '
      'reports the difference', () async {
    final path = await video('plain');
    await seedRow(path, 7001, 7101);
    await connect();
    final classicWork = (await workIdsOf(path)).single;
    final entry = await bind(path, tmdbBinding(''), supersede: false);
    expect(entry.containsKey('supersededClassic'), isFalse);
    expect(await workIdsOf(path), hasLength(2));
    expect(await workIdsOf(path), contains(classicWork));
    final identity =
        (await call('media.identity.get', {'path': path}))['identity'] as Map;
    expect((identity['conflicts'] as List).map((c) => c['type']),
        contains('different_episode'));
  });

  for (final origin in ['gui', 'mcp']) {
    test('a binding by ${origin == 'gui' ? 'the user' : 'an agent'} is not '
        'replaced by a later declaration', () async {
      final path = await video('manual-$origin');
      await connect();
      final first = await bind(path, tmdbBinding('', episodes: [1]),
          origin: origin, supersede: false);
      final manualWork = first['workId'] as String;
      // Classic then matches the file to something else.
      await seedRow(path, 7001, 7101);
      await runtime.service.syncClassicHistory();
      final store = runtime.service.store;
      final fileId = await store.ensureFile(path);
      expect(await workIdsOf(path), hasLength(2));
      expect(await store.classicMatchOnly(fileId), isFalse);

      await expectLater(
          bind(path, tmdbBinding('', episodes: [2]), origin: origin),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.conflict)));
      expect(await workIdsOf(path), hasLength(2));
      expect(await workIdsOf(path), contains(manualWork));
      final accepted = await jobs.database.query('media_bindings',
          where: "entity_id=? AND status='accepted' AND source='classic_match'",
          whereArgs: [fileId]);
      expect(accepted, isNotEmpty);
      expect(await shownWorkIds(), hasLength(2));
    });
  }

  test('a user binding stays accepted when a Classic match that disagrees '
      'is superseded by binding the same episode again', () async {
    final path = await video('repeat');
    await connect();
    final first =
        await bind(path, tmdbBinding(''), origin: 'gui', supersede: false);
    await seedRow(path, 7001, 7101);
    await runtime.service.syncClassicHistory();
    // Re-binding the same episode is allowed; it supersedes the Classic match
    // that disagrees with it, and the user's binding stays accepted.
    final entry = await bind(path, tmdbBinding(''));
    expect(entry['supersededClassic'], isNotNull);
    expect(await workIdsOf(path), [first['workId']]);
    final bindings = await jobs.database.query('media_bindings',
        where: "entity_id=? AND status='accepted'",
        whereArgs: [await runtime.service.store.ensureFile(path)]);
    expect(bindings.map((b) => b['bound_by']), everyElement('user'));
  });

  group('download executor', () {
    late MemoryJobStore store;
    late FakeDownloadBackend backend;
    late DownloadExecutor executor;
    late TaskEngine downloadsEngine;
    late DownloadService downloads;
    late Harness downloadHarness;
    late String path;

    Future<void> connectDownloads(
        {bool scanMatches = true, JsonMap? workerBinding}) async {
      final inner = HeadlessDownloadLibrary(runtime.service);
      final library = _ScanningLibrary(inner, () async {
        if (scanMatches) await seedRow(path, 7001, 7107);
        await runtime.service.syncClassicHistory();
      });
      final backends = DownloadBackends([backend]);
      executor = DownloadExecutor(
          backends: backends,
          library: library,
          isEnabled: () async => true,
          pollInterval: const Duration(milliseconds: 10));
      downloadsEngine = TaskEngine(
          store: store, ownerDeviceId: 'device-test', executors: [executor]);
      executor.engine = downloadsEngine;
      downloads = DownloadService(
          engine: downloadsEngine,
          executor: executor,
          backends: backends,
          library: library);
      downloadHarness = Harness([
        DownloadCapability(
            downloads: downloads,
            sources: DownloadSources(Directory('${root.path}/metadata')))
      ]);
      await downloadsEngine.start();
    }

    void setComplete(bool complete) {
      backend.overrideFiles = [
        DownloadFile(
            location: DownloadLocation(path: path, isLocal: true),
            expectedSize: 4,
            completedBytes: complete ? 4 : 0,
            isVideo: true)
      ];
    }

    Future<Job> until(String id, bool Function(Job) test) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (true) {
        final job = await downloadsEngine.get(id);
        if (test(job)) return job;
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Condition not met: ${job.toJson()}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    JsonMap? binding(Job job) {
      final rows = (job.checkpoint['completedFiles'] as List? ?? []).cast<Map>();
      return rows.isEmpty
          ? null
          : (rows.single['binding'] as Map?)?.cast<String, Object?>();
    }

    JsonMap declaration({int episode = 1}) => {
          'fileIndex': 0,
          'workRef': mediaWorkRef,
          'releaseRef': mediaReleaseRef,
          'episodeRefs': [mediaEpisodeRef(episode)],
        };

    setUp(() async {
      store = MemoryJobStore();
      backend = FakeDownloadBackend(media)..present = true;
      path = (File('${media.path}/episode-7.mkv')
            ..writeAsBytesSync([1, 2, 3, 4]))
          .path;
      await connect();
    });
    tearDown(() async {
      final listed = await downloadsEngine.list();
      await downloadsEngine.close();
      for (final job in listed) {
        await executor.quiesce(job.jobId);
      }
    });

    test(
        'a declaration made before the file finished wins over the match the '
        'Classic scan makes on completion', () async {
      await connectDownloads();
      setComplete(false);
      final job = await downloads.add(testRequest);
      await until(
          job.jobId, (j) => j.state == JobState.running && j.sideEffectCommitted);
      final declared = await downloadHarness.invokeJson(
          'download.declare_files',
          {
            'jobId': job.jobId,
            'fileBindings': [declaration()]
          },
          Invocation(origin: 'mcp', id: 'declare-superseding'));
      expect(declared, isA<Completed>(), reason: '${declared.toEnvelope()}');
      setComplete(true);

      final done = await until(job.jobId,
          (j) => binding(j) != null && binding(j)!['status'] != 'pending');
      final outcome = binding(done)!;
      expect(outcome['status'], 'bound', reason: '$outcome');
      final superseded = outcome['supersededClassic'] as Map;
      expect(superseded['emptiedWorkIds'], hasLength(1));

      final classicWork = (superseded['workIds'] as List).single as String;
      expect(await workIdsOf(path), [outcome['workId']]);
      expect(await shownWorkIds(), [outcome['workId']]);
      expect(await mergedShows(classicWork), isFalse);
      // Classic's row still says what Classic decided.
      expect((await classicDb.query('watch_history')).single['anime_id'], 7001);
      await runtime.service.syncClassicHistory();
      expect(await workIdsOf(path), [outcome['workId']]);
      expect(await shownWorkIds(), [outcome['workId']]);
    });

    test('a declaration made after the file finished replaces the match too',
        () async {
      await connectDownloads();
      setComplete(true);
      final job = await downloads.add(testRequest);
      final finished = await until(
          job.jobId,
          (j) =>
              ((j.checkpoint['completedFiles'] as List?) ?? []).isNotEmpty);
      expect(binding(finished), isNull);
      expect(await workIdsOf(path), hasLength(1));

      final result = await downloadHarness.invokeJson(
          'download.declare_files',
          {
            'jobId': job.jobId,
            'fileBindings': [declaration()]
          },
          Invocation(origin: 'mcp', id: 'declare-after'));
      expect(result, isA<Completed>(), reason: '${result.toEnvelope()}');
      final bindings =
          ((result as Completed).value.toJson()['bindings'] as List).cast<Map>();
      expect(bindings.single['status'], 'bound');
      expect(bindings.single['supersededClassic'], isNotNull);
      expect(await shownWorkIds(), [bindings.single['workId']]);
    });

    test('a file an agent bound first stays as it was', () async {
      await connectDownloads(scanMatches: false);
      // The agent bound the file before the download finished.
      await runtime.service.store.ensureFile(path);
      await bind(path, tmdbBinding('', episodes: [1]));
      await seedRow(path, 7001, 7107);
      setComplete(true);
      final job = await downloads.add(testRequest);
      await until(
          job.jobId,
          (j) =>
              ((j.checkpoint['completedFiles'] as List?) ?? []).isNotEmpty);
      final result = await downloadHarness.invokeJson(
          'download.declare_files',
          {
            'jobId': job.jobId,
            'fileBindings': [declaration(episode: 2)]
          },
          Invocation(origin: 'mcp', id: 'declare-over-agent'));
      final bindings =
          ((result as Completed).value.toJson()['bindings'] as List).cast<Map>();
      expect(bindings.single['status'], 'already_identified');
      expect(bindings.single.containsKey('supersededClassic'), isFalse);
      expect(await workIdsOf(path), hasLength(2));
    });
  });
}

/// The real headless library, with the Classic scan standing in for
/// `importFiles`: it matches the file, then NipaPlay's index follows.
final class _ScanningLibrary implements DownloadLibrary {
  _ScanningLibrary(this.inner, this.scan);
  final HeadlessDownloadLibrary inner;
  final Future<void> Function() scan;
  @override
  Future<bool> get enabled => inner.enabled;
  @override
  bool get isBusy => false;
  @override
  Future<bool> wasImported(String key) => inner.wasImported(key);
  @override
  Future<void> markImported(String key) => inner.markImported(key);
  @override
  Future<JsonMap?> lookup(String path) => inner.lookup(path);
  @override
  Future<bool> importFiles(List<String> paths, String outputDirectory) async {
    await scan();
    return inner.importFiles(paths, outputDirectory);
  }

  @override
  Future<JsonMap> bindFile(
          {required String fileId,
          required JsonMap declaration,
          required String requestId,
          required String origin}) =>
      inner.bindFile(
          fileId: fileId,
          declaration: declaration,
          requestId: requestId,
          origin: origin);
}
