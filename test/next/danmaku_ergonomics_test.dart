import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'danmaku_test_support.dart';

const anchors = [
  {'sourceTimeMs': 140000, 'mediaTimeMs': 138100, 'evidence': 'late event'},
  {'sourceTimeMs': 10000, 'mediaTimeMs': 8000, 'evidence': 'early event'},
  {'sourceTimeMs': 80000, 'mediaTimeMs': 77900, 'evidence': 'middle event'}
];

void main() {
  late DanmakuFixture f;
  setUp(() async {
    f = DanmakuFixture();
    await f.open();
  });
  tearDown(() => f.close());
  Future<String> binding() async => f.service.store.attach(await f.file(),
      segmentedVideo, 'synthetic evidence', null, Invocation(origin: 'mcp'));
  Future<JsonMap> snapshot() async => {
        for (final table in [
          'danmaku_bindings',
          'danmaku_binding_events',
          'danmaku_cache_chunks',
          'danmaku_alignment_candidates',
          'jobs',
          'job_events',
          'media_entities',
          'media_locations'
        ])
          table: await f.jobs.database.query(table)
      };
  Future<JsonMap> envelope(String action, JsonMap input) async =>
      (await f.harness.invokeJson(action, input, Invocation(origin: 'mcp')))
          .toEnvelope();

  test(
      'alignment analysis is read-only and one update accepts a different estimate',
      () async {
    final id = await binding();
    final before = await snapshot();
    final analysis = await f.call(
        'danmaku.analyze_alignment', {'bindingId': id, 'anchors': anchors});
    expect(analysis['estimateOffsetMs'], 2000);
    expect(analysis['anchorOffsetsMs'], [1900, 2000, 2100]);
    expect(analysis['residualsMs'], [100, 0, 100]);
    expect(analysis['maxResidualMs'], 100);
    expect(analysis['anchorSpanMs'], 130000);
    expect(analysis['evidence'], ['late event', 'early event', 'middle event']);
    expect(analysis['confidence'], 'consistentAnchors');
    expect(analysis['observedRevision'], 0);
    expect(analysis['currentOffsetMs'], 0);
    expect(await snapshot(), before);
    expect(f.host.requests, isEmpty);
    final updated = await f.call('danmaku.update', {
      'changes': [
        {
          'bindingId': id,
          'expectedRevision': analysis['observedRevision'],
          'offsetMs': 900,
          'reason': '根据片头后锚点修正'
        }
      ]
    });
    final item = (updated['results'] as List).single as Map;
    expect(item['status'], 'completed');
    expect(item['result']['offsetMs'], 900);
    expect(item['result']['revision'], 1);
    expect((await f.service.store.binding(id))['offset_ms'], 900);
    expect(await f.jobs.list(), isEmpty);
    expect(
        await f.jobs.database.query('danmaku_alignment_candidates'), isEmpty);
    final events = await f.jobs.database.query('danmaku_binding_events',
        where: 'binding_id = ?', whereArgs: [id], orderBy: 'revision');
    final audit = jsonDecode(events.last['payload'] as String) as Map;
    expect(audit['reason'], '根据片头后锚点修正');
    expect(audit['actor'], 'agent');
    expect(audit['origin'], 'mcp');
  });

  test('empty inconsistent and even anchor sets expose evidence limits',
      () async {
    final id = await binding();
    final empty = await f
        .call('danmaku.analyze_alignment', {'bindingId': id, 'anchors': []});
    expect(empty['estimateOffsetMs'], isNull);
    expect(empty['maxResidualMs'], isNull);
    expect(empty['anchorOffsetsMs'], isEmpty);
    expect(empty['anchorSpanMs'], 0);
    expect(empty['confidence'], 'insufficientEvidence');
    expect(empty['limitations'], isNotEmpty);
    final even = await f.call('danmaku.analyze_alignment', {
      'bindingId': id,
      'anchors': [
        {'sourceTimeMs': 1000, 'mediaTimeMs': 2000, 'evidence': 'negative'},
        {'sourceTimeMs': 2000, 'mediaTimeMs': 1000, 'evidence': 'positive'}
      ]
    });
    expect(even['estimateOffsetMs'], 1000);
    expect(even['residualsMs'], [2000, 0]);
    expect(even['confidence'], 'insufficientEvidence');
    final inconsistent = await f.call('danmaku.analyze_alignment', {
      'bindingId': id,
      'anchors': [
        ...anchors.take(2),
        {'sourceTimeMs': 80000, 'mediaTimeMs': 50000, 'evidence': 'outlier'}
      ]
    });
    expect(inconsistent['maxResidualMs'], 28000);
    expect(inconsistent['confidence'], 'insufficientEvidence');
    final tooMany = await envelope('danmaku.analyze_alignment',
        {'bindingId': id, 'anchors': List.filled(101, anchors.first)});
    expect(tooMany['error'], containsPair('code', 'invalid_input'));
    final missing = await envelope(
        'danmaku.analyze_alignment', {'bindingId': 'missing', 'anchors': []});
    expect(missing['error'], containsPair('code', 'not_found'));
    expect(await f.jobs.list(), isEmpty);
  });

  test('batch changes are atomic per binding and retain ordered failures',
      () async {
    final id = await binding();
    final other = await f.service.store.attach(
        await f.identities.ensureFile('/fixture/other.mkv'),
        ddpVideo,
        'synthetic',
        null,
        Invocation(origin: 'mcp'));
    final updated = await f.call('danmaku.update', {
      'changes': [
        {
          'bindingId': id,
          'expectedRevision': 0,
          'enabled': false,
          'displayFold': false,
          'offsetMs': -321
        },
        {
          'bindingId': id,
          'expectedRevision': 0,
          'enabled': true,
          'offsetMs': 42
        },
        {'bindingId': 'missing', 'expectedRevision': 0, 'offsetMs': 8},
        {'bindingId': other, 'expectedRevision': 0, 'offsetMs': 7200001},
        {'bindingId': id, 'expectedRevision': 1},
        {'bindingId': other, 'offsetMs': 12},
        {'bindingId': id, 'expectedRevision': 1, 'offsetMs': 0}
      ]
    });
    final results = updated['results'] as List;
    expect(results.map((r) => r['index']), [0, 1, 2, 3, 4, 5, 6]);
    expect(results.map((r) => r['status']), [
      'completed',
      'failed',
      'failed',
      'completed',
      'failed',
      'failed',
      'completed'
    ]);
    expect(results[1]['error']['code'], 'conflict');
    expect(results[2]['error']['code'], 'not_found');
    expect(results[4]['error']['code'], 'invalid_input');
    expect(results[5]['error']['code'], 'invalid_input');
    final current = await f.service.store.binding(id);
    expect(current['revision'], 2);
    expect(current['offset_ms'], 0);
    expect(current['enabled'], 0);
    expect(current['deduplicate'], 0);
    expect((await f.service.store.binding(other))['offset_ms'], 7200001);
    for (final changes in [
      <Object?>[],
      List.filled(101, {'bindingId': id, 'offsetMs': 0})
    ]) {
      expect((await envelope('danmaku.update', {'changes': changes}))['error'],
          containsPair('code', 'invalid_input'));
    }
    for (final bad in [
      {'bindingId': id, 'trackId': 'both', 'enabled': true},
      {'enabled': true},
      {'bindingId': id, 'expectedRevision': 2, 'offsetMs': 1.5},
      {'bindingId': id, 'expectedRevision': 2, 'offsetMs': 'later'},
      {'bindingId': id, 'expectedRevision': 2, 'enabled': 'false'}
    ]) {
      expect(
          (await envelope('danmaku.update', {
            'changes': [bad]
          }))['error'],
          containsPair('code', 'invalid_input'));
    }
  });

  test('unbound current tracks support enabled offset and display folding',
      () async {
    await f.file();
    f.player.classicTracks.add({
      'trackId': 'local',
      'enabled': true,
      'offsetMs': 0,
      'deduplicate': true,
      'platform': 'unknown',
      'platformVideoId': null,
      'origin': 'local_file'
    });
    final updated = await f.call('danmaku.update', {
      'changes': [
        {
          'trackId': 'local',
          'enabled': false,
          'offsetMs': -1234,
          'displayFold': false
        },
        {'trackId': 'local', 'expectedRevision': 0, 'enabled': true},
        {'trackId': 'missing', 'enabled': false}
      ]
    });
    final results = updated['results'] as List;
    expect(results.first['result'], containsPair('persistence', 'playback'));
    expect(f.player.classicTracks.single['enabled'], isFalse);
    expect(f.player.classicTracks.single['offsetMs'], -1234);
    expect(f.player.classicTracks.single['deduplicate'], isFalse);
    expect(results[1]['error']['code'], 'invalid_input');
    expect(results[2]['error']['code'], 'not_found');
    expect(await f.jobs.database.query('danmaku_bindings'), isEmpty);
    expect(await f.jobs.list(), isEmpty);
    expect(f.host.requests, isEmpty);
    expect(
        ((await f.call('danmaku.tracks', {}))['tracks'] as List)
            .single['displayFold'],
        isFalse);
  });

  test('bound track updates use binding revision and survive restart',
      () async {
    await f.file();
    f.player.classicTracks.add({
      'trackId': 'dandanplay',
      'enabled': true,
      'offsetMs': 0,
      'deduplicate': true,
      'source': 'dandanplay',
      'platform': 'dandanplay',
      'platformVideoId': ddpVideo.videoId,
      'origin': 'auto_remote'
    });
    final attached = await f.call('danmaku.attach', {
      'video': ddpVideo.toJson(),
      'reason': 'synthetic',
      'requestId': 'reuse'
    });
    final id = attached['bindingId'] as String;
    final updated = await f.call('danmaku.update', {
      'changes': [
        {
          'trackId': 'dandanplay',
          'expectedRevision': 0,
          'offsetMs': 987,
          'enabled': false,
          'displayFold': false
        },
        {'trackId': 'dandanplay', 'expectedRevision': 0, 'offsetMs': 1}
      ]
    });
    final results = updated['results'] as List;
    expect(results.first['result']['bindingId'], id);
    expect(results.first['result']['revision'], 1);
    expect(results[1]['error']['code'], 'conflict');
    await f.reopen();
    await f.service.refreshCurrent();
    final current = await f.service.store.binding(id);
    expect(current['offset_ms'], 987);
    expect(current['enabled'], 0);
    expect(current['deduplicate'], 0);
    expect(f.host.requests, isEmpty);
  });

  test(
      'legacy queued alignment completes analysis without producing a Decision',
      () async {
    final id = await binding();
    final job = await f.engine.submit(
        type: 'danmaku.align',
        title: 'Legacy queued',
        input: {
          'bindingId': id,
          'bindingRevision': 0,
          'anchors': anchors,
          'requestId': 'queued'
        });
    final done = await f.wait(job.jobId, JobState.succeeded);
    expect(done.decision, isNull);
    expect(done.receipt!.details['analysis'],
        containsPair('estimateOffsetMs', 2000));
    expect(done.receipt!.details['applied'], isFalse);
    expect(done.receipt!.details['migration'],
        'danmaku.analyze_alignment + danmaku.update');
    expect((await f.service.store.binding(id))['revision'], 0);
    final events = await f.jobs.events(job.jobId);
    expect(events.any((e) => e.snapshot['state'] == 'needs_decision'), isFalse);
  });

  test(
      'legacy proposed checkpoint recovers to analysis without changing binding',
      () async {
    final id = await binding();
    final saved = await f.legacyAlignment(
        {'bindingId': id, 'anchors': anchors, 'requestId': 'interrupted'},
        state: JobState.interrupted);
    await f.reopen();
    final done = await f.wait(saved['jobId'] as String, JobState.succeeded);
    expect(done.receipt!.details['analysis'],
        containsPair('estimateOffsetMs', 2000));
    expect((await f.service.store.binding(id))['offset_ms'], 0);
    expect(done.sideEffectCommitted, isTrue);
    expect(done.decision, isNull);
  });

  test('retired align rejects new tasks with an explicit migration', () async {
    final id = await binding();
    final rejected = await envelope('danmaku.align',
        {'bindingId': id, 'anchors': anchors, 'requestId': 'new'});
    expect(rejected['error'], containsPair('code', 'unavailable'));
    expect((rejected['error'] as Map)['message'],
        contains('danmaku.analyze_alignment'));
    expect((rejected['error'] as Map)['message'], contains('danmaku.update'));
    expect(await f.jobs.list(), isEmpty);
    expect(
        await f.jobs.database.query('danmaku_alignment_candidates'), isEmpty);
  });

  test('legacy committed apply checkpoint recovers without a second write',
      () async {
    final id = await binding();
    await f.call(
        'danmaku.offset', {'bindingId': id, 'revision': 0, 'offsetMs': 2000});
    final saved = await f.legacyAlignment(
        {'bindingId': id, 'anchors': anchors, 'requestId': 'committed'},
        state: JobState.interrupted,
        choice: 'apply',
        candidateState: 'applied');
    final before = await f.jobs.database.query('danmaku_binding_events');
    await f.reopen();
    final done = await f.wait(saved['jobId'] as String, JobState.succeeded);
    expect(done.receipt!.details['applied'], isTrue);
    expect((await f.service.store.binding(id))['revision'], 1);
    expect((await f.service.store.binding(id))['offset_ms'], 2000);
    expect(await f.jobs.database.query('danmaku_binding_events'), before);
  });
}
