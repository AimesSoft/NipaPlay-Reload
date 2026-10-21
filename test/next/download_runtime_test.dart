import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/scan_service.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';
import 'media_test_support.dart';

NextCore createCore({
  required Directory root,
  required FakeDownloadBackend backend,
  required FakeDownloadLibrary library,
  required Future<bool> Function() isEnabled,
  required Future<Set<String>> Function() loadImportedKeys,
}) =>
    NextCore(
      root: root,
      databaseFactory: databaseFactoryFfi,
      downloadBackend: backend,
      downloadLibrary: library,
      isDownloaderEnabled: isEnabled,
      loadImportedKeys: loadImportedKeys,
      classic: MemoryClassic(),
      authorizedRoots: () => [root.path],
      mediaProviders: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(sqfliteFfiInit);
  test('Next startup policy preserves Classic when the endpoint stays enabled',
      () async {
    SharedPreferences.setMockInitialValues({
      'labs_enable_agent_endpoint': true,
      'labs_use_next_interface': false,
      'next_startup_scan_enabled': false,
    });
    final root = await Directory.systemTemp.createTemp('x55-classic-startup-');
    final runtime = createCore(
        root: root,
        backend: FakeDownloadBackend(root),
        library: FakeDownloadLibrary(),
        isEnabled: () async => false,
        loadImportedKeys: () async => {});
    addTearDown(() async {
      await runtime.close();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    var calls = 0;
    final classic = ScanService.forTesting(
        completedFilesProcessor: (_) async => [],
        startupAction: () async { calls++; });
    addTearDown(classic.dispose);
    await classic.startStartupRefresh();
    expect(calls, 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('labs_use_next_interface', true);
    final next = ScanService.forTesting(
        completedFilesProcessor: (_) async => [],
        startupAction: () async { calls++; });
    addTearDown(next.dispose);
    await next.startStartupRefresh();
    expect(calls, 1);
  });
  test('unidentified downloads stay complete across observation and restart',
      () async {
    final root =
        await Directory.systemTemp.createTemp('download-unidentified-');
    final backend = FakeDownloadBackend(root)..present = true;
    await backend.finish();
    final library = FakeDownloadLibrary()..identify = false;
    NextCore createRuntime() => createCore(
        root: root,
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    var runtime = createRuntime();
    addTearDown(() async {
      await runtime.close();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    final job = (await runtime.engine.list()).single;
    final done =
        await untilState(runtime.engine, job.jobId, JobState.succeeded);
    expect(
        (done.receipt!.details['files'] as List).single,
        allOf(containsPair('imported', false),
            containsPair('identificationPending', true)));
    await runtime.downloads.refresh();
    await runtime.downloads.refresh();
    expect(library.scans, hasLength(1));
    await runtime.close();
    runtime = createRuntime();
    await runtime.ready;
    expect(await runtime.engine.list(), hasLength(1));
    expect((await runtime.engine.get(job.jobId)).toJson(), done.toJson());
    expect(library.scans, hasLength(1));
  });

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
    final runtime = createCore(
        root: root,
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    await entered.future;
    final job = (await runtime.engine.list()).single;
    await runtime.engine.cancel(job.jobId);
    release.complete();
    final done =
        await untilState(runtime.engine, job.jobId, JobState.cancelled);
    await runtime.downloads.refresh();
    await runtime.downloads.refresh();
    expect(await runtime.engine.list(), hasLength(1));
    expect(backend.paused, true);
    expect(library.scans, isEmpty);
    expect((await runtime.engine.get(job.jobId)).toJson(), done.toJson());
    await runtime.downloads.downloads.resume(job.jobId);
    await runtime.downloads.refresh();
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
    final runtime = createCore(
        root: root,
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    final job = (await runtime.engine.list(type: 'download')).single;
    final done =
        await untilState(runtime.engine, job.jobId, JobState.succeeded);
    await runtime.downloads.refresh();
    expect(done.receipt!.verification, VerificationLevel.verified);
    expect(
        runtime.downloads.autoScannedKeys, contains('$testHash|${root.path}'));
    expect(backend.additions, 0);
    expect(library.scans, hasLength(1));
    await runtime.downloads.refresh();
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
    final runtime = createCore(
        root: root,
        backend: backend,
        library: library,
        isEnabled: () async => enabled,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    expect(backend.initializations, 0);
    expect(await runtime.engine.list(), isEmpty);
    enabled = true;
    await runtime.downloads.refresh();
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
    final runtime = createCore(
        root: root,
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
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
    await runtime.downloads.refresh();
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
    final runtime = createCore(
        root: root,
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    final first = (await runtime.engine.list()).single;
    await untilState(runtime.engine, first.jobId, JobState.paused);
    await runtime.downloads.refresh();
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
    final runtime = createCore(
        root: root,
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    addTearDown(() async {
      await runtime.close();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    expect(runtime.downloads.lastSessionError!.code, FailureCode.unavailable);
    expect(await runtime.engine.list(), isEmpty);
    backend.online = true;
    backend.present = true;
    await backend.finish();
    await runtime.downloads.refresh();
    final job = (await runtime.engine.list()).single;
    await untilState(runtime.engine, job.jobId, JobState.succeeded);
  });

  test('a session removed outside Next is noticed at startup and on refresh',
      () async {
    final root = await Directory.systemTemp.createTemp('download-vanished-');
    final backend = FakeDownloadBackend(root)..present = true;
    await backend.finish();
    final library = FakeDownloadLibrary();
    NextCore createRuntime() => createCore(
        root: root,
        backend: backend,
        library: library,
        isEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys);
    var runtime = createRuntime();
    addTearDown(() async {
      await runtime.close();
      await root.delete(recursive: true);
    });
    await runtime.ready;
    final job = (await runtime.engine.list()).single;
    final done =
        await untilState(runtime.engine, job.jobId, JobState.succeeded);
    await runtime.downloads.refresh();
    expect((await runtime.engine.get(job.jobId)).toJson(), done.toJson());
    // Classic forgets it while Next runs.
    backend.present = false;
    await runtime.downloads.refresh();
    final seen = await runtime.engine.get(job.jobId);
    expect(seen.receipt!.details['sessionPresent'], false);
    expect(seen.receipt!.details.containsKey('dataDeleted'), isFalse);
    expect(seen.receipt!.details['observedMissingAt'], isNotNull);
    await runtime.downloads.refresh();
    expect((await runtime.engine.get(job.jobId)).toJson(), seen.toJson());
    // Forgotten while Next was closed: noticed on the next start.
    backend.present = true;
    await runtime.close();
    runtime = createRuntime();
    await runtime.ready;
    await runtime.downloads.refresh();
    final again = (await runtime.engine.list(type: 'download'))
        .where((j) => j.jobId != job.jobId)
        .single;
    await untilState(runtime.engine, again.jobId, JobState.succeeded);
    backend.present = false;
    await runtime.close();
    runtime = createRuntime();
    await runtime.ready;
    final restarted = await runtime.engine.get(again.jobId);
    expect(restarted.receipt!.details['sessionPresent'], false);
  });
}
