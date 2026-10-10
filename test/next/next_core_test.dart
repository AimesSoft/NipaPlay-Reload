import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'download_test_support.dart';
import 'media_test_support.dart';

void main() {
  late Directory root, mediaFolder;
  late FakeDownloadBackend backend;
  late FakeDownloadLibrary library;
  late MemoryClassic classic;
  late FixtureTransport tmdb, dandanplay;
  late NextCore core;

  NextCore createCore() => NextCore(
        root: root,
        databaseFactory: databaseFactoryFfi,
        downloadBackend: backend,
        downloadLibrary: library,
        isDownloaderEnabled: () async => true,
        loadImportedKeys: () async => library.importedKeys,
        downloadRefreshInterval: const Duration(milliseconds: 20),
        classic: classic,
        authorizedRoots: () => [mediaFolder.path],
        mediaProviders: [
          TmdbMetadataProvider(tmdb),
          DandanplayMetadataProvider(dandanplay),
        ],
      );

  Future<JsonMap> call(Harness harness, String action, JsonMap input) async {
    final outcome =
        await harness.invokeJson(action, input, Invocation(origin: 'mcp'));
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    return (outcome as Completed).value.toJson();
  }

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-core-');
    mediaFolder = await Directory('${root.path}/media').create();
    backend = FakeDownloadBackend(root);
    library = FakeDownloadLibrary();
    classic = MemoryClassic();
    tmdb = FixtureTransport('tmdb');
    dandanplay = FixtureTransport('dandanplay');
  });
  tearDown(() async {
    await core.close();
    await root.delete(recursive: true);
  });

  test('Classic and Harness share live download and media tasks without Labs',
      () async {
    core = createCore();
    await core.ready;
    final harness = Harness(core.capabilities);
    expect(core.downloads.engine, same(core.engine));
    expect(core.media.service.engine, same(core.engine));
    expect(core.danmaku.service.engine, same(core.engine));
    expect(core.media.service.store.database,
        same((core.engine.store as SqliteJobStore).database));
    expect(core.danmaku.service.store.db,
        same((core.engine.store as SqliteJobStore).database));
    final db = core.media.service.store.database;
    expect(await db.getVersion(), 4);
    expect(await db.query('settings_changes'), isEmpty);
    expect(await db.query('danmaku_bindings'), isEmpty);
    expect((await db.rawQuery('PRAGMA foreign_key_check')), isEmpty);

    // The backend finishes after startup; only application observation imports it.
    backend.present = true;
    await backend.finish();
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while ((await core.engine.list(type: 'download')).isEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('Session was not adopted.');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final download = (await core.engine.list(type: 'download')).single;
    await waitForJob(core.engine, download.jobId, JobState.succeeded);
    expect(library.scans, hasLength(1));
    expect(backend.additions, 0);

    await File('${mediaFolder.path}/长安十二时辰 S01E01.mkv')
        .writeAsString('offline media');
    final scan = await call(harness, 'media.library.scan', {
      'root': mediaFolder.path,
      'requestId': 'core-scan',
      'sources': ['tmdb']
    });
    final scanned = await waitForJob(core.engine,
        (scan['job'] as JsonMap)['jobId'] as String, JobState.succeeded);
    final identification = await waitForJob(
        core.engine,
        (scanned.receipt!.details['identificationJobIds'] as List).single
            as String,
        JobState.needsDecision);
    final choice = identification.decision!.options
        .firstWhere((option) => option.call.actionId == 'media.identity.bind')
        .call;
    await call(harness, choice.actionId, choice.input);
    await waitForJob(core.engine, identification.jobId, JobState.succeeded);
    expect((await call(harness, 'media.library.works', {}))['works'],
        hasLength(1));
    final listed = (await call(harness, 'task.list', {}))['jobs'] as List;
    expect(listed.map((job) => (job as JsonMap)['type']),
        containsAll(['download', 'media.scan', 'media.identify']));
    expect(
        listed
            .every((job) => (job as JsonMap)['ownerDeviceId'] == core.deviceId),
        isTrue);
  });

  test('startup recovers both domains using the persisted device and database',
      () async {
    backend.present = true;
    core = createCore();
    await core.ready;
    final deviceId = core.deviceId;
    final download = (await core.engine.list(type: 'download')).single;
    await waitForJob(core.engine, download.jobId, JobState.running);
    final file = await File('${mediaFolder.path}/长安十二时辰 S01E01.mkv')
        .writeAsString('offline media');
    final fileId = await core.media.service.index(file.path);
    tmdb.retry = ProviderRetry(
        'tmdb',
        DateTime.now().toUtc().add(const Duration(seconds: 1)),
        'offline retry');
    final identification =
        await core.media.service.identify(fileId, sources: ['tmdb']);
    await waitForJob(core.engine, identification.jobId, JobState.waitingRetry);
    await core.close();
    await backend.finish();

    core = createCore();
    await core.ready;
    expect(core.deviceId, deviceId);
    await waitForJob(core.engine, download.jobId, JobState.succeeded);
    await waitForJob(core.engine, identification.jobId, JobState.needsDecision);
    expect(await core.engine.list(type: 'download'), hasLength(1));
    expect(await core.engine.list(type: 'media.identify'), hasLength(1));
    expect(library.scans, hasLength(1));
    expect(backend.additions, 0);
    expect((await core.engine.store.events(download.jobId)).map((e) => e.kind),
        contains('interrupted'));
  });

  test(
      'Core registers and resumes persisted danmaku execution before a player is bound',
      () async {
    core = createCore();
    await core.ready;
    final fileId = await core.media.service.store
        .ensureFile('${mediaFolder.path}/fixture.mkv');
    final bindingId = await core.danmaku.service.store.attach(
        fileId,
        const DanmakuVideo(
            sourceId: 'bilibili',
            videoId: '101',
            title: '合成',
            durationMs: 720000,
            objectType: 'cid'),
        '合成证据',
        null,
        Invocation(origin: 'mcp'));
    final date = DateTime.now().toUtc();
    final job = Job(
        jobId: 'core-danmaku-align',
        type: 'danmaku.align',
        title: 'Persisted legacy alignment',
        state: JobState.needsDecision,
        phase: 'estimate',
        progress: JobProgress(completed: 0, unit: 'anchors'),
        createdAt: date,
        updatedAt: date,
        ownerDeviceId: core.deviceId,
        revision: 0,
        sideEffectCommitted: true,
        input: {'bindingId': bindingId, 'bindingRevision': 0},
        decision: const Decision(prompt: 'Persisted choice', options: [
          DecisionOption(
              label: 'Apply',
              call: ActionCall('danmaku.align_apply',
                  {'jobId': 'core-danmaku-align', 'revision': 0}))
        ]));
    await core.engine.store.commit(
        job,
        JobEvent(
            jobId: job.jobId,
            revision: 0,
            kind: 'needs_decision',
            at: date,
            snapshot: job.toJson()),
        expectedRevision: null);
    await core.danmaku.service.store.db.insert('danmaku_alignment_candidates', {
      'job_id': job.jobId,
      'binding_id': bindingId,
      'binding_revision': 0,
      'state': 'proposed',
      'payload': jsonEncode({
        'method': 'manualAnchors',
        'offsetMs': 500,
        'anchors': [
          {'sourceTimeMs': 1000, 'mediaTimeMs': 500, 'evidence': '合成锚点'}
        ],
        'maxResidualMs': 0,
        'confidence': 'insufficientEvidence',
        'confirmed': false,
        'applicableRange': 'requested media version',
        'autoApply': false
      })
    });
    expect(core.danmaku.service.player.target, isNull);
    await core.close();
    core = createCore();
    await core.ready;
    final pending = await core.engine.get(job.jobId);
    expect(pending.state, JobState.needsDecision);
    final option = pending.decision!.options
        .firstWhere((option) => option.call.actionId == 'danmaku.align_apply')
        .call;
    await call(Harness(core.capabilities), option.actionId, option.input);
    await waitForJob(core.engine, job.jobId, JobState.succeeded);
    expect((await core.danmaku.service.store.binding(bindingId))['offset_ms'],
        500);
    final catalog =
        await call(Harness(core.capabilities), 'danmaku.sources', {});
    expect((catalog['sources'] as List).map((source) => source['sourceId']),
        contains('local'));
  });

  test('startup delivers pending Classic media projections without an Agent',
      () async {
    core = createCore();
    await core.ready;
    final file = await File('${mediaFolder.path}/Hash Sample S01E01.mkv')
        .writeAsString('offline media');
    final fileId = await core.media.service.index(file.path);
    classic.rejectReadback = true;
    final identification =
        await core.media.service.identify(fileId, sources: ['dandanplay']);
    await waitForJob(core.engine, identification.jobId, JobState.failed);
    expect(await core.media.service.store.pendingProjections(), hasLength(1));
    final bindings =
        await core.media.service.store.database.query('media_bindings');
    await core.close();
    classic.rejectReadback = false;
    core = createCore();
    await core.ready;
    final repair = (await core.engine.list(type: 'media.project')).single;
    await waitForJob(core.engine, repair.jobId, JobState.succeeded);
    expect(await core.media.service.store.pendingProjections(), isEmpty);
    expect(await core.media.service.store.database.query('media_bindings'),
        bindings);
  });
}
