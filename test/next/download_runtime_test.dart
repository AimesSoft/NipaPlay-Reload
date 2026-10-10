import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/downloads/download_runtime.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';

void main() {
  test('observation keeps cancelled data paused until an explicit resume',
      () async {
    final root = await Directory.systemTemp.createTemp('download-cancelled-');
    final backend = FakeDownloadBackend(root)..present = true;
    await backend.finish();
    final library = FakeDownloadLibrary();
    final entered = Completer<void>(), release = Completer<void>();
    backend.onReadSize = (_) async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    final runtime = DownloadRuntime.forTesting(
        root: root,
        store: MemoryJobStore(),
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      runtime.dispose();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    await entered.future;
    final job = (await runtime.engine.list()).single;
    await runtime.engine.cancel(job.jobId);
    release.complete();
    final done =
        await untilState(runtime.engine, job.jobId, JobState.cancelled);
    await runtime.refresh();
    await runtime.refresh();
    expect(await runtime.engine.list(), hasLength(1));
    expect(backend.paused, true);
    expect(library.scans, isEmpty);
    expect((await runtime.engine.get(job.jobId)).toJson(), done.toJson());
    await runtime.downloads.resume(job.jobId);
    await runtime.refresh();
    final resumed = (await runtime.engine.list()).last;
    expect(resumed.jobId, isNot(job.jobId));
    await untilState(runtime.engine, resumed.jobId, JobState.succeeded);
    expect(library.scans, hasLength(1));
    expect(backend.additions, 0);
  });

  test(
      'application service startup adopts the session and imports without a page or Labs',
      () async {
    final root = await Directory.systemTemp.createTemp('download-startup-');
    final backend = FakeDownloadBackend(root)..present = true;
    await backend.finish();
    final library = FakeDownloadLibrary();
    final runtime = DownloadRuntime.forTesting(
        root: root,
        store: MemoryJobStore(),
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      runtime.dispose();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    final job = (await runtime.engine.list(type: 'download')).single;
    final done =
        await untilState(runtime.engine, job.jobId, JobState.succeeded);
    await runtime.refresh();
    expect(done.receipt!.verification, VerificationLevel.verified);
    expect(runtime.autoScannedKeys, contains('$testHash|${root.path}'));
    expect(backend.additions, 0);
    expect(library.scans, hasLength(1));
    await runtime.refresh();
    expect(await runtime.engine.list(type: 'download'), hasLength(1));
    expect(library.scans, hasLength(1));
  });

  test(
      'disabled startup does not initialize the session; enabling starts observation',
      () async {
    final root = await Directory.systemTemp.createTemp('download-disabled-');
    final backend = FakeDownloadBackend(root)..present = true;
    await backend.finish();
    final library = FakeDownloadLibrary();
    var enabled = false;
    final runtime = DownloadRuntime.forTesting(
        root: root,
        store: MemoryJobStore(),
        backend: backend,
        library: library,
        isEnabled: () async => enabled,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      runtime.dispose();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    expect(backend.initializations, 0);
    expect(await runtime.engine.list(), isEmpty);
    enabled = true;
    await runtime.refresh();
    final job = (await runtime.engine.list()).single;
    await untilState(runtime.engine, job.jobId, JobState.succeeded);
    expect(backend.initializations, greaterThan(0));
  });

  test(
      'automatic import disabled still verifies download; enabling imports the completed session',
      () async {
    final root = await Directory.systemTemp.createTemp('download-no-import-');
    final backend = FakeDownloadBackend(root)..present = true;
    await backend.finish();
    final library = FakeDownloadLibrary()..autoImport = false;
    final runtime = DownloadRuntime.forTesting(
        root: root,
        store: MemoryJobStore(),
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      runtime.dispose();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    final first = (await runtime.engine.list()).single;
    final done =
        await untilState(runtime.engine, first.jobId, JobState.succeeded);
    expect((done.receipt!.details['files'] as List).single,
        containsPair('reason', 'auto_import_disabled'));
    expect(library.scans, isEmpty);
    library.autoImport = true;
    await runtime.refresh();
    final import = (await runtime.engine.list()).last;
    await untilState(runtime.engine, import.jobId, JobState.succeeded);
    expect((await runtime.engine.get(first.jobId)).toJson(), done.toJson());
    expect(library.scans, hasLength(1));
  });

  test('a restored paused download stays paused and is not duplicated',
      () async {
    final root = await Directory.systemTemp.createTemp('download-paused-');
    final backend = FakeDownloadBackend(root)
      ..present = true
      ..paused = true;
    final library = FakeDownloadLibrary();
    final runtime = DownloadRuntime.forTesting(
        root: root,
        store: MemoryJobStore(),
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      runtime.dispose();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    final first = (await runtime.engine.list()).single;
    await untilState(runtime.engine, first.jobId, JobState.paused);
    await runtime.refresh();
    expect(await runtime.engine.list(), hasLength(1));
    expect(backend.resumes, 0);
    expect(backend.additions, 0);
  });

  test(
      'an offline backend does not prevent reading tasks or retrying session observation',
      () async {
    final root = await Directory.systemTemp.createTemp('download-offline-');
    final backend = FakeDownloadBackend(root)..online = false;
    final library = FakeDownloadLibrary();
    final runtime = DownloadRuntime.forTesting(
        root: root,
        store: MemoryJobStore(),
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      runtime.dispose();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    expect(runtime.lastSessionError!.code, FailureCode.unavailable);
    expect(await runtime.engine.list(), isEmpty);
    backend.online = true;
    backend.present = true;
    await backend.finish();
    await runtime.refresh();
    final job = (await runtime.engine.list()).single;
    await untilState(runtime.engine, job.jobId, JobState.succeeded);
  });
}
