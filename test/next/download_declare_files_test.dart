import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/download_capability.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_executor.dart';
import 'package:nipaplay/next/downloads/download_service.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/next/downloads/file_bindings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';

Map<String, Object?> ref(String type, String id, String scope) => {
      'provider': 'dandanplay',
      'objectType': type,
      'externalId': id,
      'scope': scope
    };

Map<String, Object?> declare(int index, String episode) => {
      'fileIndex': index,
      'workRef': ref('anime', '7', ''),
      'episodeRefs': [ref('episode', episode, 'anime/7')],
    };

void main() {
  late Directory root;
  late JobStore store;
  late FakeDownloadBackend backend;
  late FakeDownloadLibrary library;
  late DownloadExecutor executor;
  late TaskEngine engine;
  late DownloadService downloads;
  late Harness harness;
  late List<String> paths;
  var calls = 0;

  void connect({Duration poll = const Duration(milliseconds: 10)}) {
    final backends = DownloadBackends([backend]);
    executor = DownloadExecutor(
        backends: backends,
        library: library,
        isEnabled: () async => true,
        pollInterval: poll);
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
    executor.engine = engine;
    downloads = DownloadService(
        engine: engine,
        executor: executor,
        backends: backends,
        library: library);
    harness = Harness([
      DownloadCapability(
          downloads: downloads,
          sources: DownloadSources(Directory('${root.path}/metadata')))
    ]);
  }

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-declare-');
    store = MemoryJobStore();
    backend = FakeDownloadBackend(root)..present = true;
    library = FakeDownloadLibrary()..identify = false;
    paths = [
      for (final name in ['a.mkv', 'b.mkv'])
        (File('${root.path}/$name')..writeAsBytesSync([1, 2, 3, 4])).path
    ];
    for (final entry in paths.indexed) {
      library.media[entry.$2] = {
        'path': entry.$2,
        'fileId': 'file-${entry.$1}',
        'workIds': [],
        'episodes': [],
        'identificationPending': true
      };
    }
    connect();
    await engine.start();
  });
  tearDown(() async {
    final jobs = await engine.list();
    await engine.close();
    for (final job in jobs) {
      await executor.quiesce(job.jobId);
    }
    await root.delete(recursive: true);
  });

  /// Which of the two videos the engine reports as fully downloaded.
  void setFiles(List<bool> complete) {
    backend.overrideFiles = [
      for (final entry in paths.indexed)
        DownloadFile(
            location: DownloadLocation(path: entry.$2, isLocal: true),
            expectedSize: 4,
            completedBytes: complete[entry.$1] ? 4 : 0,
            isVideo: true)
    ];
  }

  Future<Job> until(String id, bool Function(Job) test) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (true) {
      final job = await engine.get(id);
      if (test(job)) return job;
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Condition not met: ${job.toJson()}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  List<Map> rows(Job job) =>
      (job.checkpoint['completedFiles'] as List? ?? []).cast<Map>();
  Map? row(Job job, int index) =>
      rows(job).where((r) => r['index'] == index).firstOrNull;
  String? status(Job job, int index) =>
      (row(job, index)?['binding'] as Map?)?['status'] as String?;

  /// A running download whose worker has committed its session.
  Future<Job> running() async {
    final job = await downloads.add(testRequest);
    return until(
        job.jobId, (j) => j.state == JobState.running && j.sideEffectCommitted);
  }

  Future<JsonMap> declareFiles(String jobId, List<JsonMap> bindings,
      {String origin = 'mcp', String? id}) async {
    final outcome = await harness.invokeJson(
        'download.declare_files',
        {'jobId': jobId, 'fileBindings': bindings},
        Invocation(origin: origin, id: id ?? 'declare-${calls++}'));
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    final result = (outcome as Completed).value.toJson();
    expect(
        harness.lookup('download.declare_files')!.spec.output.validate(result),
        isEmpty);
    return result;
  }

  Future<Failure> declareFails(String jobId, List<JsonMap> bindings) async {
    final outcome = await harness.invokeJson(
        'download.declare_files',
        {'jobId': jobId, 'fileBindings': bindings},
        Invocation(origin: 'mcp', id: 'declare-${calls++}'));
    expect(outcome, isA<Failed>(), reason: '${outcome.toEnvelope()}');
    return (outcome as Failed).failure;
  }

  List<Map> results(JsonMap result) =>
      (result['bindings'] as List).cast<Map>();

  test('a declaration given while the file is downloading binds it on completion',
      () async {
    setFiles([false, false]);
    final job = await running();
    final result = await declareFiles(job.jobId, [declare(0, '101')]);
    expect(result['declarationsSaved'], true);
    expect(results(result), [
      {'fileIndex': 0, 'status': 'declared', 'reason': 'not_completed'}
    ]);
    expect(library.bindCalls, isEmpty);
    expect(((result['job'] as Map)['state']), 'running');

    setFiles([true, false]);
    final bound = await until(job.jobId, (j) => status(j, 0) == 'bound');
    expect(bound.state, JobState.running);
    expect(library.bindCalls, hasLength(1));
    expect(library.bindCalls.single['origin'], 'mcp');
    expect(library.bindCalls.single['requestId'],
        matches(RegExp('^download:${job.jobId}:file:0:[0-9a-f]{24}\$')));
    expect(row(bound, 1), isNull);
  });

  test('a file that completes right after a declaration is bound by it',
      () async {
    // Long polls: the declaration and the completion both land while the
    // worker waits, so its next pass is the first to see either.
    await engine.close();
    connect(poll: const Duration(milliseconds: 400));
    await engine.start();
    setFiles([false, false]);
    final job = await running();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    setFiles([true, false]);
    final result = await declareFiles(job.jobId, [declare(0, '101')]);
    expect(results(result).single['status'], 'declared');
    final bound = await until(job.jobId, (j) => status(j, 0) != null);
    expect(status(bound, 0), 'bound');
    expect(library.bindCalls, hasLength(1));
  });

  test('a file already completed is bound at once and the outcome is returned',
      () async {
    setFiles([true, true]);
    library.media[paths[1]] = {
      'path': paths[1],
      'fileId': 'file-1',
      'workIds': ['work-classic'],
      'episodes': [
        {'episodeId': 'episode-classic', 'workId': 'work-classic'}
      ],
      'identificationPending': false
    };
    final job = await running();
    await until(job.jobId, (j) => rows(j).length == 2);
    expect(library.bindCalls, isEmpty);

    final result =
        await declareFiles(job.jobId, [declare(0, '101'), declare(1, '102')]);
    expect(results(result), [
      {
        'fileIndex': 0,
        'status': 'bound',
        'workId': 'work-1',
        'releaseId': 'release-1',
        'episodeIds': ['episode-1']
      },
      {
        'fileIndex': 1,
        'status': 'already_identified',
        'existingEpisodeIds': ['episode-classic']
      },
    ]);
    expect(library.bindCalls.map((c) => c['fileId']), ['file-0']);
    final saved = await engine.get(job.jobId);
    expect(saved.state, JobState.running);
    expect(status(saved, 0), 'bound');
    expect(status(saved, 1), 'already_identified');
    expect(((row(saved, 0)!['media'] as Map)['episodes'] as List), hasLength(1));
    expect(effectiveFileBindings(saved).map((e) => e['fileIndex']), [0, 1]);
  });

  test('a binding that failed is retried by declaring again, and a changed '
      'declaration is not blocked by the earlier request', () async {
    setFiles([true, true]);
    final job = await running();
    await until(job.jobId, (j) => rows(j).length == 2);

    library.bindFailure =
        const Failure(FailureCode.conflict, 'episode refs do not match');
    var result = await declareFiles(job.jobId, [declare(0, '101')]);
    expect(results(result).single['status'], 'failed');
    expect(((results(result).single['error']) as Map)['message'],
        contains('do not match'));
    expect(status(await engine.get(job.jobId), 0), 'failed');

    library.bindFailure = null;
    result = await declareFiles(job.jobId, [declare(0, '101')]);
    expect(results(result).single['status'], 'bound');
    expect(status(await engine.get(job.jobId), 0), 'bound');

    // The file lost its episodes (unbound elsewhere); the declaration changes.
    library.media[paths[0]]!['episodes'] = [];
    result = await declareFiles(job.jobId, [declare(0, '102')]);
    expect(results(result).single,
        containsPair('episodeIds', ['episode-2']));
    final ids = library.bindCalls.map((c) => c['requestId'] as String).toList();
    expect(ids, hasLength(3));
    expect(ids[0], ids[1]);
    expect(ids[2], isNot(ids[0]));
    expect(library.bound, hasLength(2));
    final saved = await engine.get(job.jobId);
    expect(effectiveFileBindings(saved).single['episodeRefs'],
        [ref('episode', '102', 'anime/7')]);
  });

  test('declaring the same thing again replays; another declaration leaves '
      'an identified file alone', () async {
    setFiles([true, true]);
    final job = await running();
    await until(job.jobId, (j) => rows(j).length == 2);
    final first = await declareFiles(job.jobId, [declare(0, '101')],
        id: 'same-request');
    final again = await declareFiles(job.jobId, [declare(0, '101')],
        id: 'same-request');
    expect(results(again), results(first));
    expect(library.bindCalls, hasLength(1));
    expect(library.bound, hasLength(1));

    final other = await declareFiles(job.jobId, [declare(0, '999')]);
    expect(results(other).single['status'], 'already_identified');
    expect(results(other).single['existingEpisodeIds'], ['episode-1']);
    expect(library.bindCalls, hasLength(1));
  });

  test('declarations do not lose updates to the worker or to each other',
      () async {
    setFiles([true, false]);
    final job = await running();
    await until(job.jobId, (j) => row(j, 0) != null);

    // The worker is registering file 1 when the declarations arrive.
    final entered = Completer<void>();
    final gate = Completer<void>();
    library.onImport = (_) {
      if (!entered.isCompleted) entered.complete();
      return gate.future;
    };
    setFiles([true, true]);
    await entered.future;
    var finished = 0;
    final both = Future.wait([
      declareFiles(job.jobId, [declare(0, '101')]).whenComplete(() => finished++),
      declareFiles(job.jobId, [declare(1, '102')]).whenComplete(() => finished++),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(finished, 0, reason: 'they wait for the worker\'s turn');
    expect(library.bindCalls, isEmpty);
    gate.complete();
    final outcomes = await both;
    expect(results(outcomes[0]).single['status'], 'bound');
    expect(results(outcomes[1]).single['status'], 'bound');

    final saved = await until(job.jobId,
        (j) => status(j, 0) == 'bound' && status(j, 1) == 'bound');
    expect(rows(saved), hasLength(2));
    expect(effectiveFileBindings(saved).map((e) => e['fileIndex']), [0, 1]);
    expect(library.bindCalls, hasLength(2));
    // The worker keeps writing and must not undo either change.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final later = await engine.get(job.jobId);
    expect(status(later, 0), 'bound');
    expect(status(later, 1), 'bound');
    expect(effectiveFileBindings(later), hasLength(2));
  });

  test('a declaration survives a restart and is honoured afterwards',
      () async {
    setFiles([false, false]);
    final job = await running();
    await declareFiles(job.jobId, [declare(1, '102')], origin: 'agent');
    await engine.close();
    await executor.quiesce(job.jobId);

    connect();
    await engine.start();
    final recovered = await until(job.jobId,
        (j) => j.state == JobState.running || j.state == JobState.interrupted);
    expect(effectiveFileBindings(recovered).single['fileIndex'], 1);
    setFiles([false, true]);
    final bound = await until(job.jobId, (j) => status(j, 1) == 'bound');
    expect(library.bindCalls.single['origin'], 'agent');
    expect(row(bound, 0), isNull);
  });

  test('a paused download keeps its state and the torrent is not touched',
      () async {
    setFiles([false, true]);
    final job = await running();
    await downloads.pause(job.jobId);
    final before = await engine.get(job.jobId);
    expect(before.state, JobState.paused);
    final pauses = backend.pauses, resumes = backend.resumes;

    final result = await declareFiles(job.jobId, [declare(0, '101')]);
    expect(result['declarationsSaved'], true);
    expect(results(result).single['status'], 'declared');
    final after = await engine.get(job.jobId);
    expect(after.state, JobState.paused);
    expect(backend.paused, true);
    expect(backend.pauses, pauses);
    expect(backend.resumes, resumes);
    expect(effectiveFileBindings(after).single['fileIndex'], 0);
    expect(library.bindCalls, isEmpty);

    setFiles([true, true]);
    await downloads.resume(job.jobId);
    await until(job.jobId, (j) => status(j, 0) == 'bound');
    expect(library.bindCalls, hasLength(1));
  });

  test('a download waiting to retry keeps its retry', () async {
    setFiles([false, false]);
    final job = await running();
    backend.error = 'tracker unreachable';
    final waiting =
        await until(job.jobId, (j) => j.state == JobState.waitingRetry);
    final result = await declareFiles(job.jobId, [declare(0, '101')]);
    expect(result['declarationsSaved'], true);
    final after = await engine.get(job.jobId);
    expect(after.state, JobState.waitingRetry);
    expect(after.retryAt, waiting.retryAt);
    expect(effectiveFileBindings(after).single['fileIndex'], 0);
  });

  test('a finished download binds completed files but its receipt stays',
      () async {
    setFiles([true, true]);
    backend.finished = true;
    backend.completed = 4;
    final job = await downloads.add(testRequest);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect(rows(done), hasLength(2));

    final result = await declareFiles(job.jobId, [declare(0, '101')]);
    expect(result['declarationsSaved'], false);
    expect(results(result).single['status'], 'bound');
    expect(library.bindCalls, hasLength(1));
    final after = await engine.get(job.jobId);
    expect(after.revision, done.revision);
    expect(after.toJson(), done.toJson());
    expect(row(after, 0)!.containsKey('binding'), false);
  });

  test('validation: manifest range, current selection, merge by index, job',
      () async {
    setFiles([false, false]);
    final job = await running();
    expect((await declareFails(job.jobId, [declare(5, '1')])).message,
        contains('does not exist'));
    expect((await declareFails(job.jobId, [declare(0, '1'), declare(0, '2')]))
            .message,
        contains('twice'));
    expect((await declareFails('job-missing', [declare(0, '1')])).code,
        FailureCode.notFound);

    await declareFiles(job.jobId, [declare(0, '101')]);
    await declareFiles(job.jobId, [declare(1, '102')]);
    await declareFiles(job.jobId, [declare(0, '103')]);
    final merged = effectiveFileBindings(await engine.get(job.jobId));
    expect(merged.map((e) => e['fileIndex']), [0, 1]);
    expect(merged[0]['episodeRefs'], [ref('episode', '103', 'anime/7')]);
    expect(merged[1]['episodeRefs'], [ref('episode', '102', 'anime/7')]);

    await downloads.selectFiles(job.jobId, [0]);
    final failure = await declareFails(job.jobId, [declare(1, '102')]);
    expect(failure.code, FailureCode.invalidInput);
    expect(failure.message, contains('selected files'));
    await engine.cancel(job.jobId);
  });
}
