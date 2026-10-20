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
  late DiskDeletion guard;
  late Harness harness;
  late List<String> paths;
  final asked = <String>[];
  Future<bool> Function() answer = () async => true;

  setUp(() async {
    sqfliteFfiInit();
    asked.clear();
    answer = () async => true;
    root = await Directory.systemTemp.createTemp('next-delete-files-');
    backend = FakeDownloadBackend(root)..present = true;
    library = FakeDownloadLibrary()..identify = false;
    paths = [
      for (final name in ['a.mkv', 'b.mkv', 'c.mkv'])
        (File('${root.path}/$name')..writeAsBytesSync([1, 2, 3, 4])).path
    ];
    backend.overrideFiles = [
      for (final path in paths)
        DownloadFile(
            location: DownloadLocation(path: path, isLocal: true),
            expectedSize: 4,
            completedBytes: 4,
            isVideo: true)
    ];
    // Only the first file is finished: the download is still running.
    final backends = DownloadBackends([backend]);
    executor = DownloadExecutor(
        backends: backends,
        library: library,
        isEnabled: () async => true,
        pollInterval: const Duration(milliseconds: 10));
    guard = DiskDeletion(prompt: (title, message, stopped) {
      asked.add(message);
      return answer();
    });
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

  /// A download that is still going: two of its files are done, the third
  /// is not.
  Future<Job> running() async {
    backend.overrideFiles = [
      for (final entry in paths.indexed)
        DownloadFile(
            location: DownloadLocation(path: entry.$2, isLocal: true),
            expectedSize: 4,
            completedBytes: entry.$1 == 2 ? 0 : 4,
            isVideo: true)
    ];
    backend.finished = false;
    final job = await downloads.add(testRequest);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (true) {
      final now = await engine.get(job.jobId);
      if (now.state == JobState.running && now.sideEffectCommitted) return now;
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Download did not start: ${now.toJson()}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<Job> terminal(String id) async {
    var job = await engine.get(id);
    while (!job.state.isTerminal) {
      job = await engine.wait(id, afterRevision: job.revision);
    }
    return job;
  }

  Future<NeedsDecision> preview(JsonMap input) async {
    final outcome =
        await harness.invokeJson('download.delete', input, Invocation(origin: 'mcp'));
    expect(outcome, isA<NeedsDecision>(), reason: '${outcome.toEnvelope()}');
    return outcome as NeedsDecision;
  }

  Future<Job> request(NeedsDecision decision) async {
    final option = decision.decision.options.single.call;
    final outcome = await harness.invokeJson(
        option.actionId, option.input, Invocation(origin: 'mcp'));
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    final id = ((outcome as Completed).value.toJson()['job'] as Map)['jobId']
        as String;
    return terminal(id);
  }

  Future<JsonMap> read(String jobId) async {
    final outcome = await harness.invokeJson(
        'download.read', {'jobId': jobId}, Invocation(origin: 'mcp'));
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    return (outcome as Completed).value.toJson();
  }

  test('the preview and the question list only the chosen files', () async {
    final job = await running();
    final decision = await preview({'jobId': job.jobId, 'fileIndices': [0]});
    expect(decision.decision.prompt, startsWith('删除这个下载里的这些文件：'));
    expect(decision.decision.prompt, contains('a.mkv'));
    expect(decision.decision.prompt, isNot(contains('b.mkv')));
    expect(decision.decision.prompt, isNot(contains('c.mkv')));
    expect(backend.fileDeletions, isEmpty);
    await request(decision);
    expect(asked.single, contains('a.mkv'));
    expect(asked.single, isNot(contains('b.mkv')));
    expect(asked.single, contains('这个下载里的这个文件'));
    expect(asked.single, contains('其他文件不动'));
  });

  test('a refusal deletes nothing and leaves the selection', () async {
    final job = await running();
    answer = () async => false;
    final done = await request(
        await preview({'jobId': job.jobId, 'fileIndices': [0, 1]}));
    expect(done.state, JobState.failed);
    expect(done.error!.message, '用户没有同意删除');
    expect(backend.fileDeletions, isEmpty);
    for (final path in paths) {
      expect(await File(path).exists(), isTrue);
    }
    final task = (await read(job.jobId))['task'] as Map;
    expect((task['files'] as List).map((f) => (f as Map)['included']),
        [true, true, true]);
  });

  test('approval deletes only those files; the rest goes on', () async {
    final job = await running();
    final done = await request(
        await preview({'jobId': job.jobId, 'fileIndices': [0]}));
    expect(done.state, JobState.succeeded);
    expect(done.receipt!.verification, VerificationLevel.verified);
    expect(backend.fileDeletions, [
      [0]
    ]);
    expect(backend.deletions, 0);
    expect(await File(paths[0]).exists(), isFalse);
    expect(await File(paths[1]).exists(), isTrue);
    expect(await File(paths[2]).exists(), isTrue);
    // The receipt says which files went.
    final result = (done.receipt!.details['result'] as Map);
    expect((result['deletedFiles'] as List).single,
        {'index': 0, 'path': paths[0]});
    // The readback: unselected, data gone; the others unchanged.
    final read1 = await read(job.jobId);
    final files = ((read1['task'] as Map)['files'] as List).cast<Map>();
    expect(files.map((f) => f['included']), [false, true, true]);
    expect(files[0]['actualSize'], isNull);
    expect(files[0]['playable'], false);
    expect(files[1]['actualSize'], 4);
    // The download itself goes on, not paused.
    final after = await engine.get(job.jobId);
    expect(after.state.isTerminal, isFalse);
    expect(backend.paused, isFalse);
  });

  test('a finished download keeps seeding the remaining files', () async {
    backend.finished = true;
    final job = await downloads.add(testRequest);
    final end = await terminal(job.jobId);
    expect(end.state, JobState.succeeded);
    final replacements = (await engine.list(type: 'download')).length;
    final done = await request(
        await preview({'jobId': job.jobId, 'fileIndices': [1, 2]}));
    expect(done.state, JobState.succeeded);
    expect(await File(paths[0]).exists(), isTrue);
    expect(await File(paths[1]).exists(), isFalse);
    expect(await File(paths[2]).exists(), isFalse);
    final files = (((await read(job.jobId))['task'] as Map)['files'] as List)
        .cast<Map>();
    expect(files.map((f) => f['included']), [true, false, false]);
    expect(backend.paused, isFalse);
    // No new observation job: the selection only shrank.
    expect((await engine.list(type: 'download')).length, replacements);
  });

  test('files changed after the preview are refused', () async {
    final job = await running();
    // Changed before the request: the single-use preview is stale.
    final decision =
        await preview({'jobId': job.jobId, 'fileIndices': [0]});
    await downloads.selectFiles(job.jobId, [1, 2]);
    final option = decision.decision.options.single.call;
    expect(
        await harness.invokeJson(
            option.actionId, option.input, Invocation(origin: 'mcp')),
        isA<Failed>());
    // Changed while the question is open.
    await downloads.selectFiles(job.jobId, [0, 1, 2]);
    final second = await preview({'jobId': job.jobId, 'fileIndices': [0]});
    answer = () async {
      await downloads.selectFiles(job.jobId, [1, 2]);
      return true;
    };
    final done = await request(second);
    expect(done.state, JobState.failed);
    expect(done.error!.code, FailureCode.conflict);
    expect(backend.fileDeletions, isEmpty);
    expect(await File(paths[0]).exists(), isTrue);
  });

  test('paths outside the output directory are refused', () async {
    final job = await running();
    final outside =
        await Directory.systemTemp.createTemp('next-delete-outside-');
    addTearDown(() => outside.delete(recursive: true));
    final keep = await File('${outside.path}/keep.mkv').writeAsString('keep');
    backend.overrideFiles = [
      backend.overrideFiles![0],
      DownloadFile(
          location: DownloadLocation(path: keep.path, isLocal: true),
          expectedSize: 4,
          completedBytes: 4,
          isVideo: true),
      backend.overrideFiles![2],
    ];
    final outcome = await harness.invokeJson(
        'download.delete',
        {'jobId': job.jobId, 'fileIndices': [1]},
        Invocation(origin: 'mcp'));
    expect(outcome, isA<Failed>());
    expect((outcome as Failed).failure.code, FailureCode.invalidInput);
    await expectLater(
        downloads.deleteFiles(job.jobId, [1]), throwsA(isA<Failure>()));
    expect(await keep.exists(), isTrue);
    expect(backend.fileDeletions, isEmpty);
    expect(asked, isEmpty);
  });

  test('indices must exist, be unique and belong to one download', () async {
    final job = await running();
    for (final input in [
      {'jobId': job.jobId, 'fileIndices': [9]},
      {'jobId': job.jobId, 'fileIndices': [0, 0]},
      {'jobId': job.jobId, 'fileIndices': <int>[]},
      {'jobId': job.jobId, 'fileIndices': [-1]},
      {'jobIds': [job.jobId], 'fileIndices': [0]},
    ]) {
      expect(
          await harness.invokeJson(
              'download.delete', input, Invocation(origin: 'mcp')),
          isA<Failed>(),
          reason: '$input');
    }
    expect(asked, isEmpty);
    expect(backend.fileDeletions, isEmpty);
  });

  test('deleting a whole download behaves as before', () async {
    final job = await running();
    final decision = await preview({'jobId': job.jobId});
    expect(decision.decision.prompt, startsWith('删除这些下载文件：'));
    final done = await request(decision);
    expect(done.state, JobState.succeeded);
    expect(backend.deletions, 1);
    expect(backend.fileDeletions, isEmpty);
    expect(asked.single, startsWith('将删除这些下载的文件，无法恢复：'));
    expect(asked.single, isNot(contains('其他文件不动')));
    for (final path in paths) {
      expect(await File(path).exists(), isFalse);
    }
  });

  test('the words say which files of the download go', () {
    final preview = {
      'downloads': [
        {
          'partial': true,
          'files': [
            for (final name in ['1.mkv', '2.mkv', '3.mkv', '4.mkv', '5.mkv'])
              {'path': '/d/$name', 'included': false, 'expectedSize': 1 << 30}
          ]
        }
      ]
    };
    final words = downloadDeletionWords(preview);
    expect(words, startsWith('将删除这个下载里的这几个文件，无法恢复：'));
    expect(words, contains('· 1.mkv'));
    expect(words, contains('· 还有 2 个文件'));
    expect(words, contains('共约 5.0 GB'));
    expect(words, endsWith('下载里的其他文件不动。'));
  });
}
