import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/download_capability.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_runtime.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FakeDownloadBackend backend;
  late FakeDownloadLibrary library;
  late DownloadRuntime runtime;
  late TaskEngine engine;
  late Harness harness;

  DownloadFile file(String name, {required bool done, bool video = true}) =>
      DownloadFile(
          location: DownloadLocation(path: '${root.path}/$name', isLocal: true),
          expectedSize: 4,
          completedBytes: done ? 4 : 0,
          isVideo: video);

  Future<void> complete(String name) =>
      File('${root.path}/$name').writeAsString('data');

  Future<JsonMap> wait(String jobId, {List<int>? known, int? seconds}) async {
    final outcome = await harness.invokeJson(
        'download.wait_files',
        {
          'jobId': jobId,
          if (known != null) 'known': known,
          if (seconds != null) 'waitSeconds': seconds,
        },
        Invocation(origin: 'test'));
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    return (outcome as Completed).value.toJson();
  }

  List<int> indices(JsonMap result) =>
      [for (final f in result['files'] as List) (f as Map)['index'] as int];

  Future<String> start(List<DownloadFile> files) async {
    backend.overrideFiles = files;
    final job = await runtime.downloads.add(testRequest);
    return job.jobId;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('download-wait-');
    SharedPreferences.setMockInitialValues({});
    StorageService.debugAppStorageDirectoryOverride = root;
    backend = FakeDownloadBackend(root)..present = true;
    library = FakeDownloadLibrary();
    runtime = DownloadRuntime(
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    engine = TaskEngine(
        store: MemoryJobStore(),
        ownerDeviceId: 'fixture',
        executors: [runtime.executor]);
    runtime.attach(engine, root);
    await engine.start();
    harness = Harness([
      DownloadCapability(
          downloads: runtime.downloads,
          sources: DownloadSources(Directory('${root.path}/metadata')))
    ]);
  });
  tearDown(() => StorageService.debugAppStorageDirectoryOverride = null);

  test('returns at once when a finished video is already registered',
      () async {
    await complete('a.mp4');
    final id =
        await start([file('a.mp4', done: true), file('b.mp4', done: false)]);
    final result = await wait(id, seconds: 30);
    expect(indices(result), [0]);
    expect(result['ended'], false);
    expect(result['timedOut'], false);
    expect(result['jobId'], id);
    expect((result['files'] as List).single['media'], isNotNull);
    await engine.cancel(id);
  });

  test('waits for the next file and skips known ones', () async {
    await complete('a.mp4');
    final id =
        await start([file('a.mp4', done: true), file('b.mp4', done: false)]);
    final pending = wait(id, known: [0], seconds: 30);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await complete('b.mp4');
    backend.overrideFiles = [
      file('a.mp4', done: true),
      file('b.mp4', done: true)
    ];
    final result = await pending;
    expect(indices(result), [1]);
    expect(result['timedOut'], false);
    await engine.cancel(id);
  });

  test('times out with no files', () async {
    await complete('a.mp4');
    final id =
        await start([file('a.mp4', done: true), file('b.mp4', done: false)]);
    final result = await wait(id, known: [0], seconds: 1);
    expect(result['files'], isEmpty);
    expect(result['timedOut'], true);
    expect(result['ended'], false);
    await engine.cancel(id);
  });

  test('ignores files that are not videos or not registered', () async {
    await complete('a.mp4');
    await complete('b.txt');
    library.identify = false;
    final id = await start(
        [file('a.mp4', done: true), file('b.txt', done: true, video: false)]);
    final result = await wait(id, seconds: 1);
    expect(result['files'], isEmpty);
    expect(result['timedOut'], true);
    await engine.cancel(id);
  });

  test('returns the remaining files when the download has ended', () async {
    await complete('a.mp4');
    final id = await start([file('a.mp4', done: true)]);
    backend.finished = true;
    backend.completed = backend.total;
    await untilState(engine, id, JobState.succeeded);
    final result = await wait(id, seconds: 30);
    expect(result['ended'], true);
    expect(result['timedOut'], false);
    expect(result['state'], 'succeeded');
    expect(indices(result), [0]);
    final again = await wait(id, known: [0], seconds: 30);
    expect(again['files'], isEmpty);
    expect(again['ended'], true);
  });
}
