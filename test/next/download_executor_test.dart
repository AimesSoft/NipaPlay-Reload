import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/download_capability.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_executor.dart';
import 'package:nipaplay/next/downloads/download_service.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';

void main() {
  late Directory root;
  late JobStore store;
  late FakeDownloadBackend backend;
  late FakeDownloadLibrary library;
  late DownloadExecutor executor;
  late TaskEngine engine;
  late DownloadService downloads;
  late Harness harness;

  test('scanner acknowledgement cannot replace media readback', () async {
    backend.present = true;
    await backend.finish();
    library.acknowledgeOnly = true;
    final job = await downloads.add(testRequest);
    final retry = await untilState(engine, job.jobId, JobState.waitingRetry);
    expect(retry.phase, 'importing');
    expect(retry.receipt, isNull);
    expect(library.importedKeys, isEmpty);
  });

  test(
      'all files are accounted for while only selected unmatched videos are scanned',
      () async {
    backend.present = true;
    await backend.finish();
    final existingPath = backend.video.location.path;
    library.media[existingPath] = {
      'path': existingPath,
      'animeId': 1,
      'episodeId': 2
    };
    final second = DownloadFile(
        location:
            DownloadLocation(path: '${root.path}/second.mkv', isLocal: true),
        expectedSize: 4,
        isVideo: true);
    final excluded = DownloadFile(
        location:
            DownloadLocation(path: '${root.path}/excluded.mkv', isLocal: true),
        expectedSize: 4,
        isVideo: true,
        included: false);
    await File(second.location.path).writeAsString('done');
    backend.overrideFiles = [backend.video, second, excluded];
    final job = await downloads.add(testRequest);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect(library.scans, [
      [second.location.path]
    ]);
    final files = (done.receipt!.details['files'] as List).cast<JsonMap>();
    expect(files, hasLength(3));
    expect(files.last, containsPair('reason', 'not_selected'));
    expect(files.last['actualSize'], isNull);
    expect(files.take(2).every((row) => row['imported'] == true), isTrue);
  });

  void connect() {
    final backends = DownloadBackends([backend]);
    executor = DownloadExecutor(
        backends: backends,
        library: library,
        isEnabled: () async => true,
        pollInterval: const Duration(milliseconds: 10),
        importRetryDelay: const Duration(minutes: 1));
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
    executor.engine = engine;
    downloads = DownloadService(
        engine: engine,
        executor: executor,
        backends: backends,
        library: library);
    harness = Harness([
      TaskCapability(engine),
      DownloadCapability(
          downloads: downloads,
          sources: DownloadSources(Directory('${root.path}/metadata')))
    ]);
  }

  Future<Job> add() async {
    final outcome = await harness.invokeJson('download.add',
        {'source': testRequest.source}, Invocation(origin: 'test'));
    expect(outcome, isA<Completed<JsonEncodable>>());
    return await engine.get(((outcome as Completed<JsonEncodable>)
        .value
        .toJson()['job'] as JsonMap)['jobId'] as String);
  }

  Future<Job> phase(String id, String value) async {
    var job = await engine.get(id);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (job.phase != value || job.revision < 3) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Expected phase $value; ${job.toJson()}');
      }
      job = await engine.wait(id,
          afterRevision: job.revision,
          timeout: const Duration(milliseconds: 20));
    }
    return job;
  }

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-download-');
    store = MemoryJobStore();
    backend = FakeDownloadBackend(root);
    library = FakeDownloadLibrary();
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

  test(
      'Actions accept immediately, deduplicate concurrent content and expose the same backend',
      () async {
    final gate = Completer<void>();
    backend.addGate = gate.future;
    final jobs = await Future.wait([add(), add()]);
    expect(jobs[0].jobId, jobs[1].jobId);
    expect(jobs[0].toJson()['backend'], {'kind': 'builtin'});
    expect(jobs[0].toJson().containsKey('checkpoint'), isFalse);
    expect(jobs[0].toJson().containsKey('input'), isFalse);
    await backend.addEntered.future;
    gate.complete();
    await phase(jobs[0].jobId, 'downloading');
    backend.completed = 2;
    var progressed = await engine.get(jobs[0].jobId);
    while (progressed.progress.completed != 2) {
      progressed = await engine.wait(progressed.jobId,
          afterRevision: progressed.revision,
          timeout: const Duration(milliseconds: 20));
    }
    expect(progressed.progress.toJson(),
        {'completed': 2, 'total': 4, 'unit': 'bytes'});
    await backend.finish();
    final done = await untilState(engine, progressed.jobId, JobState.succeeded);
    expect(done.receipt!.verification, VerificationLevel.verified);
    final file = (done.receipt!.details['files'] as List).single as JsonMap;
    expect(file['expectedSize'], 4);
    expect(file['actualSize'], 4);
    expect(file['imported'], isTrue);
    expect(file['media'],
        {'path': backend.video.location.path, 'animeId': 1, 'episodeId': 2});
    expect((await add()).jobId, done.jobId);
    expect(backend.additions, 1);
    for (final call in ['download.add', 'task.get', 'task.wait', 'task.list']) {
      final input = call == 'download.add'
          ? {'source': testRequest.source}
          : call == 'task.list'
              ? {'type': 'download'}
              : {'jobId': done.jobId};
      final outcome = await harness.invokeJson(
          call, input, Invocation(origin: 'test')) as Completed<JsonEncodable>;
      expect(harness.lookup(call)!.spec.output.validate(outcome.value.toJson()),
          isEmpty);
      final result = outcome.value.toJson();
      expect(
          call == 'task.list' ? (result['jobs'] as List).single : result['job'],
          done.toJson());
    }
    final phases =
        (await store.events(done.jobId)).map((e) => e.snapshot['phase']);
    expect(
        phases, containsAllInOrder(['downloading', 'verifying', 'importing']));
  });

  test(
      'pause stops native work, resume keeps identity, completed controls only affect seeding',
      () async {
    final job = await add();
    await phase(job.jobId, 'downloading');
    expect((await downloads.pause(job.jobId)).state, JobState.paused);
    expect(backend.paused, isTrue);
    final revision = (await engine.get(job.jobId)).revision;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect((await engine.get(job.jobId)).revision, revision);
    await downloads.resume(job.jobId);
    await untilState(engine, job.jobId, JobState.running);
    expect(backend.paused, isFalse);
    await backend.finish();
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    await downloads.pause(job.jobId);
    expect(backend.paused, isTrue);
    await downloads.resume(job.jobId);
    expect((await engine.get(job.jobId)).toJson(), done.toJson());
    expect(backend.additions, 1);
  });

  test(
      'verification failure cannot succeed or import and its retry can be paused',
      () async {
    backend.present = true;
    await backend.finish(size: 2);
    final job = await add();
    final retry = await untilState(engine, job.jobId, JobState.waitingRetry);
    expect(retry.phase, 'verifying');
    expect(retry.error!.retryable, isTrue);
    expect((retry.checkpoint['files'] as List).single,
        containsPair('reason', 'size_mismatch'));
    expect(library.scans, isEmpty);
    await downloads.pause(job.jobId);
    await backend.finish();
    await downloads.resume(job.jobId);
    await untilState(engine, job.jobId, JobState.succeeded);
  });

  test(
      'busy and unidentified imports retry durably; recovery only scans unmapped files',
      () async {
    backend.present = true;
    await backend.finish();
    library.busy = true;
    final job = await add();
    await untilState(engine, job.jobId, JobState.waitingRetry);
    expect(library.scans, isEmpty);
    library.busy = false;
    library.identify = false;
    final retry = await untilState(engine, job.jobId, JobState.waitingRetry);
    await downloads.pause(retry.jobId);
    await downloads.resume(retry.jobId);
    final unidentified =
        await untilState(engine, job.jobId, JobState.waitingRetry);
    expect((unidentified.checkpoint['files'] as List).single,
        containsPair('reason', 'not_identified'));
    library.media[backend.video.location.path] = {
      'path': backend.video.location.path,
      'animeId': 1,
      'episodeId': 2
    };
    final scans = library.scans.length;
    await downloads.pause(job.jobId);
    await downloads.resume(job.jobId);
    await untilState(engine, job.jobId, JobState.succeeded);
    expect(library.scans.length, scans);
  });

  test(
      'restart reconciles a committed session without a checkpoint and a changed native handle',
      () async {
    await engine.close();
    store = await SqliteJobStore.open(Directory('${root.path}/db'),
        factory: databaseFactoryFfi);
    final now = DateTime.now().toUtc();
    final original = Job(
        jobId: 'stable-job',
        type: 'download',
        title: 'Episode',
        state: JobState.running,
        phase: 'downloading',
        progress: JobProgress(completed: 1, total: 4, unit: 'bytes'),
        createdAt: now,
        updatedAt: now,
        ownerDeviceId: 'device-test',
        revision: 0,
        input: testRequest.toJson(),
        details: {
          'backend': {'kind': 'builtin'}
        });
    await store.commit(
        original,
        JobEvent(
            jobId: original.jobId,
            revision: 0,
            kind: 'fixture',
            at: now,
            snapshot: original.toJson()),
        expectedRevision: null);
    await store.close();
    store = await SqliteJobStore.open(Directory('${root.path}/db'),
        factory: databaseFactoryFfi);
    backend.present = true;
    backend.handle = '98';
    await backend.finish();
    connect();
    await engine.start();
    final done = await untilState(engine, original.jobId, JobState.succeeded);
    expect(done.checkpoint['handle'], '98');
    expect(backend.additions, 0);
    expect((await store.events(done.jobId)).map((e) => e.kind),
        contains('interrupted'));
    await engine.close();
    store = await SqliteJobStore.open(Directory('${root.path}/db'),
        factory: databaseFactoryFfi);
    connect();
    await engine.start();
    expect((await engine.get(done.jobId)).toJson(), done.toJson());
    expect(library.scans, hasLength(1));
  });

  test('recovery never re-adds a missing committed session', () async {
    final job = await add();
    await phase(job.jobId, 'downloading');
    await engine.close();
    await executor.quiesce(job.jobId);
    backend.present = false;
    connect();
    await engine.start();
    final failed = await untilState(engine, job.jobId, JobState.failed);
    expect(failed.receipt!.details['reason'], 'session_missing');
    expect(backend.additions, 1);
  });

  test(
      'cancellation before backend commit stops metadata work with a cancelled receipt',
      () async {
    backend.stopAddBeforeCommit = true;
    final job = await add();
    await backend.addEntered.future;
    await engine.cancel(job.jobId);
    final done = await untilState(engine, job.jobId, JobState.cancelled);
    expect(backend.present, isFalse);
    expect(done.toJson()['receipt'],
        containsPair('cancellation', containsPair('afterCommit', false)));
  });

  test(
      'cancellation after native add pauses and verifies partial committed effects',
      () async {
    final job = await add();
    await phase(job.jobId, 'downloading');
    await File(backend.video.location.path).writeAsString('pa');
    await engine.cancel(job.jobId);
    final done = await untilState(engine, job.jobId, JobState.cancelled);
    expect(backend.paused, isTrue);
    expect(backend.present, isTrue);
    expect(done.receipt!.verification, VerificationLevel.verified);
    expect(done.receipt!.details['downloadComplete'], isFalse);
    expect((done.receipt!.details['files'] as List).single,
        allOf(containsPair('actualSize', 2), containsPair('retained', true)));
    expect(await File(backend.video.location.path).readAsString(), 'pa');
    expect(done.error, isNull);
    expect(backend.removals, 0);
    expect(backend.deletions, 0);
    expect(library.scans, isEmpty);
    expect(done.toJson()['receipt'],
        containsPair('cancellation', containsPair('afterCommit', true)));
    expect((await add()).jobId, job.jobId);
    expect(backend.additions, 1);
  });

  test('cancellation during submitted import still reads back the media result',
      () async {
    backend.present = true;
    await backend.finish();
    final entered = Completer<void>(), release = Completer<void>();
    library.onImport = (_) async {
      entered.complete();
      await release.future;
    };
    final job = await add();
    await entered.future;
    await engine.cancel(job.jobId);
    release.complete();
    final done = await untilState(engine, job.jobId, JobState.cancelled);
    expect(
        (done.receipt!.details['files'] as List).single,
        allOf(containsPair('imported', true), containsPair('actualSize', 4),
            containsPair('retained', true), contains('media')));
    expect(done.receipt!.verification, VerificationLevel.verified);
    expect(done.error, isNull);
    expect(done.toJson()['receipt'],
        containsPair('cancellation', containsPair('phase', 'importing')));
    expect(backend.paused, isTrue);
  });

  test(
      'cancellation records every retained size and distinguishes missing files',
      () async {
    final emptyPath = '${root.path}/empty.mkv';
    final missingPath = '${root.path}/missing.mkv';
    await File(emptyPath).writeAsBytes([]);
    await File(backend.video.location.path).writeAsString('pa');
    backend.overrideFiles = [
      backend.video,
      DownloadFile(
          location: DownloadLocation(path: emptyPath, isLocal: true),
          expectedSize: 4,
          isVideo: true),
      DownloadFile(
          location: DownloadLocation(path: missingPath, isLocal: true),
          expectedSize: 4,
          isVideo: true)
    ];
    final job = await add();
    await phase(job.jobId, 'downloading');
    await engine.cancel(job.jobId);
    final done = await untilState(engine, job.jobId, JobState.cancelled);
    final files = (done.receipt!.details['files'] as List).cast<JsonMap>();
    expect(files.map((row) => row['actualSize']), [2, 0, null]);
    expect(files.map((row) => row['retained']), [true, true, false]);
    expect(files.map((row) => row['path']),
        [backend.video.location.path, emptyPath, missingPath]);
    expect(done.receipt!.details['paused'], true);
    expect(done.error, isNull);
  });

  test(
      'unidentified in-flight import still finishes cancellation without error',
      () async {
    backend.present = true;
    await backend.finish();
    library.acknowledgeOnly = true;
    final entered = Completer<void>(), release = Completer<void>();
    library.onImport = (_) async {
      entered.complete();
      await release.future;
    };
    final job = await add();
    await entered.future;
    await engine.cancel(job.jobId);
    release.complete();
    final done = await untilState(engine, job.jobId, JobState.cancelled);
    expect(done.error, isNull);
    expect(done.receipt!.verification, VerificationLevel.verified);
    expect(
        (done.receipt!.details['files'] as List).single,
        allOf(containsPair('imported', false),
            containsPair('reason', 'not_identified')));
    expect(backend.paused, true);
    expect(library.importedKeys, isEmpty);
  });

  test('a real backend error while stopping remains failed and unverified',
      () async {
    backend.present = true;
    await backend.finish();
    final entered = Completer<void>(), release = Completer<void>();
    library.onImport = (_) async {
      entered.complete();
      await release.future;
    };
    final job = await add();
    await entered.future;
    await engine.cancel(job.jobId);
    backend.online = false;
    release.complete();
    final done = await untilState(engine, job.jobId, JobState.failed);
    expect(done.error!.code, FailureCode.unavailable);
    expect(done.receipt!.verification, VerificationLevel.unverified);
    expect(backend.paused, isFalse);
  });

  test('restart reconciles committed cancellation and preserves partial files',
      () async {
    await engine.close();
    store = await SqliteJobStore.open(Directory('${root.path}/db'),
        factory: databaseFactoryFfi);
    final now = DateTime.now().toUtc();
    final original = Job(
        jobId: 'cancelled-on-restart',
        type: 'download',
        title: 'Episode',
        state: JobState.cancelling,
        phase: 'downloading',
        progress: JobProgress(completed: 2, total: 4, unit: 'bytes'),
        createdAt: now,
        updatedAt: now,
        ownerDeviceId: 'device-test',
        revision: 0,
        input: testRequest.toJson(),
        details: {
          'backend': {'kind': 'builtin'}
        },
        checkpoint: {'handle': 'old-handle'},
        sideEffectCommitted: true,
        cancelRequestedAt: now,
        cancelRequestedPhase: 'downloading',
        cancelAfterCommit: true);
    await store.commit(
        original,
        JobEvent(
            jobId: original.jobId,
            revision: 0,
            kind: 'fixture',
            at: now,
            snapshot: original.toJson()),
        expectedRevision: null);
    backend.present = true;
    backend.handle = 'new-handle';
    await File(backend.video.location.path).writeAsString('pa');
    connect();
    await engine.start();
    final done = await untilState(engine, original.jobId, JobState.cancelled);
    expect(done.checkpoint['handle'], 'new-handle');
    expect(done.receipt!.verification, VerificationLevel.verified);
    expect((done.receipt!.details['files'] as List).single,
        allOf(containsPair('actualSize', 2), containsPair('retained', true)));
    expect(backend.paused, true);
    expect(backend.additions, 0);
    expect(library.scans, isEmpty);
    expect((await store.events(done.jobId)).map((event) => event.kind),
        containsAllInOrder(['interrupted', 'effect_committed', 'cancelled']));
  });

  test('cancellation during file verification does not submit a new import',
      () async {
    backend.present = true;
    await backend.finish();
    final entered = Completer<void>(), release = Completer<void>();
    backend.onReadSize = (_) async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    final job = await add();
    await entered.future;
    await engine.cancel(job.jobId);
    release.complete();
    final done = await untilState(engine, job.jobId, JobState.cancelled);
    expect(library.scans, isEmpty);
    expect(done.receipt!.details['reason'], 'cancelled_before_import');
    expect(backend.paused, isTrue);
  });

  test(
      'cancel arriving before add returns records the effect that committed afterwards',
      () async {
    final release = Completer<void>();
    backend.addGate = release.future;
    final job = await add();
    await backend.addEntered.future;
    await engine.cancel(job.jobId);
    release.complete();
    final done = await untilState(engine, job.jobId, JobState.cancelled);
    expect(backend.present, isTrue);
    expect(backend.paused, isTrue);
    expect(
        done.toJson()['receipt'],
        containsPair(
            'cancellation',
            allOf(containsPair('afterCommit', false),
                containsPair('sideEffectCommitted', true))));
  });

  test(
      'legacy import registration prevents importing records the user later cleared',
      () async {
    backend.present = true;
    await backend.finish();
    library.importedKeys.add('$testHash|${root.path}');
    final job = await add();
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect(library.scans, isEmpty);
    expect((done.receipt!.details['files'] as List).single,
        containsPair('reason', 'previous_import_record_missing'));
  });

  test('remove keeps downloaded files while delete removes only its own files',
      () async {
    final job = await add();
    await phase(job.jobId, 'downloading');
    await File(backend.video.location.path).writeAsString('part');
    await downloads.remove(job.jobId);
    final removed = await untilState(engine, job.jobId, JobState.cancelled);
    expect(removed.receipt!.details['reason'], 'cancelled_incomplete');
    expect(await File(backend.video.location.path).exists(), isTrue);
    final second = await add();
    await phase(second.jobId, 'downloading');
    await File('${root.path}/other.mkv').writeAsString('other torrent');
    await downloads.remove(second.jobId, deleteData: true);
    expect(backend.deletions, 1);
    expect(await File(backend.video.location.path).exists(), isFalse);
    expect(await File('${root.path}/other.mkv').exists(), isTrue);
    backend.present = true;
    backend.paused = false;
    final classic = await downloads.adopt(backend, backend.snapshot);
    expect(classic.jobId, isNot(second.jobId));
    expect(harness.lookup('download.delete')!.spec.effect, Effect.destructive);
    expect(harness.lookup('download.remove')!.spec.effect, Effect.write);
  });

  test(
      'delete rejects lexical traversal and symlinks before calling the backend',
      () async {
    final external =
        await Directory.systemTemp.createTemp('external-download-');
    addTearDown(() => external.delete(recursive: true));
    final outside = File('${external.path}/keep.mkv');
    await outside.writeAsString('keep');
    backend.overrideFiles = [
      DownloadFile(
          location: DownloadLocation(path: outside.path, isLocal: true),
          expectedSize: 4,
          isVideo: true)
    ];
    final job = await add();
    await phase(job.jobId, 'downloading');
    await expectLater(
        downloads.remove(job.jobId, deleteData: true), throwsA(isA<Failure>()));
    expect(backend.deletions, 0);
    await Link('${root.path}/escape').create(external.path);
    backend.overrideFiles = [
      DownloadFile(
          location: DownloadLocation(
              path: '${root.path}/escape/keep.mkv', isLocal: true),
          expectedSize: 4,
          isVideo: true)
    ];
    await expectLater(
        downloads.remove(job.jobId, deleteData: true), throwsA(isA<Failure>()));
    expect(backend.deletions, 0);
    expect(await outside.readAsString(), 'keep');
    expect(backend.present, isTrue);
  });

  test(
      'remote files are verified through their backend and await transfer before local import',
      () async {
    await engine.close();
    backend = FakeDownloadBackend(root,
        reference:
            const DownloadBackendRef(kind: 'qbittorrent', id: 'seedbox'));
    backend.local = false;
    backend.present = true;
    await backend.finish();
    connect();
    await engine.start();
    final job = await downloads.add(testRequest, backend: backend.reference);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect(done.toJson()['backend'], {'kind': 'qbittorrent', 'id': 'seedbox'});
    expect((done.receipt!.details['files'] as List).single,
        containsPair('reason', 'requires_transfer'));
    expect(library.scans, isEmpty);
    expect(done.toJson().toString(), isNot(contains('credential:')));
  });

  test(
      'offline backends persist a retry without claiming completion or re-adding',
      () async {
    backend.online = false;
    final job = await downloads.add(testRequest);
    final retry = await untilState(engine, job.jobId, JobState.waitingRetry);
    expect(retry.error!.code, FailureCode.unavailable);
    expect(retry.receipt, isNull);
    expect(backend.additions, 0);
    backend.online = true;
    backend.present = true;
    await backend.finish();
    await downloads.pause(job.jobId);
    await downloads.resume(job.jobId);
    await untilState(engine, job.jobId, JobState.succeeded);
    expect(backend.additions, 0);
  });
}
