import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_test_support.dart';

void main() {
  late MediaFixture f;
  setUp(() async {
    f = MediaFixture();
    await f.open(sources: ['tmdb', 'bangumi', 'dandanplay']);
  });
  tearDown(() => f.close());

  test(
      'v1 migration preserves existing Task Engine rows and appends identity tables',
      () async {
    final root = await Directory.systemTemp.createTemp('next-v1-');
    final db = await databaseFactoryFfi.openDatabase('${root.path}/next.db',
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, version) async {
              await db.execute(
                  'CREATE TABLE jobs(job_id TEXT PRIMARY KEY,type TEXT NOT NULL,state TEXT NOT NULL,revision INTEGER NOT NULL,created_at TEXT NOT NULL,snapshot TEXT NOT NULL)');
              await db.execute(
                  'CREATE TABLE job_events(job_id TEXT NOT NULL REFERENCES jobs(job_id),revision INTEGER NOT NULL,kind TEXT NOT NULL,at TEXT NOT NULL,snapshot TEXT NOT NULL,PRIMARY KEY(job_id,revision))');
            }));
    final now = DateTime.utc(2026, 10, 10);
    final job = Job(
        jobId: 'preexisting-download',
        type: 'download',
        title: 'Existing',
        state: JobState.queued,
        phase: 'queued',
        progress: JobProgress(completed: 0, unit: 'bytes'),
        createdAt: now,
        updatedAt: now,
        ownerDeviceId: 'device',
        revision: 0);
    await db.insert('jobs', {
      'job_id': job.jobId,
      'type': job.type,
      'state': 'queued',
      'revision': 0,
      'created_at': now.toIso8601String(),
      'snapshot': jsonEncode(job.toStorageJson())
    });
    await db.insert('job_events', {
      'job_id': job.jobId,
      'revision': 0,
      'kind': 'submitted',
      'at': now.toIso8601String(),
      'snapshot': jsonEncode(job.toJson())
    });
    await db.close();
    final upgraded =
        await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    expect(
        (await upgraded.get(job.jobId))!.toStorageJson(), job.toStorageJson());
    expect(await upgraded.events(job.jobId), hasLength(1));
    expect(await upgraded.database.getVersion(), 2);
    expect(await upgraded.database.query('media_entities'), isEmpty);
    await upgraded.close();
    await root.delete(recursive: true);
  });

  test(
      'history imports remain unknown-provenance evidence and never become accepted identities',
      () async {
    final path = '${f.media.path}/legacy.mkv';
    f.classic.rows[path] = {
      'filePath': path,
      'animeName': '',
      'episodeTitle': null,
      'animeId': 7001,
      'episodeId': 7101,
      'videoHash': null,
      'watchProgress': 0.7,
      'lastPosition': 7000
    };
    await f.call('media.library.import_history', {});
    await f.call('media.library.import_history', {});
    final files = await f.jobs.database
        .query('media_entities', where: 'kind = ?', whereArgs: ['file']);
    expect(files, hasLength(1));
    final identity = (await f.call(
            'media.identity.get', {'entityId': files.single['id']}))['identity']
        as Map;
    expect(identity['bindings'], isEmpty);
    expect((identity['legacyEvidence'] as List).single['provenance'],
        'legacy_unknown');
    expect((await f.call('media.library.works', {}))['works'], isEmpty);
    expect(f.classic.rows[path]!['lastPosition'], 7000);
    expect(await f.jobs.database.query('media_legacy_history'), hasLength(1));
  });

  test(
      'TMDB-only identification yields a durable executable Decision and a Next library work with a complete catalogue',
      () async {
    final fileId = await f.file('长安十二时辰 S01E01.mkv');
    final accepted = await f.service.identify(fileId, sources: ['tmdb']);
    final decision =
        await waitForJob(f.engine, accepted.jobId, JobState.needsDecision);
    final queried =
        await f.call('media.identification.get', {'jobId': decision.jobId});
    expect(queried['candidates'], hasLength(1));
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
    for (final option in decision.decision!.options) {
      expect(
          f.harness
              .lookup(option.call.actionId)!
              .spec
              .input
              .validate(option.call.input),
          isEmpty);
    }
    await f.reopen(sources: ['tmdb', 'bangumi', 'dandanplay']);
    final persisted = await f.engine.get(decision.jobId);
    expect(persisted.decision!.toJson(), decision.decision!.toJson());
    await f.choose(persisted);
    final result = await f.call('media.library.works', {'query': '长安'});
    final work = (result['works'] as List).single as Map;
    final release = (work['releases'] as List).single as Map;
    expect(release['episodes'], hasLength(2));
    expect(
        ((release['episodes'] as List).first['files'] as List).single['fileId'],
        fileId);
    expect((release['episodes'] as List).last['files'], isEmpty);
    expect(
        (work['metadata'] as List).any((field) => field['field'] == 'imageUrl'),
        isTrue);
    await f.call('media.library.work', {'workId': work['workId']});
    final identity = (await f
        .call('media.identity.get', {'entityId': fileId}))['identity'] as Map;
    expect((identity['bindings'] as List).single['boundBy'], 'agent');
    expect((identity['bindings'] as List).single['ref']['provider'], 'tmdb');
    expect(f.classic.applications, 0);
    expect((await f.engine.get(decision.jobId)).receipt!.verification,
        VerificationLevel.verified);
  });

  test(
      'host provenance cannot be supplied as an input and GUI choices record user independently of confidence',
      () async {
    final fileId = await f.file('长安十二时辰 S01E01.mkv');
    final queued = await f.service.identify(fileId, sources: ['tmdb']);
    final job =
        await waitForJob(f.engine, queued.jobId, JobState.needsDecision);
    final call = job.decision!.options.first.call;
    final forged = await f.harness.invokeJson(
        call.actionId,
        {...call.input, 'boundBy': 'user'},
        Invocation(origin: 'mcp')) as Failed;
    expect(forged.failure.code, FailureCode.invalidInput);
    await f.choose(job, origin: 'gui');
    final identity = (await f
        .call('media.identity.get', {'entityId': fileId}))['identity'] as Map;
    expect((identity['bindings'] as List).single['boundBy'], 'user');
    expect((identity['evidence'] as List).single['reason'],
        contains('confirmation'));
    final stale = await f.harness.invokeJson(
        call.actionId, call.input, Invocation(origin: 'mcp')) as Failed;
    expect(stale.failure.code, FailureCode.conflict);
  });

  test(
      'Agent evidence explicitly maps absolute 13 to Bangumi subject episode 1 and cannot bypass catalogue membership',
      () async {
    final fileId = await f.file('Cour Sample Part 2 - 13.mkv');
    final queued = await f.service.identify(fileId, sources: ['bangumi']);
    var job = await waitForJob(f.engine, queued.jobId, JobState.needsDecision);
    final evidence = {
      'jobId': job.jobId,
      'revision': job.revision,
      'workRef': const ExternalRef('bangumi', 'subject', '8001').toJson(),
      'episodeIds': ['8101'],
      'reason':
          'Release is the second cour; filename absolute 13 maps to subject sort 1.',
      'url': 'https://example.invalid/verified-cour-map'
    };
    final bad = await f.harness.invokeJson(
        'media.identification.add_evidence',
        {
          ...evidence,
          'episodeIds': ['forged']
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(bad.failure.code, FailureCode.invalidInput);
    final added = await f.call('media.identification.add_evidence', evidence);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
    await f.call(
        'media.identification.reconsider', added['reconsider'] as JsonMap);
    job = await waitForJob(f.engine, job.jobId, JobState.needsDecision);
    await f.choose(job, candidateId: added['candidateId'] as String);
    final identity = (await f
        .call('media.identity.get', {'entityId': fileId}))['identity'] as Map;
    final binding = (identity['bindings'] as List).single;
    expect(binding['ref']['externalId'], '8101');
    expect(binding['source'], 'agent_evidence');
    expect((identity['evidence'] as List).single['url'], evidence['url']);
    final library = await f.call('media.library.works', {});
    final episodes = ((library['works'] as List).single['releases'] as List)
        .single['episodes'] as List;
    expect(episodes, hasLength(3));
    expect(
        episodes
            .where((ep) => ep['number'] == '1')
            .map((ep) => ep['type'])
            .toSet(),
        {'regular', 'special'});
  });

  test('file revision changes reject old choices without writing identities',
      () async {
    final fileId = await f.file('长安十二时辰 S01E01.mkv');
    final queued = await f.service.identify(fileId, sources: ['tmdb']);
    final job =
        await waitForJob(f.engine, queued.jobId, JobState.needsDecision);
    final location = (await f.identities.locations(fileId)).single;
    await File(location['locator'] as String).writeAsString('changed content');
    await f.service.index(location['locator'] as String);
    final call = job.decision!.options.first.call;
    final stale = await f.harness.invokeJson(
        call.actionId, call.input, Invocation(origin: 'mcp')) as Failed;
    expect(stale.failure.code, FailureCode.conflict);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
    final replacement = await f.service.identify(fileId, sources: ['tmdb']);
    expect(replacement.jobId, isNot(job.jobId));
    await waitForJob(f.engine, replacement.jobId, JobState.needsDecision);
  });

  test(
      'one file may cover multiple episodes and each episode may have multiple files',
      () async {
    final combined = await f.file('长安十二时辰 S01E01-E02.mkv');
    final q = await f.service.identify(combined, sources: ['tmdb']);
    await f.choose(await waitForJob(f.engine, q.jobId, JobState.needsDecision));
    final alternate = await f.file('长安十二时辰 S01E01 [alternate].mkv');
    final q2 = await f.service.identify(alternate, sources: ['tmdb']);
    await f
        .choose(await waitForJob(f.engine, q2.jobId, JobState.needsDecision));
    final combinedIdentity = (await f
        .call('media.identity.get', {'entityId': combined}))['identity'] as Map;
    expect(combinedIdentity['episodes'], hasLength(2));
    expect(
        (combinedIdentity['episodes'] as List)
            .every((ep) => ep['relation'] == 'combined'),
        isTrue);
    final library = await f.call('media.library.works', {});
    final episodes = ((library['works'] as List).single['releases'] as List)
        .single['episodes'] as List;
    expect(episodes.firstWhere((ep) => ep['number'] == '1')['files'],
        hasLength(2));
  });

  test(
      'unique hashOnly automatically binds and verifies Classic projection without changing progress',
      () async {
    final fileId = await f.file('Hash Sample S01E01.mkv');
    final path =
        (await f.identities.locations(fileId)).single['locator'] as String;
    f.classic.rows[path] = {
      'filePath': path,
      'lastPosition': 9000,
      'watchProgress': 0.9
    };
    final q = await f.service.identify(fileId, sources: ['dandanplay']);
    final completed = await waitForJob(f.engine, q.jobId, JobState.succeeded);
    expect(completed.receipt!.details['identified'], true);
    final identity = (await f
        .call('media.identity.get', {'entityId': fileId}))['identity'] as Map;
    expect((identity['bindings'] as List).single['boundBy'], 'automatic');
    expect((identity['bindings'] as List).single['source'], 'hashOnly');
    expect(f.classic.rows[path]!['animeId'], 7001);
    expect(f.classic.rows[path]!['episodeId'], 7101);
    expect(f.classic.rows[path]!['lastPosition'], 9000);
    expect(
        (await f.jobs.database.query('media_projection_outbox'))
            .single['state'],
        'delivered');
    expect(f.dandanplay.requests, hasLength(1));
  });

  test(
      'an accepted identity is reused without searching and duplicate submissions converge',
      () async {
    final fileId = await f.file('Hash Sample S01E01.mkv');
    final jobs = await Future.wait([
      f.service.identify(fileId, sources: ['dandanplay']),
      f.service.identify(fileId, sources: ['dandanplay'])
    ]);
    expect(jobs[0].jobId, jobs[1].jobId);
    await waitForJob(f.engine, jobs.first.jobId, JobState.succeeded);
    final requestCount = f.dandanplay.requests.length;
    final reused = await f.service.identify(fileId, sources: ['dandanplay']);
    await waitForJob(f.engine, reused.jobId, JobState.succeeded);
    expect(f.dandanplay.requests.length, requestCount);
  });

  test(
      'Classic projection failure remains pending and reboot repairs the committed identity',
      () async {
    final fileId = await f.file('Hash Sample S01E01.mkv');
    f.classic.rejectReadback = true;
    final q = await f.service.identify(fileId, sources: ['dandanplay']);
    final failed = await waitForJob(f.engine, q.jobId, JobState.failed);
    expect(failed.receipt!.verification, VerificationLevel.unverified);
    expect(await f.identities.pendingProjections(), hasLength(1));
    final bindings = await f.jobs.database
        .query('media_bindings', where: 'entity_id = ?', whereArgs: [fileId]);
    expect(bindings, hasLength(1));
    f.classic.rejectReadback = false;
    await f.reopen(sources: ['tmdb', 'bangumi', 'dandanplay']);
    await f.service.recoverProjections();
    final repair = (await f.engine.list(type: 'media.project')).single;
    await waitForJob(f.engine, repair.jobId, JobState.succeeded);
    expect(await f.identities.pendingProjections(), isEmpty);
    expect(
        await f.jobs.database.query('media_bindings',
            where: 'entity_id = ?', whereArgs: [fileId]),
        hasLength(1));
  });

  test(
      'metadata refresh updates fields and keeps user overrides and accepted identity untouched',
      () async {
    final fileId = await f.file('长安十二时辰 S01E01.mkv');
    final q = await f.service.identify(fileId, sources: ['tmdb']);
    await f.choose(await waitForJob(f.engine, q.jobId, JobState.needsDecision));
    final work = (await f.jobs.database
            .query('media_entities', where: 'kind = ?', whereArgs: ['work']))
        .single['id'] as String;
    final before = await f.jobs.database.query('media_bindings');
    await f.call('media.metadata.override',
        {'entityId': work, 'field': 'title', 'value': '我的标题'},
        origin: 'gui');
    final forbidden = await f.harness.invokeJson(
        'media.metadata.override',
        {'entityId': work, 'field': 'title', 'value': 'spoof'},
        Invocation(origin: 'mcp')) as Failed;
    expect(forbidden.failure.code, FailureCode.unavailable);
    (f.tmdb.responses['/3/tv/9001'] as Map)['overview'] =
        'Updated source overview';
    final refreshed = await f.call('media.metadata.refresh', {
      'ref': const ExternalRef('tmdb', 'tv', '9001').toJson(),
      'requestId': 'refresh-once'
    });
    final duplicate = await f.call('media.metadata.refresh', {
      'ref': const ExternalRef('tmdb', 'tv', '9001').toJson(),
      'requestId': 'refresh-once'
    });
    expect(
        (duplicate['job'] as Map)['jobId'], (refreshed['job'] as Map)['jobId']);
    await waitForJob(f.engine, (refreshed['job'] as Map)['jobId'] as String,
        JobState.succeeded);
    final metadata = await f.identities.mergedMetadata(work);
    expect((metadata['fields'] as Map)['title'], '我的标题');
    expect((metadata['fields'] as Map)['overview'], 'Updated source overview');
    expect(await f.jobs.database.query('media_bindings'), before);
  });

  test(
      'scan acceptance returns promptly, enumerates all files and schedules independent ambiguity jobs',
      () async {
    await File('${f.media.path}/长安十二时辰 S01E01.mkv').writeAsString('one');
    await File('${f.media.path}/长安十二时辰 S01E02.mkv').writeAsString('two');
    await File('${f.media.path}/skip.txt').writeAsString('ignore');
    final input = {
      'root': f.media.path,
      'requestId': 'scan-once',
      'sources': ['tmdb']
    };
    final accepted = await f.call('media.library.scan', input);
    final again = await f.call('media.library.scan', input);
    expect((again['job'] as Map)['jobId'], (accepted['job'] as Map)['jobId']);
    final job = await waitForJob(f.engine,
        (accepted['job'] as Map)['jobId'] as String, JobState.succeeded);
    expect(job.receipt!.details['discovered'], 2);
    expect(job.receipt!.details['identificationComplete'], false);
    for (final id in job.receipt!.details['identificationJobIds'] as List) {
      await waitForJob(f.engine, id as String, JobState.needsDecision);
    }
    expect(
        await f.jobs.database
            .query('media_entities', where: 'kind = ?', whereArgs: ['file']),
        hasLength(2));
  });

  test('filesystem access rejects unconfigured roots and escaping symlinks',
      () async {
    final outside = await Directory.systemTemp.createTemp('next-outside-');
    try {
      final denied = await f.harness.invokeJson(
          'media.library.scan',
          {'root': outside.path, 'requestId': 'outside'},
          Invocation(origin: 'mcp')) as Failed;
      expect(denied.failure.code, FailureCode.unavailable);
      final file =
          await File('${outside.path}/outside.mkv').writeAsString('outside');
      await Link('${f.media.path}/escape.mkv').create(file.path);
      await expectLater(f.service.index('${f.media.path}/escape.mkv'),
          throwsA(isA<Failure>()));
      expect(await f.engine.list(type: 'media.scan'), isEmpty);
    } finally {
      await outside.delete(recursive: true);
    }
  });

  test('skip and defer receipts explicitly retain unidentified status',
      () async {
    for (final disposition in ['skip', 'defer']) {
      final fileId = await f.file('Unknown $disposition.mkv');
      final q = await f.service.identify(fileId, sources: ['tmdb']);
      final job = await waitForJob(f.engine, q.jobId, JobState.needsDecision);
      final call = job.decision!.options
          .singleWhere((option) =>
              option.call.actionId == 'media.identification.$disposition')
          .call;
      await f.call(call.actionId, call.input);
      final completed =
          await waitForJob(f.engine, job.jobId, JobState.succeeded);
      expect(completed.receipt!.details['identified'], false);
      expect(completed.receipt!.details['disposition'], disposition);
    }
  });

  test(
      'retry deadlines and candidate checkpoints survive reboot without duplicate bindings',
      () async {
    final fileId = await f.file('长安十二时辰 S01E01.mkv');
    f.tmdb.retry = ProviderRetry(
        'tmdb',
        DateTime.now().toUtc().add(const Duration(milliseconds: 500)),
        'Fixture 429');
    final q = await f.service.identify(fileId, sources: ['tmdb']);
    await waitForJob(f.engine, q.jobId, JobState.waitingRetry);
    await f.reopen(sources: ['tmdb', 'bangumi', 'dandanplay']);
    final decision =
        await waitForJob(f.engine, q.jobId, JobState.needsDecision);
    expect(await f.identities.candidates(q.jobId), hasLength(1));
    await f.choose(decision);
    expect(
        await f.jobs.database.query('media_bindings',
            where: 'entity_id = ?', whereArgs: [fileId]),
        hasLength(1));
  });

  test(
      'cancellation while a provider is pending produces no identity or post-cancel writes',
      () async {
    final fileId = await f.file('长安十二时辰 S01E01.mkv');
    f.tmdb.entered = Completer<void>();
    f.tmdb.release = Completer<void>();
    final q = await f.service.identify(fileId, sources: ['tmdb']);
    await f.tmdb.entered!.future;
    await f.engine.cancel(q.jobId);
    f.tmdb.release!.complete();
    final cancelled = await waitForJob(f.engine, q.jobId, JobState.cancelled);
    expect(cancelled.receipt!.details['identified'], false);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
    expect(await f.identities.candidates(q.jobId), isEmpty);
  });

  test(
      'unbind revokes identity, repairs Classic fields and preserves evidence and progress',
      () async {
    final fileId = await f.file('Hash Sample S01E01.mkv');
    final path =
        (await f.identities.locations(fileId)).single['locator'] as String;
    f.classic.rows[path] = {'filePath': path, 'lastPosition': 9000};
    final q = await f.service.identify(fileId, sources: ['dandanplay']);
    await waitForJob(f.engine, q.jobId, JobState.succeeded);
    final result = await f.call(
        'media.identity.unbind', {'fileId': fileId, 'bindingRevision': 1});
    final identity = result['identity'] as Map;
    expect((identity['bindings'] as List).single['status'], 'revoked');
    expect(identity['evidence'], hasLength(1));
    expect(identity['episodes'], isEmpty);
    expect(f.classic.rows[path]!['animeName'], '');
    expect(f.classic.rows[path]!['lastPosition'], 9000);
  });

  test('read actions never persist snapshots, candidates, bindings or jobs',
      () async {
    await f
        .call('media.metadata.search', {'provider': 'tmdb', 'query': '长安十二时辰'});
    await f.call('media.metadata.get',
        {'ref': const ExternalRef('tmdb', 'tv', '9001').toJson()});
    await f
        .call('media.metadata.search', {'provider': 'bangumi', 'query': '季度'});
    await f.call('media.metadata.get',
        {'ref': const ExternalRef('bangumi', 'subject', '8001').toJson()});
    await f.call(
        'media.metadata.search', {'provider': 'dandanplay', 'query': '动画'});
    await f.call('media.metadata.get',
        {'ref': const ExternalRef('dandanplay', 'anime', '7001').toJson()});
    for (final table in [
      'media_snapshots',
      'media_candidates',
      'media_bindings',
      'jobs'
    ]) {
      expect(await f.jobs.database.query(table), isEmpty, reason: table);
    }
  });

  test(
      'an explicit accepted release enables unique filename-number binding without new provider queries',
      () async {
    final first = await f.file('长安十二时辰 S01E01.mkv');
    final q = await f.service.identify(first, sources: ['tmdb']);
    await f.choose(await waitForJob(f.engine, q.jobId, JobState.needsDecision));
    final release = (await f.jobs.database
            .query('media_entities', where: 'kind = ?', whereArgs: ['release']))
        .single['id'] as String;
    final next = await f.file('长安十二时辰 S01E02.mkv');
    final revision = (await f.identities.entity(next))['revision'];
    final before = f.tmdb.requests.length;
    final result = await f.call('media.identification.start', {
      'fileId': next,
      'fileRevision': revision,
      'sources': ['tmdb'],
      'releaseId': release
    });
    final job = await waitForJob(f.engine,
        (result['job'] as Map)['jobId'] as String, JobState.succeeded);
    expect(job.receipt!.details['identified'], true);
    expect(f.tmdb.requests.length, before);
    final identity = (await f
        .call('media.identity.get', {'entityId': next}))['identity'] as Map;
    expect((identity['bindings'] as List).single['source'], 'accepted_release');
    expect((identity['bindings'] as List).single['boundBy'], 'automatic');
  });

  test(
      'explicit requestId opens a new decision after defer without changing file content',
      () async {
    final fileId = await f.file('Unknown.mkv');
    final q = await f.service.identify(fileId, sources: ['tmdb']);
    final pending = await waitForJob(f.engine, q.jobId, JobState.needsDecision);
    final defer = pending.decision!.options
        .singleWhere(
            (option) => option.call.actionId == 'media.identification.defer')
        .call;
    await f.call(defer.actionId, defer.input);
    await waitForJob(f.engine, pending.jobId, JobState.succeeded);
    final resumed = await f.call('media.identification.start', {
      'fileId': fileId,
      'fileRevision': 0,
      'sources': ['tmdb'],
      'requestId': 'new-evidence'
    });
    expect((resumed['job'] as Map)['jobId'], isNot(pending.jobId));
    await waitForJob(f.engine, (resumed['job'] as Map)['jobId'] as String,
        JobState.needsDecision);
  });

  test(
      'hash conflicts remain proposals and cannot overwrite imported unknown-provenance matching',
      () async {
    final fileId = await f.file('Hash Sample S01E01.mkv');
    final path =
        (await f.identities.locations(fileId)).single['locator'] as String;
    f.classic.rows[path] = {
      'filePath': path,
      'animeId': 6001,
      'episodeId': 6101,
      'animeName': 'Other animation',
      'episodeTitle': 'Other episode',
      'videoHash': null
    };
    await f.call('media.library.import_history', {});
    final q = await f.service.identify(fileId, sources: ['dandanplay']);
    final job = await waitForJob(f.engine, q.jobId, JobState.needsDecision);
    final context =
        await f.call('media.identification.get', {'jobId': job.jobId});
    expect(
        (context['candidates'] as List).any(
            (candidate) => candidate['evidence']['reason'].contains('legacy')),
        isTrue);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
    expect(f.classic.applications, 0);
  });

  test(
      'pause fences candidate writes and resume reconciles the stored identification',
      () async {
    final fileId = await f.file('长安十二时辰 S01E01.mkv');
    f.tmdb.entered = Completer<void>();
    f.tmdb.release = Completer<void>();
    final q = await f.service.identify(fileId, sources: ['tmdb']);
    await f.tmdb.entered!.future;
    await f.engine.pause(q.jobId);
    f.tmdb.release!.complete();
    await f.engine.resume(q.jobId);
    final decision =
        await waitForJob(f.engine, q.jobId, JobState.needsDecision);
    expect(await f.identities.candidates(q.jobId), hasLength(1));
    await f.choose(decision);
  });

  test(
      'file content revision invalidates Dandanplay binding and clears its obsolete Classic projection',
      () async {
    final fileId = await f.file('Hash Sample S01E01.mkv');
    final q = await f.service.identify(fileId, sources: ['dandanplay']);
    await waitForJob(f.engine, q.jobId, JobState.succeeded);
    final path =
        (await f.identities.locations(fileId)).single['locator'] as String;
    await File(path).writeAsString('replaced content');
    await f.service.index(path);
    final identity = (await f
        .call('media.identity.get', {'entityId': fileId}))['identity'] as Map;
    expect(identity['revision'], 1);
    expect((identity['bindings'] as List).single['status'], 'revoked');
    expect(f.classic.rows[path]!['animeName'], '');
    expect(await f.identities.pendingProjections(), isEmpty);
  });

  test(
      'read provider retries are unavailable and retryable without leaking transport exceptions',
      () async {
    f.tmdb.retry =
        ProviderRetry('tmdb', DateTime.utc(2027), 'Fixture throttled');
    final outcome = await f.harness.invokeJson(
        'media.metadata.search',
        {'provider': 'tmdb', 'query': '长安'},
        Invocation(origin: 'mcp')) as Failed;
    expect(outcome.failure.code, FailureCode.unavailable);
    expect(outcome.failure.retryable, true);
  });

  test('restart reconciles committed identity despite a pending cancellation',
      () async {
    final fileId = await f.file('Hash Sample S01E01.mkv');
    f.classic.rejectReadback = true;
    final q = await f.service.identify(fileId, sources: ['dandanplay']);
    final failed = await waitForJob(f.engine, q.jobId, JobState.failed);
    expect(failed.sideEffectCommitted, true);
    final now = DateTime.now().toUtc();
    final interrupted = Job.fromJson({
      ...failed.toStorageJson(),
      'state': 'cancelling',
      'revision': failed.revision + 1,
      'updatedAt': now.toIso8601String(),
      'error': null,
      'receipt': null,
      'cancelRequestedAt': now.toIso8601String(),
      'cancelRequestedPhase': 'project',
      'cancelAfterCommit': true
    });
    await f.jobs.commit(
        interrupted,
        JobEvent(
            jobId: interrupted.jobId,
            revision: interrupted.revision,
            kind: 'fixture_crash',
            at: now,
            snapshot: interrupted.toJson()),
        expectedRevision: failed.revision);
    f.classic.rejectReadback = false;
    await f.reopen(sources: ['tmdb', 'bangumi', 'dandanplay']);
    final recovered = await waitForJob(f.engine, q.jobId, JobState.succeeded);
    expect(recovered.receipt!.details['identified'], true);
    expect(recovered.sideEffectCommitted, true);
    expect(recovered.cancelRequestedAt, isNotNull);
    expect(await f.identities.pendingProjections(), isEmpty);
    expect(
        await f.jobs.database.query('media_bindings',
            where: 'entity_id = ?', whereArgs: [fileId]),
        hasLength(1));
  });

  test(
      'queued identification cancellation does not start more provider requests',
      () async {
    f.tmdb.release = Completer<void>();
    final jobs = <Job>[];
    for (var i = 0; i < 8; i++) {
      final fileId = await f.file('长安十二时辰 S01E01 [$i].mkv');
      jobs.add(await f.service.identify(fileId, sources: ['tmdb']));
    }
    for (var i = 0; i < 100 && f.tmdb.requests.length < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(f.tmdb.requests, hasLength(4));
    for (final job in jobs.skip(4)) {
      await f.engine.cancel(job.jobId);
      await waitForJob(f.engine, job.jobId, JobState.cancelled);
    }
    expect(f.tmdb.requests, hasLength(4));
    f.tmdb.release!.complete();
    for (final job in jobs.take(4)) {
      await waitForJob(f.engine, job.jobId, JobState.needsDecision);
    }
  });
}
