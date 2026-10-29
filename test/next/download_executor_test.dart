import 'dart:async';
import 'dart:convert';
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

  void connect(
      {List<DownloadBackend> additional = const [],
      Duration retryDelay = const Duration(minutes: 1),
      Duration stallAfter = const Duration(minutes: 5)}) {
    final backends = DownloadBackends([backend, ...additional]);
    executor = DownloadExecutor(
        backends: backends,
        library: library,
        isEnabled: () async => true,
        pollInterval: const Duration(milliseconds: 10),
        importRetryDelay: retryDelay,
        stallAfter: stallAfter);
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
          deleteAudit: JsonlJournal(File('${root.path}/download-audit.jsonl')),
          sources: DownloadSources(Directory('${root.path}/metadata')))
    ]);
  }

  Future<JsonMap> call(String action, JsonMap input) async {
    final outcome = await harness.invokeJson(
        action, input, Invocation(origin: 'mcp', id: 'batch-test'));
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    final result = (outcome as Completed).value.toJson();
    expect(harness.lookup(action)!.spec.output.validate(result), isEmpty);
    return result;
  }

  test('unsupported bandwidth control never initializes or mutates downloads',
      () async {
    final initializations = backend.initializations;
    final status = await call('download.limits.get', {});
    expect(status['supported'], false);
    expect(status['applied'], false);
    final changed = await call('download.limits.set', {
      'downloadBytesPerSecond': 131072,
      'uploadBytesPerSecond': 65536
    });
    expect(changed['supported'], false);
    expect(backend.initializations, initializations);
    final invalid = await harness.invokeJson('download.limits.set', {
      'downloadBytesPerSecond': 131072,
      'uploadBytesPerSecond': 10
    }, Invocation(origin: 'test'));
    expect(invalid, isA<Failed>());
    expect(backend.initializations, initializations);
    expect(backend.additions, 0);
  });

  test(
      'scanner acknowledgement does not fabricate media or block download success',
      () async {
    backend.present = true;
    await backend.finish();
    library.acknowledgeOnly = true;
    final job = await downloads.add(testRequest);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect(done.receipt!.verification, VerificationLevel.verified);
    expect(
        (done.receipt!.details['files'] as List).single,
        allOf(
            containsPair('imported', false),
            containsPair('reason', 'not_identified'),
            containsPair('identificationPending', true),
            isNot(contains('media'))));
    expect(library.importedKeys, contains(backend.snapshot.importKey));
  });

  test(
      'selection readback preserves hash identity, paths and prior completion evidence',
      () async {
    final job = await downloads.add(testRequest);
    await backend.addEntered.future;
    while (!backend.present) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final changed = await call(
        'download.select_files', {'jobId': job.jobId, 'fileIndices': []});
    expect((changed['job'] as Map)['jobId'], job.jobId);
    expect(
        ((changed['task'] as Map)['files'] as List).single['included'], false);
    expect((await downloads.add(testRequest)).jobId, job.jobId);
    await expectLater(
        downloads.selectFiles(job.jobId, [9]), throwsA(isA<Failure>()));
    expect((await downloads.snapshot(job.jobId))!.files.single.location.path,
        backend.video.location.path);
    await engine.cancel(job.jobId);
  });

  test('a checked first file is persisted while the parent remains incomplete',
      () async {
    backend.present = true;
    final first = File('${root.path}/first.mp4');
    await first.writeAsString('data');
    backend.overrideFiles = [
      DownloadFile(
          location: DownloadLocation(path: first.path, isLocal: true),
          expectedSize: 4,
          completedBytes: 4,
          isVideo: true),
      DownloadFile(
          location:
              DownloadLocation(path: '${root.path}/second.mp4', isLocal: true),
          expectedSize: 4,
          completedBytes: 0,
          isVideo: true),
    ];
    final job = await downloads.add(testRequest);
    Job current;
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    do {
      current = await engine.get(job.jobId);
      if (current.checkpoint['completedFiles'] == null ||
          (current.checkpoint['completedFiles'] as List).isEmpty) {
        expect(current.state.isTerminal, false,
            reason: jsonEncode(current.toJson()));
        expect(DateTime.now().isBefore(deadline), true,
            reason: jsonEncode(current.toJson()));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      } else {
        break;
      }
    } while (true);
    expect(current.state.isTerminal, false);
    final row = (current.checkpoint['completedFiles'] as List).single as Map;
    expect(row['verification'], 'verified');
    expect(row['index'], 0);
    expect(row['actualSize'], 4);
    expect(library.scans, [
      [first.path]
    ]);
    await downloads.pause(job.jobId);
    expect((await engine.get(job.jobId)).checkpoint['completedFiles'], [row]);
    await downloads.resume(job.jobId);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(library.scans, [
      [first.path]
    ]);
    expect((await engine.get(job.jobId)).checkpoint['completedFiles'], [row]);
    await engine.cancel(job.jobId);
  });

  test('a stretch without progress is recorded once and closes on a new byte',
      () async {
    Future<List<Map>> stallsOnce(String jobId, bool Function(List<Map>) done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (true) {
        final job = await engine.get(jobId);
        final stalls = (job.checkpoint['stalls'] as List? ?? []).cast<Map>();
        if (done(stalls)) return stalls;
        expect(DateTime.now().isBefore(deadline), true,
            reason: jsonEncode(job.toJson()));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    backend.present = true;
    final before = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    backend.health = {
      'secondsWithoutProgress': 120,
      'lastProgressAt': null,
      'connectedPeers': 0,
      'seenPeers': 12,
      'deadPeers': 12
    };
    final job = await downloads.add(testRequest);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect((await engine.get(job.jobId)).checkpoint['stalls'], isNull);
    backend.health = {...backend.health!, 'secondsWithoutProgress': 360};
    var stalls = await stallsOnce(job.jobId, (s) => s.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    stalls = await stallsOnce(job.jobId, (s) => true);
    expect(stalls, hasLength(1));
    expect(stalls.single['index'], 0);
    expect(stalls.single['seenPeers'], 12);
    expect(stalls.single['connectedPeers'], 0);
    expect(stalls.single['resumedAt'], isNull);
    // A restart resets the counter without a byte: still the same stall.
    backend.health = {...backend.health!, 'secondsWithoutProgress': 5};
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect((await stallsOnce(job.jobId, (s) => true)).single['resumedAt'],
        isNull);
    // After the recorded stall, not after the clock now: on a slow machine
    // more than a second can pass between the two.
    final moved = DateTime.parse(stalls.single['at'] as String)
        .add(const Duration(seconds: 1));
    backend.health = {
      ...backend.health!,
      'secondsWithoutProgress': 0,
      'lastProgressAt': moved.toIso8601String()
    };
    stalls = await stallsOnce(
        job.jobId, (s) => s.isNotEmpty && s.last['resumedAt'] != null);
    expect(stalls.single['resumedAt'], moved.toIso8601String());
    backend.health = {...backend.health!, 'secondsWithoutProgress': 400};
    stalls = await stallsOnce(job.jobId, (s) => s.length == 2);
    expect(stalls.last['index'], 1);
    expect(before.isBefore(DateTime.parse(stalls.last['at'] as String)), true);
    await engine.cancel(job.jobId);
  });

  test('no metadata for the stall time is a stall that closes with it',
      () async {
    const stallAfter = Duration(seconds: 1);
    await engine.close();
    connect(
        retryDelay: const Duration(milliseconds: 40),
        stallAfter: stallAfter);
    await engine.start();
    Future<List<Map>> stallsOnce(
        String jobId, bool Function(List<Map>) done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (true) {
        final job = await engine.get(jobId);
        final stalls = (job.checkpoint['stalls'] as List? ?? []).cast<Map>();
        if (done(stalls)) return stalls;
        expect(DateTime.now().isBefore(deadline), true,
            reason: jsonEncode(job.toJson()));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    backend.addError = const Failure(
        FailureCode.unavailable, '磁力链接解析超时',
        retryable: true);
    final job = await downloads.add(testRequest);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // No stall may be recorded before the job is stallAfter old. The age is
    // taken after the read, so it bounds every attempt the read could have
    // seen; on a machine so slow that the pause outlasted stallAfter there
    // is nothing left to assert here.
    final early = await engine.get(job.jobId);
    final age = DateTime.now().toUtc().difference(early.createdAt);
    if (age < stallAfter) expect(early.checkpoint['stalls'], isNull);
    var stalls = await stallsOnce(job.jobId, (s) => s.isNotEmpty);
    final first = stalls.single;
    expect(first['index'], 0);
    expect(first['metadata'], false);
    expect(first['completedBytes'], 0);
    expect(first['totalBytes'], isNull);
    expect(first['seenPeers'], isNull);
    expect(first['connectedPeers'], isNull);
    expect(first['deadPeers'], isNull);
    expect(first['secondsWithoutProgress'], isA<int>());
    expect((first['error'] as Map)['code'], 'unavailable');
    expect(first['resumedAt'], isNull);
    // More failed attempts neither add nor rewrite the stretch.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    stalls = await stallsOnce(job.jobId, (s) => true);
    expect(stalls, [first]);
    // Still retrying the add, not failed: with a 40 ms retry delay the job is
    // caught waiting for the retry or in the attempt itself.
    expect(
        const {JobState.waitingRetry, JobState.interrupted, JobState.running}
            .contains((await engine.get(job.jobId)).state),
        isTrue);
    // Metadata arrives: the stretch closes and stays in the checkpoint.
    backend.addError = null;
    backend.health = {
      'secondsWithoutProgress': 0,
      'lastProgressAt': null,
      'connectedPeers': 1,
      'seenPeers': 1,
      'deadPeers': 0
    };
    stalls = await stallsOnce(
        job.jobId, (s) => s.isNotEmpty && s.last['resumedAt'] != null);
    expect(stalls, hasLength(1));
    expect(stalls.single['at'], first['at']);
    expect((await engine.get(job.jobId)).checkpoint['handle'], isNotNull);
    // A real byte stall is still a new stretch.
    backend.health = {...backend.health!, 'secondsWithoutProgress': 400};
    stalls = await stallsOnce(job.jobId, (s) => s.length == 2);
    expect(stalls.last['index'], 1);
    expect(stalls.last.containsKey('metadata'), false);
    expect(stalls.first['resumedAt'], isNotNull);
    await engine.cancel(job.jobId);
  });

  test('readding a removed success creates a new job and amends the old receipt',
      () async {
    backend.present = true;
    await backend.finish();
    library.autoImport = false;
    final original = await downloads.add(testRequest);
    final done = await untilState(engine, original.jobId, JobState.succeeded);
    final receipt = jsonEncode(done.receipt!.toJson());
    expect((await downloads.add(testRequest)).jobId, original.jobId);
    await downloads.remove(original.jobId);
    final replacement = await downloads.add(testRequest);
    expect(replacement.jobId, isNot(original.jobId));
    // The old receipt stays, now saying the session is gone.
    final kept = (await engine.get(original.jobId)).receipt!;
    expect(kept.verification, done.receipt!.verification);
    expect(kept.details['infoHash'], done.receipt!.details['infoHash']);
    expect(kept.details['sessionPresent'], false);
    expect(receipt, isNot(jsonEncode(kept.toJson())));
    expect((await engine.list(type: 'download')).map((j) => j.jobId),
        containsAll([original.jobId, replacement.jobId]));
  });

  test(
      'directory overrides survive persistence and duplicate adds do not move data',
      () async {
    await engine.close();
    connect();
    final result = await call('download.add', {
      'source': testRequest.source,
      'downloadDirectory': '${root.path}/chosen',
      'createFolderForTask': false,
    });
    final first = await engine.get((result['job'] as Map)['jobId'] as String);
    expect(first.input['downloadDirectory'], '${root.path}/chosen');
    expect(first.input['createFolderForTask'], false);
    final duplicate = await call('download.add', {
      'source': testRequest.source,
      'downloadDirectory': '${root.path}/other',
    });
    expect((duplicate['job'] as Map)['jobId'], first.jobId);
    expect((await engine.get(first.jobId)).input, first.input);
    final invalid = await harness.invokeJson(
        'download.add',
        {
          'source': 'magnet:?xt=urn:btih:${'1' * 40}',
          'downloadDirectory': 'relative',
        },
        Invocation(origin: 'test'));
    expect(invalid, isA<Failed>());
    expect(await engine.list(), hasLength(1));
  });

  test(
      'explicit completed scan preserves receipts and does not invent imported identity',
      () async {
    backend.present = true;
    await backend.finish();
    library.autoImport = false;
    library.acknowledgeOnly = true;
    final job = await downloads.add(testRequest);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    final receipt = jsonEncode(done.receipt!.toJson());
    final result = await call('download.import', {'jobId': job.jobId});
    final file = ((result['task'] as Map)['files'] as List).single as Map;
    expect(file['imported'], false);
    expect(file['identificationPending'], true);
    expect(file.containsKey('media'), false);
    expect(
        jsonEncode((await engine.get(job.jobId)).receipt!.toJson()), receipt);
    expect(library.importedKeys, contains(backend.snapshot.importKey));
    await File(backend.video.location.path).writeAsString('short');
    final scans = library.scans.length;
    final corrupt = await harness.invokeJson(
        'download.import', {'jobId': job.jobId}, Invocation(origin: 'test'));
    expect(corrupt, isA<Failed>());
    expect(library.scans.length, scans);
    expect(
        jsonEncode((await engine.get(job.jobId)).receipt!.toJson()), receipt);
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

  test(
      'registered unidentified entries succeed and await separate identification',
      () async {
    backend.present = true;
    await backend.finish();
    library.media[backend.video.location.path] = {
      'path': backend.video.location.path,
      'identificationPending': true
    };
    final job = await downloads.add(testRequest);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect(
        (done.receipt!.details['files'] as List).single,
        allOf(
            containsPair('imported', true),
            containsPair('identificationPending', true),
            containsPair('reason', 'not_identified'),
            contains('media')));
    expect(library.scans, isEmpty);
    expect(done.error, isNull);
  });

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

  Future<(FakeDownloadBackend, Job, Job)> twoDownloads() async {
    await engine.close();
    final otherRoot = await Directory('${root.path}/second').create();
    final other = FakeDownloadBackend(otherRoot,
        reference: const DownloadBackendRef(kind: 'fixture', id: 'second'));
    connect(additional: [other]);
    await engine.start();
    final first = await downloads.add(testRequest);
    final second = await downloads.add(testRequest, backend: other.reference);
    await phase(first.jobId, 'downloading');
    await phase(second.jobId, 'downloading');
    return (other, first, second);
  }

  test(
      'batch add accepts distinct sources, keeps failures local and preserves old source calls',
      () async {
    await engine.close();
    connect();
    final secondSource = 'magnet:?xt=urn:btih:${'1' * 40}';
    final results = (await call('download.add', {
      'sources': [testRequest.source, 'magnet:?xt=urn:btih:bad', secondSource],
    }))['results'] as List;
    expect(results.map((row) => (row as Map)['status']),
        ['completed', 'failed', 'completed']);
    final first = (results.first as Map)['job'] as Map;
    final second = (results.last as Map)['job'] as Map;
    expect(first['jobId'], isNot(second['jobId']));
    expect(first['state'], 'queued');
    expect(((results[1] as Map)['error'] as Map)['code'], 'invalid_input');
    final legacy = await call('download.add', {'source': testRequest.source});
    expect((legacy['job'] as Map)['jobId'], first['jobId']);
    expect(await engine.list(), hasLength(2));
  });

  test(
      'one call pauses and resumes multiple downloads, aliases and batch remove keep files',
      () async {
    final (other, first, second) = await twoDownloads();
    final ids = [first.jobId, 'missing', second.jobId];
    final paused = (await call('download.set_paused', {
      'jobIds': ids,
      'paused': true,
    }))['results'] as List;
    expect(paused.map((row) => (row as Map)['status']),
        ['completed', 'failed', 'completed']);
    expect(backend.paused, isTrue);
    expect(other.paused, isTrue);
    expect((paused.first as Map)['job'], containsPair('state', 'paused'));
    final resumed = (await call('download.set_paused', {
      'jobIds': ids,
      'paused': false,
    }))['results'] as List;
    expect(resumed.map((row) => (row as Map)['status']),
        ['completed', 'failed', 'completed']);
    expect(backend.paused, isFalse);
    expect(other.paused, isFalse);
    await phase(first.jobId, 'downloading');
    await phase(second.jobId, 'downloading');
    expect((await call('download.pause', {'jobId': first.jobId}))['job'],
        containsPair('state', 'paused'));
    await call('download.resume', {'jobId': first.jobId});
    expect(backend.paused, isFalse);
    await phase(first.jobId, 'downloading');
    await File(backend.video.location.path).writeAsString('part');
    await File(other.video.location.path).writeAsString('part');
    final removed =
        (await call('download.remove', {'jobIds': ids}))['results'] as List;
    expect(removed.map((row) => (row as Map)['status']),
        ['completed', 'failed', 'completed']);
    expect(backend.removals, 1);
    expect(other.removals, 1);
    expect(await File(backend.video.location.path).exists(), isTrue);
    expect(await File(other.video.location.path).exists(), isTrue);
  });

  test(
      'batch delete checks every item, continues after boundary failures and audits each attempt',
      () async {
    final (other, first, second) = await twoDownloads();
    final outsideRoot =
        await Directory.systemTemp.createTemp('batch-delete-outside-');
    addTearDown(() => outsideRoot.delete(recursive: true));
    final outside =
        await File('${outsideRoot.path}/keep.mkv').writeAsString('keep');
    backend.overrideFiles = [
      DownloadFile(
        location: DownloadLocation(path: outside.path, isLocal: true),
        expectedSize: 4,
        isVideo: true,
      )
    ];
    await File(other.video.location.path).writeAsString('part');
    final deleted = (await call('download.delete', {
      'jobIds': [first.jobId, 'missing', second.jobId],
    }))['results'] as List;
    expect(deleted.map((row) => (row as Map)['status']),
        ['failed', 'failed', 'completed']);
    expect(((deleted.first as Map)['error'] as Map)['code'], 'invalid_input');
    expect(backend.deletions, 0);
    expect(other.deletions, 1);
    expect(await outside.exists(), isTrue);
    expect(await File(other.video.location.path).exists(), isFalse);
    final auditFile = File('${root.path}/download-audit.jsonl');
    final audit = (await auditFile.readAsLines())
        .map((line) => jsonDecode(line) as Map)
        .toList();
    expect(audit, hasLength(3));
    expect(audit.map((row) => row['invocationId']),
        ['batch-test/0', 'batch-test/1', 'batch-test/2']);
    expect(
        audit.map((row) => row['status']), ['failed', 'failed', 'completed']);
    expect(audit.map((row) => row['effect']).toSet(), {'destructive'});
    expect(audit.map((row) => row['origin']).toSet(), {'mcp'});
    expect(audit.map((row) => (row['input'] as Map)['jobId']),
        [first.jobId, 'missing', second.jobId]);
    backend.overrideFiles = null;
    await File(backend.video.location.path).writeAsString('part');
    await call('download.delete', {'jobId': first.jobId});
    expect(backend.deletions, 1);
    expect(await auditFile.readAsLines(), hasLength(4));
    expect(harness.lookup('download.delete')!.spec.effect, Effect.destructive);
    expect(harness.lookup('download.remove')!.spec.effect, Effect.write);
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
      'download controls are idempotent through Actions for running and terminal jobs',
      () async {
    Future<Job> control(String action, String id) async {
      final outcome = await harness.invokeJson(
          'download.$action', {'jobId': id}, Invocation(origin: 'test'));
      expect(outcome, isA<Completed<JsonEncodable>>());
      return engine.get(id);
    }

    final job = await add();
    await phase(job.jobId, 'downloading');
    await control('resume', job.jobId);
    await control('resume', job.jobId);
    expect(backend.resumes, 0);
    await control('pause', job.jobId);
    final paused = await control('pause', job.jobId);
    expect(paused.state, JobState.paused);
    expect(backend.pauses, 1);
    await control('resume', job.jobId);
    await control('resume', job.jobId);
    expect(backend.resumes, 1);
    await backend.finish();
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    await control('resume', job.jobId);
    expect(backend.resumes, 1);
    await control('pause', job.jobId);
    await control('pause', job.jobId);
    expect(backend.pauses, 2);
    await control('resume', job.jobId);
    await control('resume', job.jobId);
    expect(backend.resumes, 2);
    expect((await engine.get(job.jobId)).toJson(), done.toJson());
    await control('remove', job.jobId);
    await control('remove', job.jobId);
    await control('delete', job.jobId);
    expect(backend.removals, 1);
    expect(backend.deletions, 0);
    final missing = await harness.invokeJson(
            'download.resume', {'jobId': job.jobId}, Invocation(origin: 'test'))
        as Failed;
    expect(missing.failure.code, FailureCode.notFound);
    for (final action in ['pause', 'resume', 'remove', 'delete']) {
      final outcome = await harness.invokeJson('download.$action',
          {'jobId': 'unknown'}, Invocation(origin: 'test')) as Failed;
      expect(outcome.failure.code, FailureCode.notFound);
    }
  });

  test(
      'resume retries a backend error instead of treating it as already running',
      () async {
    final job = await add();
    await phase(job.jobId, 'downloading');
    backend.error = 'peer connection failed';
    final outcome = await harness.invokeJson(
        'download.resume', {'jobId': job.jobId}, Invocation(origin: 'test'));
    expect(outcome, isA<Completed<JsonEncodable>>());
    expect(backend.resumes, 1);
    expect(backend.error, isNull);
  });

  test(
      'resume cannot restart a torrent while cancellation is still stopping it',
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
    final outcome = await harness.invokeJson(
            'download.resume', {'jobId': job.jobId}, Invocation(origin: 'test'))
        as Failed;
    expect(outcome.failure.code, FailureCode.conflict);
    expect(backend.resumes, 0);
    release.complete();
    await untilState(engine, job.jobId, JobState.cancelled);
  });

  test(
      'busy scanner retries, but unidentified files finish without recognition retries',
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
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect(
        (done.receipt!.details['files'] as List).single,
        allOf(
            containsPair('reason', 'not_identified'),
            containsPair('identificationPending', true),
            containsPair('actualSize', 4)));
    expect(done.error, isNull);
    expect(library.scans, hasLength(1));
    for (var observation = 0; observation < 3; observation++) {
      expect(
          (await downloads.adopt(backend, backend.snapshot)).jobId, job.jobId);
    }
    expect(library.scans, hasLength(1));
  });

  test('restoring a completed torrent does not adopt its recheck as a new job',
      () async {
    backend.present = true;
    await backend.finish();
    final job = await add();
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    backend
      ..handle = 'restored-handle'
      ..state = 'initializing'
      ..finished = false
      ..completed = 2;
    expect((await downloads.adopt(backend, backend.snapshot)).jobId, job.jobId);
    expect(await engine.list(type: 'download'), hasLength(1));
    backend
      ..state = 'live'
      ..finished = true
      ..completed = backend.total;
    expect((await downloads.adopt(backend, backend.snapshot)).jobId, job.jobId);
    expect((await engine.get(job.jobId)).toJson(), done.toJson());
    expect(backend.additions, 0);
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

  test('cancelling leaves files the engine never verified out of the library',
      () async {
    final job = await add();
    await phase(job.jobId, 'downloading');
    // The engine allocates every file at full size before any byte arrives.
    await File(backend.video.location.path)
        .writeAsBytes(List.filled(backend.total, 0));
    library.media[backend.video.location.path] = {'fileId': 'would-register'};
    await downloads.remove(job.jobId);
    final removed = await untilState(engine, job.jobId, JobState.cancelled);
    final file = (removed.receipt!.details['files'] as List).single as Map;
    expect(file['actualSize'], backend.total);
    expect(file['complete'], isFalse);
    expect(file['imported'], isFalse);
    expect(file['reason'], 'cancelled_incomplete');
    expect(library.lookups, isNot(contains(backend.video.location.path)));
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
