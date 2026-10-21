import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/download_capability.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_executor.dart';
import 'package:nipaplay/next/downloads/download_service.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/next/tasks/user_consent.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';

void main() {
  late Directory root;
  late FakeDownloadBackend backend;
  late FakeDownloadLibrary library;
  late DownloadExecutor executor;
  late TaskEngine engine;
  late DownloadService downloads;
  late Harness harness;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-remove-receipt-');
    backend = FakeDownloadBackend(root);
    library = FakeDownloadLibrary()..identify = false;
    final backends = DownloadBackends([backend]);
    executor = DownloadExecutor(
        backends: backends,
        library: library,
        isEnabled: () async => true,
        pollInterval: const Duration(milliseconds: 10));
    final guard = DiskDeletion(prompt: (title, message, stopped) async => true);
    engine = TaskEngine(
        store: MemoryJobStore(),
        ownerDeviceId: 'device-test',
        executors: [executor, guard]);
    executor.engine = engine;
    guard.engine = engine;
    downloads = DownloadService(
        engine: engine,
        executor: executor,
        backends: backends,
        library: library);
    harness = Harness([
      TaskCapability(engine),
      ...guard.protect([
        DownloadCapability(
            downloads: downloads,
            sources: DownloadSources(Directory('${root.path}/metadata')))
      ])
    ]);
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

  Future<Job> terminal(String id) async {
    var job = await engine.get(id);
    while (!job.state.isTerminal) {
      job = await engine.wait(id, afterRevision: job.revision);
    }
    return job;
  }

  Future<Job> finished() async {
    await backend.finish();
    backend.present = true;
    final job = await downloads.add(testRequest);
    final done = await terminal(job.jobId);
    expect(done.state, JobState.succeeded);
    final file = (done.receipt!.details['files'] as List).single as Map;
    expect(file['actualSize'], 4);
    expect(file['local'], true);
    return done;
  }

  Map fileOf(Job job) => (job.receipt!.details['files'] as List).single as Map;

  /// Invokes an Action; a consent question is answered by its own option and
  /// the resulting job is waited for.
  Future<JsonMap> invoke(String id, JsonMap input) async {
    var outcome =
        await harness.invokeJson(id, input, Invocation(origin: 'mcp'));
    if (outcome is NeedsDecision) {
      final option = outcome.decision.options.single.call;
      outcome = await harness.invokeJson(
          option.actionId, option.input, Invocation(origin: 'mcp'));
      expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
      final jobId =
          ((outcome as Completed).value.toJson()['job'] as Map)['jobId']
              as String;
      await terminal(jobId);
      return {'job': (await engine.get(jobId)).toJson()};
    }
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    return (outcome as Completed).value.toJson();
  }

  test('deleting a finished download amends its record', () async {
    final done = await finished();
    library.media[backend.video.location.path] = {'fileId': 'f'};
    await invoke('download.delete', {'jobId': done.jobId});
    expect(await File(backend.video.location.path).exists(), isFalse);
    final read = await engine.get(done.jobId);
    expect(read.state, JobState.succeeded);
    expect(read.revision, greaterThan(done.revision));
    final details = read.receipt!.details;
    expect(read.receipt!.verification, done.receipt!.verification);
    expect(details['sessionPresent'], false);
    expect(details['dataDeleted'], true);
    expect(DateTime.parse(details['removedAt'] as String).isUtc, isTrue);
    expect(details['infoHash'], testHash);
    final file = fileOf(read);
    expect(file['actualSize'], isNull);
    expect(file['retained'], false);
    expect(file['imported'], true);
    expect(file.containsKey('canonicalPath'), isFalse);
    // The readers see the same record.
    final viaRead = await invoke('download.read', {'jobId': done.jobId});
    expect(
        (((viaRead['job'] as Map)['receipt'] as Map)['details']
            as Map)['sessionPresent'],
        false);
    final listed = (await engine.list(type: 'download')).single;
    expect(listed.toJson(), read.toJson());
  });

  test('the value the service returns is the amended record', () async {
    final done = await finished();
    final job = await downloads.remove(done.jobId, deleteData: true);
    expect(job.receipt!.details['sessionPresent'], false);
    expect(job.receipt!.details['dataDeleted'], true);
    expect(fileOf(job)['retained'], false);
    expect(job.toJson(), (await engine.get(done.jobId)).toJson());
  });

  test('removing but keeping the files says they are retained', () async {
    final done = await finished();
    final job = await downloads.remove(done.jobId);
    expect(job.state, JobState.succeeded);
    expect(job.receipt!.details['sessionPresent'], false);
    expect(job.receipt!.details['dataDeleted'], false);
    expect(fileOf(job)['retained'], true);
    expect(fileOf(job)['actualSize'], 4);
    expect(await File(backend.video.location.path).exists(), isTrue);
  });

  test('removing a running download is still recorded by the executor',
      () async {
    backend.present = true;
    backend.finished = false;
    final job = await downloads.add(testRequest);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!(await engine.get(job.jobId)).sideEffectCommitted) {
      expect(DateTime.now().isBefore(deadline), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final removed = await downloads.remove(job.jobId);
    expect(removed.state, JobState.cancelled);
    expect(removed.receipt!.details['reason'], 'cancelled_incomplete');
    expect(removed.revision, (await engine.get(job.jobId)).revision);
    expect(removed.receipt!.details.containsKey('removedAt'), isFalse);
    expect(removed.receipt!.details.containsKey('dataDeleted'), isFalse);
  });

  test('a finished download whose session is already gone is left alone',
      () async {
    final done = await finished();
    backend.present = false;
    final job = await downloads.remove(done.jobId);
    expect(job.toJson(), done.toJson());
  });

  test('adding the same magnet after a delete starts a new job', () async {
    final done = await finished();
    // While the session lives, the old record is returned.
    expect((await downloads.add(testRequest)).jobId, done.jobId);
    await downloads.remove(done.jobId, deleteData: true);
    final again = await downloads.add(testRequest);
    expect(again.jobId, isNot(done.jobId));
    expect(again.state.isTerminal, isFalse);
    expect(again.receipt, isNull);
    await engine.cancel(again.jobId);
  });

  test('an ended download whose session vanished outside Next is amended once',
      () async {
    final done = await finished();
    final present = await backend.list();
    // The session is there: nothing changes.
    await downloads.observeMissingSessions(backend, present);
    expect((await engine.get(done.jobId)).toJson(), done.toJson());
    // Classic removed it, keeping the data.
    backend.present = false;
    library.media[backend.video.location.path] = {'fileId': 'f'};
    await downloads.observeMissingSessions(backend, const []);
    final read = await engine.get(done.jobId);
    expect(read.state, JobState.succeeded);
    final details = read.receipt!.details;
    expect(details['sessionPresent'], false);
    expect(DateTime.parse(details['removedAt'] as String).isUtc, isTrue);
    expect(details['observedMissingAt'], details['removedAt']);
    expect(details.containsKey('dataDeleted'), isFalse);
    expect(details['infoHash'], testHash);
    expect(read.receipt!.verification, done.receipt!.verification);
    expect(fileOf(read)['retained'], true);
    expect(fileOf(read)['actualSize'], 4);
    expect(fileOf(read)['imported'], true);
    // Seen again: not amended twice.
    await downloads.observeMissingSessions(backend, const []);
    expect((await engine.get(done.jobId)).toJson(), read.toJson());
  });

  test('the data deleted elsewhere shows in the re-read files', () async {
    final done = await finished();
    backend.present = false;
    await File(backend.video.location.path).delete();
    await downloads.observeMissingSessions(backend, const []);
    final read = await engine.get(done.jobId);
    expect(read.receipt!.details['sessionPresent'], false);
    expect(fileOf(read)['retained'], false);
    expect(fileOf(read)['actualSize'], isNull);
  });

  test('a listing older than a re-add does not amend a live session',
      () async {
    final done = await finished();
    // The caller's listing is empty, but the backend has the session now.
    await downloads.observeMissingSessions(backend, const []);
    expect((await engine.get(done.jobId)).toJson(), done.toJson());
  });

  test('a job that never had a session and running jobs are left alone',
      () async {
    backend.present = true;
    backend.finished = false;
    final running = await downloads.add(testRequest);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!(await engine.get(running.jobId)).sideEffectCommitted) {
      expect(DateTime.now().isBefore(deadline), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    backend.present = false;
    await downloads.observeMissingSessions(backend, const []);
    final read = await engine.get(running.jobId);
    expect(read.receipt?.details.containsKey('sessionPresent') ?? false,
        isFalse);
    await engine.cancel(running.jobId);
  });

  test('the same hash back in the session is a new job, not the old record',
      () async {
    final done = await finished();
    backend.present = false;
    await downloads.observeMissingSessions(backend, const []);
    backend.present = true;
    final back = await downloads.adopt(backend, backend.snapshot);
    expect(back.jobId, isNot(done.jobId));
    await engine.cancel(back.jobId);
  });
}
