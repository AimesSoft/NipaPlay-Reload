import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/danmaku/export.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/media/media_migration.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'danmaku_test_support.dart';

void main() {
  late DanmakuFixture f;
  setUp(() async {
    f = DanmakuFixture();
    await f.open();
  });
  tearDown(() => f.close());
  Future<JsonMap> attach(String entity, DanmakuVideo video,
          {String origin = 'mcp'}) =>
      f.call(
          'danmaku.attach',
          {
            'entityId': entity,
            'video': video.toJson(),
            'reason': 'Synthetic same episode evidence',
            'requestId': 'attach-${video.sourceId}',
          },
          origin: origin);

  test(
      'v2 upgrade preserves media and existing job snapshots and appends MB tables',
      () async {
    final root = await Directory.systemTemp.createTemp('next-v2-');
    final db = await databaseFactoryFfi.openDatabase('${root.path}/next.db',
        options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, _) async {
              await db.execute(
                  'CREATE TABLE jobs(job_id TEXT PRIMARY KEY,type TEXT NOT NULL,state TEXT NOT NULL,revision INTEGER NOT NULL,created_at TEXT NOT NULL,snapshot TEXT NOT NULL)');
              await db.execute(
                  'CREATE TABLE job_events(job_id TEXT NOT NULL REFERENCES jobs(job_id),revision INTEGER NOT NULL,kind TEXT NOT NULL,at TEXT NOT NULL,snapshot TEXT NOT NULL,PRIMARY KEY(job_id,revision))');
              await migrateMediaIdentity(db);
            }));
    final entity = {
      'id': 'old-file',
      'kind': 'file',
      'revision': 7,
      'attributes': jsonEncode({'bindingRevision': 3})
    };
    await db.insert('media_entities', entity);
    final date = DateTime.utc(2026, 10, 10);
    final job = Job(
        jobId: 'old-download',
        type: 'download',
        title: 'Prior MA task',
        state: JobState.queued,
        phase: 'queued',
        progress: JobProgress(completed: 0, unit: 'bytes'),
        createdAt: date,
        updatedAt: date,
        ownerDeviceId: 'fixture-device',
        revision: 0);
    await db.insert('jobs', {
      'job_id': job.jobId,
      'type': job.type,
      'state': 'queued',
      'revision': 0,
      'created_at': date.toIso8601String(),
      'snapshot': jsonEncode(job.toStorageJson())
    });
    await db.close();
    final upgraded =
        await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    expect(await upgraded.database.getVersion(), 12);
    expect((await upgraded.database.query('media_entities')).single,
        {...entity, 'parent_id': null});
    expect(
        (await upgraded.get(job.jobId))!.toStorageJson(), job.toStorageJson());
    expect(await upgraded.database.query('danmaku_bindings'), isEmpty);
    await upgraded.close();
    await root.delete(recursive: true);
  });
  test('read actions declare read and never persist cache bindings or tasks',
      () async {
    final id = await f.file();
    await f.call('danmaku.sources', {});
    await f.call('danmaku.tracks', {'entityId': id});
    await f.call(
        'danmaku.episodes', {'sourceId': 'minutes', 'workId': 'show-fixture'});
    await f.call(
        'danmaku.resolve', {'sourceId': 'minutes', 'locator': 'Xfixture'});
    expect(await f.jobs.list(), isEmpty);
    expect(await f.jobs.database.query('danmaku_bindings'), isEmpty);
    expect(await f.jobs.database.query('danmaku_cache_chunks'), isEmpty);
    for (final spec
        in f.harness.catalog.where((s) => s.id.startsWith('danmaku.'))) {
      final read = [
        'danmaku.sources',
        'danmaku.search',
        'danmaku.episodes',
        'danmaku.resolve',
        'danmaku.tracks',
        'danmaku.analyze_alignment'
      ].contains(spec.id);
      expect(
          spec.effect,
          read
              ? Effect.read
              : spec.id == 'danmaku.cache_delete'
                  ? Effect.destructive
                  : Effect.write);
    }
  });
  test('resolution ambiguity has directly executable read-only options',
      () async {
    final outcome = await f.harness.invokeJson(
        'danmaku.resolve',
        {'sourceId': 'segmented', 'locator': 'ambiguous'},
        Invocation(origin: 'mcp'));
    final decision = (outcome as NeedsDecision).decision;
    expect(decision.options, hasLength(2));
    for (final option in decision.options) {
      expect(
          f.harness
              .lookup(option.call.actionId)!
              .spec
              .input
              .validate(option.call.input),
          isEmpty);
      final result = await f.call(option.call.actionId, option.call.input);
      expect((result['video'] as Map)['videoId'],
          option.call.input['selectionVideoId']);
    }
    expect(await f.jobs.list(), isEmpty);
  });
  test(
      'multiple sources attach to the same MA file with host-derived provenance and player tracks',
      () async {
    final entity = await f.file();
    final results = [
      await attach(entity, ddpVideo, origin: 'gui'),
      await attach(entity, segmentedVideo),
      await attach(entity, minuteVideo)
    ];
    for (final result in results) {
      final job = await f.wait(result['jobId'] as String, JobState.succeeded);
      expect(job.receipt!.details['complete'], isTrue);
      expect(job.receipt!.details['loaded'], isTrue);
      expect(job.receipt!.details['historyComplete'], isFalse);
    }
    final tracks = (await f
        .call('danmaku.tracks', {'entityId': entity}))['tracks'] as List;
    expect(tracks, hasLength(3));
    expect(f.player.managedTracks, hasLength(3));
    final bindings = await f.service.store.bindings(entity);
    expect(bindings.map((b) => b['bound_by']), containsAll(['user', 'agent']));
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
    expect(await f.jobs.database.query('media_projection_outbox'), isEmpty);
    expect(await f.jobs.database.query('media_external_objects'), hasLength(3));
    expect(await f.jobs.database.query('danmaku_binding_events'), hasLength(3));
    final unexpectedActor = await f.harness.invokeJson(
        'danmaku.attach',
        {
          'entityId': entity,
          'video': segmentedVideo.toJson(),
          'reason': 'fixture',
          'requestId': 'bad',
          'boundBy': 'user'
        },
        Invocation(origin: 'mcp'));
    expect(unexpectedActor, isA<Failed>());
  });
  test(
      'standalone fetch writes verified cache without modifying the current tracks',
      () async {
    await f.file();
    final submitted = await f.call('danmaku.fetch',
        {'video': segmentedVideo.toJson(), 'requestId': 'standalone'});
    final job = await f.wait(submitted['jobId'] as String, JobState.succeeded);
    expect(job.receipt!.details['loaded'], isFalse);
    expect(job.receipt!.details['rawCount'], 2);
    expect(f.player.managedTracks, isEmpty);
    expect(await f.jobs.database.query('danmaku_bindings'), isEmpty);
    final repeated = await f.call('danmaku.fetch',
        {'video': segmentedVideo.toJson(), 'requestId': 'standalone'});
    expect(repeated['jobId'], submitted['jobId']);
    expect(await f.jobs.list(), hasLength(1));
  });
  test('duplicate acquisitions share committed chunks', () async {
    final jobs = await Future.wait([
      f.service.fetch(minuteVideo, requestId: 'first'),
      f.service.fetch(minuteVideo, requestId: 'second')
    ]);
    for (final job in jobs) {
      await f.wait(job.jobId, JobState.succeeded);
    }
    expect(f.host.requests.where((r) => r['profile'] == 'minutes.chunk'),
        hasLength(2));
  });
  test(
      'one malformed minute fails with persisted partial coverage and does not mount an incomplete track',
      () async {
    final entity = await f.file();
    f.host.responses['minutes.chunk:1'] = jsonBytes({'entries': 'malformed'});
    final result = await attach(entity, minuteVideo);
    final job = await f.wait(result['jobId'] as String, JobState.failed);
    expect(job.receipt!.details['status'], 'schemaChanged');
    expect(job.receipt!.details['complete'], isFalse);
    expect(job.receipt!.details['completedChunks'], [0]);
    expect(job.receipt!.details['missingChunks'], hasLength(1));
    expect(f.player.managedTracks, isEmpty);
    expect(await f.jobs.database.query('danmaku_cache_chunks'), hasLength(1));
    expect(
        (await f.service.store
            .binding(result['bindingId'] as String))['cache_key'],
        isNull);
  });
  test('an explicit empty pool succeeds and restores an empty enabled track',
      () async {
    final entity = await f.file();
    f.host.responses['dandanplay.comments'] = jsonBytes({'comments': []});
    final result = await attach(entity, ddpVideo);
    final job = await f.wait(result['jobId'] as String, JobState.succeeded);
    expect(job.receipt!.details['status'], 'validEmpty');
    expect(job.receipt!.details['rawCount'], 0);
    expect(f.player.data[result['bindingId']], isEmpty);
  });
  test('cancellation aborts a pending chunk and stops subsequent requests',
      () async {
    await f.file();
    f.host.blockedKey = 'minutes.chunk:1';
    f.host.entered = Completer();
    f.host.release = Completer();
    final job = await f.service.fetch(minuteVideo, requestId: 'cancel');
    await f.host.entered!.future;
    await f.engine.cancel(job.jobId);
    final cancelled = await f.wait(job.jobId, JobState.failed);
    expect(cancelled.receipt!.details['stopped'], true);
    expect(cancelled.receipt!.verification, VerificationLevel.verified);
    expect(cancelled.receipt!.details['completedChunks'], [0]);
    expect(cancelled.receipt!.details['missingChunks'], hasLength(1));
    expect(await f.jobs.database.query('danmaku_cache_chunks'), hasLength(1));
  });
  test('cancelling a queued source job makes no request', () async {
    f.host.blockedKey = 'minutes.chunk:0';
    f.host.entered = Completer();
    f.host.release = Completer();
    final first = await f.service.fetch(minuteVideo, requestId: 'held');
    await f.host.entered!.future;
    final second = await f.service.fetch(minuteVideo, requestId: 'queued');
    await f.engine.cancel(second.jobId);
    await f.wait(second.jobId, JobState.cancelled);
    expect(f.host.requests, hasLength(1));
    await f.engine.cancel(first.jobId);
    await f.wait(first.jobId, JobState.cancelled);
  });
  test(
      'engine shutdown and restart recover completed chunks without refetching them',
      () async {
    f.host.blockedKey = 'minutes.chunk:1';
    f.host.entered = Completer();
    f.host.release = Completer();
    final job = await f.service.fetch(minuteVideo, requestId: 'restart');
    await f.host.entered!.future;
    await f.reopen();
    f.host.blockedKey = null;
    f.host.release!.complete();
    final recovered = await f.wait(job.jobId, JobState.succeeded);
    expect(recovered.receipt!.details['complete'], isTrue);
    expect(f.host.requests.where((r) => (r['parameters'] as Map)['index'] == 0),
        hasLength(1));
  });
  test(
      'source rate limiting persists bounded retry state with the completed checkpoint',
      () async {
    f.host.failure = SourceFailure(SourceStatus.rateLimited,
        retryAt: DateTime.now().toUtc().add(const Duration(minutes: 1)));
    final job = await f.service.fetch(segmentedVideo, requestId: 'rate-limit');
    final waiting = await f.wait(job.jobId, JobState.waitingRetry);
    expect(waiting.checkpoint['retries'], 1);
    expect(waiting.retryAt, isNotNull);
    await f.engine.cancel(job.jobId);
    await f.wait(job.jobId, JobState.cancelled);
  });
  test(
      'media content revision changing mid-fetch prevents obsolete binding from mounting',
      () async {
    final entity = await f.file();
    f.host.blockedKey = 'segmented.chunk:1';
    f.host.entered = Completer();
    f.host.release = Completer();
    final result = await attach(entity, segmentedVideo);
    await f.host.entered!.future;
    await f.identities.registerFile('/fixture/video.mkv',
        {'size': 2, 'modifiedAt': 'changed', 'headMd5': 'changed'});
    f.host.release!.complete();
    final job = await f.wait(result['jobId'] as String, JobState.failed);
    expect(job.error!.code, FailureCode.conflict);
    expect(f.player.managedTracks, isEmpty);
    expect((await f.call('danmaku.tracks', {'entityId': entity}))['tracks'],
        contains(isA<Map>().having((r) => r['stale'], 'stale', true)));
  });
  test(
      'changing video during fetch caches data but never loads into the other file',
      () async {
    final entity = await f.file();
    f.host.blockedKey = 'segmented.chunk:1';
    f.host.entered = Completer();
    f.host.release = Completer();
    final result = await attach(entity, segmentedVideo);
    await f.host.entered!.future;
    f.player.target = const DanmakuPlaybackTarget('/fixture/other.mkv', 2);
    f.host.release!.complete();
    final job = await f.wait(result['jobId'] as String, JobState.succeeded);
    expect(job.receipt!.details['loaded'], isFalse);
    expect(f.player.managedTracks, isEmpty);
    f.player.target = const DanmakuPlaybackTarget('/fixture/video.mkv', 3);
    await f.service.refreshCurrent();
    expect(f.player.managedTracks, hasLength(1));
  });
  test(
      'offsets and enable state persist independently and absolute offsets do not accumulate',
      () async {
    final entity = await f.file();
    final result = await attach(entity, segmentedVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    final id = result['bindingId'] as String;
    await f.call(
        'danmaku.offset', {'bindingId': id, 'revision': 0, 'offsetMs': 1500});
    await f.call(
        'danmaku.offset', {'bindingId': id, 'revision': 1, 'offsetMs': 1500});
    await f.call('danmaku.set_enabled',
        {'bindingId': id, 'revision': 2, 'enabled': false});
    await f.call('danmaku.set_dedup',
        {'bindingId': id, 'revision': 3, 'deduplicate': false});
    expect(f.player.tracks[id]!['offsetMs'], 1500);
    expect(f.player.data[id]!.first.sourceTimeMs, 1000);
    await f.reopen();
    await f.service.refreshCurrent();
    expect(f.player.tracks[id]!['enabled'], isFalse);
    expect(f.player.tracks[id]!['offsetMs'], 1500);
    expect((await f.service.store.binding(id))['deduplicate'], 0);
    final stale = await f.harness.invokeJson(
        'danmaku.offset',
        {'bindingId': id, 'revision': 0, 'offsetMs': 0},
        Invocation(origin: 'gui'));
    expect((stale as Failed).failure.code, FailureCode.conflict);
  });
  test(
      'detach preserves cache and history without touching Classic fixed track semantics',
      () async {
    final entity = await f.file();
    final result = await attach(entity, ddpVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    final id = result['bindingId'] as String;
    await f.call('danmaku.detach', {'bindingId': id, 'revision': 0});
    expect(f.player.managedTracks, isEmpty);
    expect(await f.jobs.database.query('danmaku_cache_chunks'), hasLength(1));
    expect((await f.service.store.binding(id, active: false))['status'],
        'revoked');
    expect(await f.jobs.database.query('danmaku_binding_events'), hasLength(2));
  });
  test(
      'cache deletion removes its loaded track while preserving the accepted binding',
      () async {
    final entity = await f.file();
    final result = await attach(entity, segmentedVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    final b = await f.service.store.binding(result['bindingId'] as String);
    await f.call('danmaku.cache_delete', {'cacheKey': b['cache_key']});
    expect(await f.jobs.database.query('danmaku_cache_chunks'), isEmpty);
    expect(f.player.managedTracks, isEmpty);
    expect(
        (await f.service.store
            .binding(result['bindingId'] as String))['status'],
        'accepted');
  });
  test(
      'alignment candidates wait for an exact explicit choice and recover across restart',
      () async {
    final entity = await f.file();
    final result = await attach(entity, segmentedVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    final id = result['bindingId'] as String;
    final alignment = await f.legacyAlignment({
      'bindingId': id,
      'requestId': 'anchors',
      'anchors': [
        {'sourceTimeMs': 10000, 'mediaTimeMs': 8000, 'evidence': 'first event'},
        {
          'sourceTimeMs': 80000,
          'mediaTimeMs': 78000,
          'evidence': 'second event'
        },
        {
          'sourceTimeMs': 140000,
          'mediaTimeMs': 138100,
          'evidence': 'third event'
        }
      ]
    });
    final decision =
        await f.wait(alignment['jobId'] as String, JobState.needsDecision);
    expect((await f.service.store.binding(id))['offset_ms'], 0);
    for (final option in decision.decision!.options) {
      expect(
          f.harness
              .lookup(option.call.actionId)!
              .spec
              .input
              .validate(option.call.input),
          isEmpty);
    }
    await f.reopen();
    final option = decision.decision!.options.first;
    await f.call(option.call.actionId, option.call.input, origin: 'gui');
    final applied = await f.wait(decision.jobId, JobState.succeeded);
    expect(applied.receipt!.details['applied'], isTrue);
    final b = await f.service.store.binding(id);
    expect(b['offset_ms'], 2000);
    expect((b['alignment'] as Map)['confirmedBy'], 'user');
    expect(f.player.data[id]!.first.sourceTimeMs, 1000);
    final repeated = await f.harness.invokeJson(
        option.call.actionId, option.call.input, Invocation(origin: 'mcp'));
    expect((repeated as Failed).failure.code, FailureCode.conflict);
  });
  test(
      'stale alignment cannot overwrite a manual offset made during its decision',
      () async {
    final entity = await f.file();
    final result = await attach(entity, segmentedVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    final id = result['bindingId'] as String;
    final submitted = await f.legacyAlignment({
      'bindingId': id,
      'requestId': 'stale',
      'anchors': [
        {
          'sourceTimeMs': 1000,
          'mediaTimeMs': 500,
          'evidence': 'one unverified event'
        }
      ]
    });
    final job =
        await f.wait(submitted['jobId'] as String, JobState.needsDecision);
    await f.call(
        'danmaku.offset', {'bindingId': id, 'revision': 0, 'offsetMs': -100});
    final option = job.decision!.options.first;
    await f.call(option.call.actionId, option.call.input);
    final failed = await f.wait(job.jobId, JobState.failed);
    expect(failed.error!.code, FailureCode.conflict);
    expect((await f.service.store.binding(id))['offset_ms'], -100);
  });
  test('empty legacy alignment evidence can keep the existing mapping',
      () async {
    final entity = await f.file();
    final result = await attach(entity, segmentedVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    final submitted = await f.legacyAlignment({
      'bindingId': result['bindingId'],
      'requestId': 'empty',
      'anchors': []
    });
    final job =
        await f.wait(submitted['jobId'] as String, JobState.needsDecision);
    expect(job.decision!.options, hasLength(1));
    final option = job.decision!.options.single;
    await f.call(option.call.actionId, option.call.input);
    expect(
        (await f.wait(job.jobId, JobState.succeeded))
            .receipt!
            .details['applied'],
        isFalse);
  });
  test(
      'Episode bindings rebuild on its MA file link without a Dandanplay identity',
      () async {
    final fileId = await f.file();
    await f.jobs.database.insert('media_entities', {
      'id': 'episode-fixture',
      'kind': 'episode',
      'revision': 0,
      'attributes': '{}'
    });
    await f.jobs.database.insert('media_file_episodes', {
      'file_id': fileId,
      'episode_id': 'episode-fixture',
      'relation': 'exact',
      'ordinal': 0,
      'start_ms': 10000,
      'end_ms': 900000
    });
    final result = await attach('episode-fixture', segmentedVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    expect(f.player.tracks[result['bindingId']]!['startMs'], 10000);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
  });

  test(
      'cache deletion rejects an active fetch rather than allowing silent repopulation',
      () async {
    f.host.blockedKey = 'minutes.chunk:1';
    f.host.entered = Completer();
    f.host.release = Completer();
    final job = await f.service.fetch(minuteVideo, requestId: 'delete-active');
    await f.host.entered!.future;
    final key =
        f.service.store.cacheKey(minuteVideo, f.service.source('minutes'));
    final outcome = await f.harness.invokeJson(
        'danmaku.cache_delete', {'cacheKey': key}, Invocation(origin: 'gui'));
    expect((outcome as Failed).failure.code, FailureCode.conflict);
    await f.engine.cancel(job.jobId);
    await f.wait(job.jobId, JobState.failed);
    await f.call('danmaku.cache_delete', {'cacheKey': key});
    expect(await f.jobs.database.query('danmaku_cache_chunks'), isEmpty);
  });
  test(
      'expired chunks are refetched and refresh a mounted track even with unchanged identity and offset',
      () async {
    final entity = await f.file();
    final result = await attach(entity, segmentedVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    final id = result['bindingId'] as String;
    await f.jobs.database.update('danmaku_cache_chunks',
        {'fetched_at': DateTime.utc(2000).toIso8601String()});
    f.host.responses['segmented.chunk:0'] = fixtureChunk(text: '更新后的合成弹幕');
    final second = await f.service
        .fetch(segmentedVideo, bindingId: id, requestId: 'refresh-cache');
    await f.wait(second.jobId, JobState.succeeded);
    expect(f.player.data[id]!.first.text, '更新后的合成弹幕');
    expect((await f.service.store.binding(id))['cache_revision'], 2);
    expect(f.host.requests.where((r) => r['profile'] == 'segmented.chunk'),
        hasLength(4));
  });
  test(
      'source identity dedup preserves different sender IDs and anonymous simultaneous comments',
      () async {
    const text = '同一时刻多名观众的文本';
    f.host.responses['dandanplay.comments'] = jsonBytes({
      'comments': [
        {'cid': 1, 'p': '1,1,255,sender-a', 'm': text},
        {'cid': 1, 'p': '1,1,255,sender-a', 'm': text},
        {'cid': 2, 'p': '1,1,255,sender-b', 'm': text},
        {'p': '1,1,255,0', 'm': text},
        {'p': '1,1,255,0', 'm': text}
      ]
    });
    final job = await f.service.fetch(ddpVideo, requestId: 'sender-identity');
    final done = await f.wait(job.jobId, JobState.succeeded);
    expect(done.receipt!.details['rawCount'], 5);
    expect(done.receipt!.details['cachedUniqueCount'], 4);
    expect(
        (await f.service.store
                .entries(done.receipt!.details['cacheKey'] as String))
            .map((e) => e.sender),
        ['sender-a', 'sender-b', null, null]);
  });
  test('alignment requestId is idempotent before and after an explicit choice',
      () async {
    final entity = await f.file();
    final result = await attach(entity, segmentedVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    final input = {
      'bindingId': result['bindingId'],
      'requestId': 'idempotent-align',
      'anchors': <Object?>[]
    };
    final first = await f.legacyAlignment(input);
    final same = await f.call('danmaku.align', input);
    expect(same['jobId'], first['jobId']);
    final job = await f.wait(first['jobId'] as String, JobState.needsDecision);
    final option = job.decision!.options.single;
    await f.call(option.call.actionId, option.call.input);
    await f.wait(job.jobId, JobState.succeeded);
    expect((await f.call('danmaku.align', input))['jobId'], first['jobId']);
  });
  test(
      'export verifies original and mapped data in an authorized folder and rejects overwrite or escape',
      () async {
    final entity = await f.file();
    final result = await attach(entity, segmentedVideo);
    await f.wait(result['jobId'] as String, JobState.succeeded);
    final id = result['bindingId'] as String;
    f.service.exporter = DanmakuExporter(f.service.store, (path) async {
      final real = await Directory(path).resolveSymbolicLinks();
      if (real != await f.root.resolveSymbolicLinks()) {
        throw const Failure(
            FailureCode.unavailable, 'Outside synthetic authorized root.');
      }
      return real;
    });
    await f.call(
        'danmaku.offset', {'bindingId': id, 'revision': 0, 'offsetMs': 500});
    for (final view in ['raw', 'mapped']) {
      final path = '${f.root.path}/$view.json';
      final exported = await f.call(
          'danmaku.export', {'bindingId': id, 'path': path, 'view': view});
      expect(exported['count'], 2);
      expect((exported['sha256'] as String).length, 64);
      final data = jsonDecode(await File(path).readAsString()) as Map;
      final entry = (data['comments'] as List).first as Map;
      expect(entry['sourceTimeMs'], 1000);
      if (view == 'mapped') expect(entry['time'], .5);
      final repeated = await f.harness.invokeJson(
          'danmaku.export',
          {'bindingId': id, 'path': path, 'view': view},
          Invocation(origin: 'gui'));
      expect((repeated as Failed).failure.code, FailureCode.conflict);
    }
    final escape = await f.harness.invokeJson(
        'danmaku.export',
        {
          'bindingId': id,
          'path': '${Directory.systemTemp.path}/escape-danmaku.json',
          'view': 'raw'
        },
        Invocation(origin: 'gui'));
    expect((escape as Failed).failure.code, FailureCode.unavailable);
  });
}
