import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/media_capability.dart';

import 'media_test_support.dart';

final class _Calls implements InvocationObserver {
  final List<InvocationRecord> records = [];
  @override
  void onInvocation(InvocationRecord record) => records.add(record);
}

const _workRef = {
  'provider': 'tmdb',
  'objectType': 'tv',
  'externalId': '9001',
  'scope': ''
};
const _releaseRef = {
  'provider': 'tmdb',
  'objectType': 'season',
  'externalId': '9101',
  'scope': 'tv/9001/season/1'
};

void main() {
  late MediaFixture f;
  setUp(() async {
    f = MediaFixture();
    await f.open();
  });
  tearDown(() => f.close());

  test(
      'one Release judgment binds all 48 Changan files with constant Action and catalogue calls',
      () async {
    final season = f.tmdb.responses['/3/tv/9001/season/1'] as Map;
    season['episodes'] = [
      for (var i = 1; i <= 48; i++)
        {
          'id': 9200 + i,
          'name': '第 $i 集',
          'season_number': 1,
          'episode_number': i,
          'air_date': '2019-06-27',
          'overview': '离线合成目录'
        }
    ];
    final tv = f.tmdb.responses['/3/tv/9001'] as Map;
    (tv['seasons'] as List).single['episode_count'] = 48;
    final directory = await Directory(
            "${f.media.path}/长安十二时辰/长安十二时辰.The.Longest.Day.In.Chang'an.2019.S01.2160p.IQ.WEB-DL.HEVC.AAC-ZmWeb")
        .create(recursive: true);
    for (var i = 1; i <= 48; i++) {
      await File(
              "${directory.path}/长安十二时辰.The.Longest.Day.In.Chang'an.2019.S01E${i.toString().padLeft(2, '0')}.2160p.IQ.WEB-DL.HEVC.AAC-ZmWeb.mp4")
          .writeAsString('offline episode $i');
    }
    await File('${directory.path}/notes.xml').writeAsString('not a video');
    final calls = _Calls();
    f.harness = Harness([MediaCapability(f.service), TaskCapability(f.engine)],
        observers: [calls]);
    final input = {
      'root': directory.path,
      'workRef': _workRef,
      'releaseRef': _releaseRef,
      'numberSource': 'sxxeyy',
      'requestId': 'changan-48',
      'reason': '确认 2019 长安十二时辰第一季，全季使用 SxxEyy'
    };
    final result = await f.call('media.identification.apply_release', input);
    final jobId = (result['job'] as Map)['jobId'] as String;
    final job = await waitForJob(f.engine, jobId, JobState.succeeded);
    expect(job.receipt!.verification, VerificationLevel.verified);
    expect(job.receipt!.details, containsPair('bound', 48));
    expect(job.receipt!.details, containsPair('needsDecision', 0));
    expect(job.receipt!.details, containsPair('failed', 0));
    expect(job.receipt!.details, containsPair('complete', true));
    expect(calls.records.map((r) => r.actionId),
        ['media.identification.apply_release']);
    expect(f.tmdb.requests.map((r) => r['path']),
        ['/3/tv/9001', '/3/tv/9001/season/1']);
    expect(await f.jobs.database.query('jobs'), hasLength(1));
    final work = (await f.identities.library()).single;
    final release = (work['releases'] as List).single as Map;
    expect(release['episodes'], hasLength(48));
    for (final episode in release['episodes'] as List) {
      final file = (episode['files'] as List).single as Map;
      final identity = await f.identities.identity(file['id'] as String);
      final binding = (identity['bindings'] as List).single as Map;
      expect(
          binding['external_id'],
          (9200 + int.parse(episode['attributes']['number'] as String))
              .toString());
      expect(binding['bound_by'], 'automatic');
      expect(binding['invocation_id'], calls.records.single.invocationId);
    }
    final releaseBindings = await f.jobs.database.query('media_bindings',
        where: 'entity_id = ? AND source = ?',
        whereArgs: [release['id'], 'release_judgment']);
    expect(releaseBindings.single['bound_by'], 'agent');
    expect(f.classic.applications, 0);
    final repeated = await f.call('media.identification.apply_release', input);
    expect((repeated['job'] as Map)['jobId'], jobId);
    expect(f.tmdb.requests, hasLength(2));
    expect(await f.jobs.database.query('media_file_episodes'), hasLength(48));
  });

  test(
      'only uncertain files produce individual executable Decisions and batch reports partial success',
      () async {
    await f.file('Show.S01E01.2160p.mkv');
    await f.file('Show.S02E02.1080p.mkv');
    await f.file('[Group] Show - 02 [1080p].mkv');
    await f.file('Show.S01E99.4K.mkv');
    final result = await f.call(
        'media.identification.apply_release',
        {
          'root': f.media.path,
          'workRef': _workRef,
          'releaseRef': _releaseRef,
          'numberSource': 'sxxeyy',
          'requestId': 'uncertain',
          'reason': '第一季'
        },
        origin: 'gui');
    final batch = await waitForJob(f.engine,
        (result['job'] as Map)['jobId'] as String, JobState.succeeded);
    expect(batch.receipt!.details['bound'], 1);
    expect(batch.receipt!.details['needsDecision'], 3);
    expect(batch.receipt!.details['complete'], false);
    for (final row in (batch.receipt!.details['files'] as List)
        .where((r) => r['state'] == 'needs_decision')) {
      final child = await waitForJob(
          f.engine, row['jobId'] as String, JobState.needsDecision);
      for (final option in child.decision!.options) {
        expect(
            f.harness
                .lookup(option.call.actionId)!
                .spec
                .input
                .validate(option.call.input),
            isEmpty);
      }
      final view =
          await f.call('media.identification.get', {'jobId': child.jobId});
      expect(view['attempts'], hasLength(1));
    }
    expect(f.tmdb.requests, hasLength(2));
    final releaseId = batch.receipt!.details['releaseId'] as String;
    final bindings = await f.jobs.database.query('media_bindings',
        where: 'entity_id = ?', whereArgs: [releaseId]);
    expect(bindings.single['bound_by'], 'user');
    final next = await f.call('media.identification.apply_release', {
      'root': f.media.path,
      'releaseId': releaseId,
      'numberSource': 'filename',
      'requestId': 'animation-format',
      'reason': '允许明确动画编号'
    });
    final reused = await waitForJob(
        f.engine, (next['job'] as Map)['jobId'] as String, JobState.succeeded);
    expect(reused.receipt!.details['bound'], 2);
    expect(reused.receipt!.details['needsDecision'], 2);
    expect(f.tmdb.requests, hasLength(2));
  });

  test(
      'batch correction revokes old identities and repairs only obsolete Dandanplay projection',
      () async {
    await f.reopen(sources: ['tmdb', 'dandanplay']);
    final fileId = await f.file('Show.S01E01.2160p.mkv');
    final initial = await f.service.identify(fileId, sources: ['dandanplay']);
    await waitForJob(f.engine, initial.jobId, JobState.succeeded);
    final location =
        (await f.identities.locations(fileId)).single['locator'] as String;
    expect(f.classic.rows[location]!['animeId'], 7001);
    f.classic.rows[location]!['lastPosition'] = 12345;
    final corrected = await f.call('media.identification.apply_release', {
      'root': f.media.path,
      'workRef': _workRef,
      'releaseRef': _releaseRef,
      'numberSource': 'sxxeyy',
      'requestId': 'correct',
      'reason': '整季纠正为 TMDB'
    });
    final batch = await waitForJob(f.engine,
        (corrected['job'] as Map)['jobId'] as String, JobState.succeeded);
    expect(batch.receipt!.details['bound'], 1);
    final identity = await f.identities.identity(fileId);
    final bindings = identity['bindings'] as List;
    expect(bindings.where((b) => b['status'] == 'revoked').single['provider'],
        'dandanplay');
    expect(
        bindings.where((b) => b['status'] == 'accepted').single['external_id'],
        '9201');
    expect(f.classic.rows[location]!['animeName'], '');
    expect(f.classic.rows[location]!['lastPosition'], 12345);
    expect(await f.identities.pendingProjections(), isEmpty);
  });

  test('batch recovery reuses committed file bindings and the cached catalogue',
      () async {
    await f.file('Show.S01E01.2160p.mkv');
    await f.file('Show.S01E02.2160p.mkv');
    final submitted = await f.call('media.identification.apply_release', {
      'root': f.media.path,
      'workRef': _workRef,
      'releaseRef': _releaseRef,
      'numberSource': 'sxxeyy',
      'requestId': 'recover',
      'reason': '第一季'
    });
    final batch = await waitForJob(f.engine,
        (submitted['job'] as Map)['jobId'] as String, JobState.succeeded);
    final before = await f.jobs.database.query('media_bindings');
    // Reproduce a crash after file commit but before persisting the batch result.
    final now = DateTime.now().toUtc();
    final interrupted = Job.fromJson({
      ...batch.toStorageJson(),
      'state': 'interrupted',
      'revision': batch.revision + 1,
      'updatedAt': now.toIso8601String(),
      'receipt': null,
      'checkpoint': {...batch.checkpoint, 'results': []}
    });
    await f.jobs.commit(
        interrupted,
        JobEvent(
            jobId: batch.jobId,
            revision: interrupted.revision,
            kind: 'fixture_interrupted',
            at: now,
            snapshot: interrupted.toJson()),
        expectedRevision: batch.revision);
    await f.reopen();
    final recovered =
        await waitForJob(f.engine, batch.jobId, JobState.succeeded);
    expect(recovered.receipt!.details['bound'], 2);
    expect(await f.jobs.database.query('media_bindings'), before);
    expect(f.tmdb.requests, hasLength(2));
    expect(await f.jobs.database.query('media_file_episodes'), hasLength(2));
  });

  test('cancelled Release lookup does not fetch a season or create identities',
      () async {
    await f.file('Show.S01E01.2160p.mkv');
    f.tmdb.entered = Completer<void>();
    f.tmdb.release = Completer<void>();
    addTearDown(() {
      if (!f.tmdb.release!.isCompleted) f.tmdb.release!.complete();
    });
    final result = await f.call('media.identification.apply_release', {
      'root': f.media.path,
      'workRef': _workRef,
      'releaseRef': _releaseRef,
      'numberSource': 'sxxeyy',
      'requestId': 'cancel',
      'reason': '第一季'
    });
    final jobId = (result['job'] as Map)['jobId'] as String;
    await f.tmdb.entered!.future;
    await f.engine.cancel(jobId);
    f.tmdb.release!.complete();
    final cancelled = await waitForJob(f.engine, jobId, JobState.cancelled);
    expect(cancelled.receipt!.details['bound'], 0);
    expect(f.tmdb.requests, hasLength(1));
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
  });

  test('duplicate catalogue numbering and missing numbers require decisions',
      () async {
    final season = f.tmdb.responses['/3/tv/9001/season/1'] as Map;
    final episodes = season['episodes'] as List;
    episodes.add({...episodes.first as Map, 'id': 9299, 'name': '同号目录项'});
    await f.file('Show.S01E01.2160p.mkv');
    await f.file('Show.S01E02.2160p.mkv');
    await f.file('Show.2160p.HEVC.mkv');
    final result = await f.call('media.identification.apply_release', {
      'root': f.media.path,
      'workRef': _workRef,
      'releaseRef': _releaseRef,
      'numberSource': 'sxxeyy',
      'requestId': 'ambiguous',
      'reason': '第一季'
    });
    final batch = await waitForJob(f.engine,
        (result['job'] as Map)['jobId'] as String, JobState.succeeded);
    expect(batch.receipt!.details['bound'], 1);
    expect(batch.receipt!.details['needsDecision'], 2);
    for (final row in (batch.receipt!.details['files'] as List)
        .where((r) => r['state'] == 'needs_decision')) {
      await waitForJob(
          f.engine, row['jobId'] as String, JobState.needsDecision);
    }
    expect(f.tmdb.requests, hasLength(2));
  });

  test(
      'expected file failure remains queryable before any parsed context exists',
      () async {
    final id = await f.identities.ensureFile('${f.media.path}/gone.S01E01.mkv');
    final job = await f.service.identify(id);
    final failed = await waitForJob(f.engine, job.jobId, JobState.failed);
    expect(failed.error!.code, FailureCode.notFound);
    final view = await f.call('media.identification.get', {'jobId': job.jobId});
    expect(view['state'], 'failed');
    expect(view['error'], containsPair('code', 'not_found'));
    expect(view.containsKey('signals'), false);
    expect(view['candidates'], isEmpty);
    expect(await f.jobs.database.query('media_identifications'), isEmpty);
  });

  test(
      'identification queries return progress for queued files and stable errors for missing or wrong task types',
      () async {
    f.tmdb.entered = Completer<void>();
    f.tmdb.release = Completer<void>();
    addTearDown(() {
      if (!f.tmdb.release!.isCompleted) f.tmdb.release!.complete();
    });
    final ids = [
      for (var i = 0; i < 8; i++) await f.file('Show-$i S01E01.mkv')
    ];
    final jobs = [for (final id in ids) await f.service.identify(id)];
    await f.tmdb.entered!.future;
    final before = await f.jobs.database.query('media_identifications');
    expect(before.length, lessThan(jobs.length));
    for (final job in jobs) {
      final view =
          await f.call('media.identification.get', {'jobId': job.jobId});
      expect(view['fileId'], job.input['fileId']);
      expect(view['state'], anyOf('queued', 'probing', 'pending'));
    }
    expect(await f.jobs.database.query('media_identifications'),
        hasLength(before.length));
    final missing = await f.harness.invokeJson('media.identification.get',
        {'jobId': 'missing'}, Invocation(origin: 'mcp')) as Failed;
    expect(missing.failure.code, FailureCode.notFound);
    final scan = await f.service.submit('media.scan', {'root': f.media.path});
    final wrong = await f.harness.invokeJson('media.identification.get',
        {'jobId': scan.jobId}, Invocation(origin: 'mcp')) as Failed;
    expect(wrong.failure.code, FailureCode.invalidInput);
    f.tmdb.release!.complete();
    for (final job in jobs) {
      await waitForJob(f.engine, job.jobId, JobState.needsDecision);
    }
  });
}
