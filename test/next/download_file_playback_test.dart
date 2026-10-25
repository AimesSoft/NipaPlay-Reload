import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/capabilities/download_playback_capability.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_runtime.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';
import 'package:path/path.dart' as ppath;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'completed first file plays from disk without resuming a paused incomplete parent',
      () async {
    final root = await Directory.systemTemp.createTemp('download-play-');
    SharedPreferences.setMockInitialValues({});
    StorageService.debugAppStorageDirectoryOverride = root;
    addTearDown(() => StorageService.debugAppStorageDirectoryOverride = null);
    final output = await Directory(ppath.join(root.path, 'downloads')).create();
    final first = File(ppath.join(output.path, 'first.mp4'));
    await first.writeAsString('data');
    final backend = FakeDownloadBackend(output)
      ..present = true
      ..paused = true;
    backend.overrideFiles = [
      DownloadFile(
          location: DownloadLocation(path: first.path, isLocal: true),
          expectedSize: 4,
          completedBytes: 4,
          isVideo: true),
      DownloadFile(
          location: DownloadLocation(
              path: ppath.join(output.path, 'second.mp4'), isLocal: true),
          expectedSize: 4,
          completedBytes: 0,
          isVideo: true)
    ];
    final library = FakeDownloadLibrary();
    final runtime = DownloadRuntime(
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    final engine = TaskEngine(
        store: MemoryJobStore(),
        ownerDeviceId: 'fixture',
        executors: [runtime.executor]);
    runtime.attach(engine, root);
    await engine.start();
    final job = await runtime.downloads.add(testRequest);
    await untilState(engine, job.jobId, JobState.paused);
    PlayableItem? opened;
    final harness = Harness([
      DownloadPlaybackCapability(runtime, (item) async {
        opened = item;
        return true;
      })
    ]);
    final result = await harness.invokeJson('download.play',
        {'jobId': job.jobId, 'fileIndex': 0}, Invocation(origin: 'test'));
    expect(result, isA<Completed>(), reason: '${result.toEnvelope()}');
    expect(opened!.videoPath, first.path);
    expect(opened!.actualPlayUrl, isNull);
    expect(backend.resumes, 0);
    expect((await engine.get(job.jobId)).state, JobState.paused);
    expect((result as Completed).value.toJson(),
        containsPair('fileComplete', true));
    expect(
        (((await runtime.downloads.read(job.jobId))['task'] as Map)['files']
                as List)
            .first['playable'],
        true);
    await first.writeAsString('bad');
    final missing = await harness.invokeJson('download.play',
        {'jobId': job.jobId, 'fileIndex': 0}, Invocation(origin: 'test'));
    expect(missing, isA<Failed>());
    expect(backend.resumes, 0);
    expect(
        (((await runtime.downloads.read(job.jobId))['task'] as Map)['files']
                as List)
            .first['playable'],
        false);
    final outside = File(ppath.join(root.path, 'outside.mp4'));
    await outside.writeAsString('data');
    await first.delete();
    await Link(first.path).create(outside.path);
    final escaped = await harness.invokeJson('download.play',
        {'jobId': job.jobId, 'fileIndex': 0}, Invocation(origin: 'test'));
    expect(escaped, isA<Failed>());
    expect(backend.resumes, 0);
    expect(
        (((await runtime.downloads.read(job.jobId))['task'] as Map)['files']
                as List)
            .first['playable'],
        false);
    await engine.close();
    await runtime.executor.quiesce(job.jobId);
    runtime.dispose();
    await root.delete(recursive: true);
  });
}
