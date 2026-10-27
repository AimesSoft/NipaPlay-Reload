import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/subtitles/episode_subtitles.dart';

import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaFixture f;
  late String file;
  setUp(() async {
    f = MediaFixture();
    await f.open();
    file = await f.file('shared.mkv');
    final db = f.jobs.database;
    for (final prefix in ['source', 'target']) {
      for (final kind in ['work', 'release', 'episode']) {
        await db.insert('media_entities', {
          'id': '$prefix-$kind',
          'kind': kind,
          if (kind != 'work')
            'parent_id': '$prefix-${kind == 'episode' ? 'release' : 'work'}',
          'revision': 0,
          'attributes': jsonEncode({
            'title': kind,
            'localOnly': true,
            if (kind == 'episode') ...{
              'number': '1',
              'order': 'local',
              'type': 'regular'
            }
          }),
        });
      }
      await db.insert('media_file_episodes', {
        'file_id': file,
        'episode_id': '$prefix-episode',
        'relation': 'local_catalog',
        'ordinal': 0,
        'start_ms': 0,
        'end_ms': 10000
      });
    }
  });
  tearDown(() => f.close());

  JsonMap request({String id = 'merge', bool mapped = true}) => {
        'sourceWorkId': 'source-work',
        'targetWorkId': 'target-work',
        'requestId': id,
        'reason': 'The same work and exact episode file range',
        'mappings': [
          if (mapped) ...[
            {'sourceId': 'source-release', 'targetId': 'target-release'},
            {'sourceId': 'source-episode', 'targetId': 'target-episode'},
          ]
        ]
      };
  Future<JsonMap> preview(JsonMap r, {String origin = 'mcp'}) =>
      f.call('media.management.merge_work', r, origin: origin);
  Future<JsonMap> commit(JsonMap r, {String origin = 'mcp'}) async {
    final p = await preview(r, origin: origin);
    expect(p['canCommit'], isTrue, reason: jsonEncode(p));
    return f.call('media.management.merge_work',
        {...r, 'expectedPlan': p['expectedPlan']},
        origin: origin);
  }

  Future<void> rejected(String action, JsonMap r) async {
    final outcome =
        await f.harness.invokeJson(action, r, Invocation(origin: 'mcp'));
    expect(outcome, isA<Failed>(), reason: jsonEncode(outcome.toEnvelope()));
  }

  Future<String> dump() async {
    final db = f.jobs.database;
    return jsonEncode({
      for (final t in [
        'media_entities',
        'media_bindings',
        'media_file_episodes',
        'media_overrides',
        'danmaku_bindings',
        'media_entity_aliases',
        'media_work_merges',
        'media_evidence'
      ])
        t: await db.query(t, orderBy: 'rowid')
    });
  }

  Future<void> binding(
      String id, String entity, String provider, String external,
      {String scope = 'work/test'}) async {
    final db = f.jobs.database;
    final ref = ExternalRef(provider, 'episode', external, scope: scope);
    final object = stableMediaId('object', ref.toJson());
    await db.insert('media_external_objects', {
      'id': object,
      'provider': provider,
      'object_type': 'episode',
      'external_id': external,
      'scope': scope
    });
    await db.insert('media_bindings', {
      'id': id,
      'entity_id': entity,
      'object_id': object,
      'relation': 'exact',
      'scope': '{}',
      'status': 'accepted',
      'source': 'explicit_binding',
      'bound_by': 'agent',
      'revision': 0,
      'invocation_id': 'original',
      'created_at': '2026-10-27T00:00:00Z'
    });
    await db.insert('media_snapshots', {
      'id': 'snapshot-$id',
      'object_id': object,
      'language': 'zh-CN',
      'fetched_at': '2026-10-27T00:00:00Z',
      'fields': '{"metadata":{"overview":"保留来源资料"}}'
    });
    await db.insert('media_evidence', {
      'id': 'evidence-$id',
      'binding_id': id,
      'source': 'explicit_binding',
      'payload': '{"reason":"original evidence"}',
      'created_at': '2026-10-27T00:00:00Z'
    });
  }

  test(
      'merge moves the complete hierarchy facts and undo restores them without Classic I/O',
      () async {
    final db = f.jobs.database;
    await binding(
        'source-binding', 'source-episode', 'dandanplay', '195660001');
    await binding('target-binding', 'target-episode', 'tmdb', '2');
    await db.insert('media_overrides', {
      'entity_id': 'source-work',
      'field': 'overview',
      'value': '"user text"',
      'invocation_id': 'original'
    });
    final danmaku = DanmakuStore(f.identities);
    final bid = await danmaku.attach(
        'source-episode',
        const DanmakuVideo(
            sourceId: 'dandanplay',
            videoId: '195660001',
            title: '1',
            durationMs: 10000,
            objectType: 'episode'),
        'confirmed',
        null,
        Invocation(origin: 'mcp'));
    await db.update('danmaku_bindings', {'cache_key': 'persistent-pool'},
        where: 'id=?', whereArgs: [bid]);
    await db.insert('file_subtitles', {
      'file_id': file,
      'facts': jsonEncode({
        'fileId': file,
        'revision': 1,
        'tracks': [
          {'id': 'subtitle', 'path': '/kept.ass'}
        ],
        'selection': {'trackId': 'subtitle', 'basis': 'manual'}
      })
    });
    final path =
        (await f.identities.locations(file)).single['locator'] as String;
    f.classic.rows[path] = {
      'filePath': path,
      'lastPosition': 6000,
      'duration': 10000,
      'watchProgress': 0.6
    };
    final history = jsonEncode(f.classic.rows);
    final initial = await dump();
    final snapshots = await db.query('media_snapshots');
    final p = await preview(request());
    expect(await dump(), initial, reason: 'preview changes no domain row');
    final done = await f.call('media.management.merge_work',
        {...request(), 'expectedPlan': p['expectedPlan']});
    expect((await f.identities.library()).map((w) => w['workId']),
        ['target-work']);
    expect(await db.query('media_file_episodes'), hasLength(1));
    expect(
        (await db.query('media_bindings'))
            .every((b) => b['entity_id'] == 'target-episode'),
        isTrue);
    expect(
        (await f.identities.entity('source-episode'))['id'], 'target-episode');
    expect(
        ((await f.call('media.library.work', {'workId': 'source-work'}))['work']
            as Map)['workId'],
        'target-work');
    final moved = await danmaku.binding(bid);
    expect(moved['entity_id'], 'target-episode');
    expect(moved['cache_key'], 'persistent-pool');
    expect(
        (await readEpisodeSubtitles(db, 'target-episode'))
            .tracks
            .single['selected'],
        isTrue);
    expect(await db.query('media_snapshots'), snapshots);
    expect((await readEpisodeSubtitles(db, 'source-episode')).tracks,
        hasLength(1));
    expect(
        (await f.call('media.files.list', {'workId': 'source-work'}))['total'],
        1);
    expect(jsonEncode(f.classic.rows), history);
    expect(f.classic.applications, 0);
    final u = {
      'mergeId': done['mergeId'],
      'requestId': 'undo',
      'reason': 'Undo test'
    };
    final up = await f.call('media.management.undo_merge', u);
    expect(up['canCommit'], isTrue, reason: jsonEncode(up));
    await f.call('media.management.undo_merge',
        {...u, 'expectedPlan': up['expectedPlan']});
    expect((await f.identities.library()).length, 2);
    expect((await danmaku.binding(bid))['entity_id'], 'source-episode');
    expect(await db.query('media_file_episodes'), hasLength(2));
    expect(await db.query('media_entity_aliases'), isEmpty);
    expect(jsonEncode(f.classic.rows), history);
    expect((await db.query('media_work_merges')).single['state'], 'undone');
  });

  test('new metadata or file associations invalidate preview atomically',
      () async {
    final r = request(), p = await preview(request());
    await f.jobs.database.update(
        'media_entities', {'attributes': '{"title":"edited","localOnly":true}'},
        where: 'id=?', whereArgs: ['target-work']);
    final before = await dump();
    await rejected('media.management.merge_work',
        {...r, 'expectedPlan': p['expectedPlan']});
    expect(await dump(), before);
  });

  test('different parts of the same file cannot be collapsed', () async {
    await f.jobs.database.update(
        'media_file_episodes', {'start_ms': 10000, 'end_ms': 20000},
        where: 'episode_id=?', whereArgs: ['source-episode']);
    final p = await preview(request());
    expect(p['canCommit'], isFalse);
    expect(
        ((p['preview'] as Map)['conflicts'] as List)
            .any((c) => c['kind'] == 'file_range'),
        isTrue);
    await rejected('media.management.merge_work',
        {...request(), 'expectedPlan': p['expectedPlan']});
    expect(await f.jobs.database.query('media_file_episodes'), hasLength(2));
  });

  test('conflicting identities are rejected even with a metadata preference',
      () async {
    await binding('a', 'source-episode', 'tmdb', '1');
    await binding('b', 'target-episode', 'tmdb', '2');
    final p = await preview({...request(), 'metadataPolicy': 'prefer_target'});
    expect(p['canCommit'], isFalse);
    expect(
        ((p['preview'] as Map)['conflicts'] as List)
            .any((c) => c['kind'] == 'external_identity'),
        isTrue);
  });

  test('different scopes do not bypass same-provider identity conflicts',
      () async {
    await binding('a', 'source-episode', 'tmdb', '1', scope: 'tv/first');
    await binding('b', 'target-episode', 'tmdb', '1', scope: 'tv/second');
    final initial = await dump();
    final p = await preview(request());
    expect(p['canCommit'], isFalse);
    final facts = p['preview'] as Map;
    expect((facts['identities'] as List).map((b) => b['scope']),
        containsAll(['tv/first', 'tv/second']));
    await rejected('media.management.merge_work',
        {...request(), 'expectedPlan': p['expectedPlan']});
    expect(await dump(), initial);
  });

  test('episode pairs must agree with explicitly mapped releases', () async {
    await f.jobs.database.insert('media_entities', {
      'id': 'another-release',
      'kind': 'release',
      'parent_id': 'target-work',
      'revision': 0,
      'attributes': '{}'
    });
    await f.jobs.database.update(
        'media_entities', {'parent_id': 'another-release'},
        where: 'id=?', whereArgs: ['target-episode']);
    final p = await preview(request());
    expect(p['canCommit'], isFalse);
    expect(
        ((p['preview'] as Map)['conflicts'] as List)
            .any((c) => c['kind'] == 'parent_mapping'),
        isTrue);
    final initial = await dump();
    await rejected('media.management.merge_work',
        {...request(), 'expectedPlan': p['expectedPlan']});
    expect(await dump(), initial);
    // Explicit episode correspondence without a contradictory release pair
    // can intentionally reconcile differing season structures.
    final r = request();
    (r['mappings'] as List).removeAt(0);
    expect((await preview(r))['canCommit'], isTrue);
  });

  test(
      'manual metadata conflicts require a choice and preserve both values for undo',
      () async {
    final db = f.jobs.database;
    for (final name in ['source', 'target']) {
      await db.insert('media_overrides', {
        'entity_id': '$name-work',
        'field': 'title',
        'value': jsonEncode(name),
        'invocation_id': 'original'
      });
    }
    final p = await preview(request());
    expect(p['canCommit'], isFalse);
    final done =
        await commit({...request(), 'metadataPolicy': 'prefer_source'});
    expect((await db.query('media_overrides')).single['value'], '"source"');
    final journal = (await db.query('media_work_merges',
            where: 'id=?', whereArgs: [done['mergeId']]))
        .single['snapshot'] as String;
    expect(journal, contains(r'\"target\"'));
    expect(journal, contains(r'\"source\"'));
  });

  test(
      'unmapped episodes keep IDs and progress ranges; preview only suggests exact matches',
      () async {
    final p = await preview(request(mapped: false));
    expect((p['preview'] as Map)['suggestedMappings'], hasLength(1));
    await commit(request(mapped: false));
    expect((await f.identities.entity('source-release'))['parent_id'],
        'target-work');
    expect(
        (await f.identities.entity('source-episode'))['id'], 'source-episode');
    expect(await f.jobs.database.query('media_file_episodes'), hasLength(2));
  });

  test(
      'merge and undo receipts survive restart and changed request reuse is refused',
      () async {
    final r = request(), p = await preview(request());
    final applied = {...r, 'expectedPlan': p['expectedPlan']};
    final done = await f.call('media.management.merge_work', applied);
    await f.reopen();
    expect(await f.call('media.management.merge_work', applied), done);
    expect(await f.jobs.database.query('media_work_merges'), hasLength(1));
    await rejected(
        'media.management.merge_work', {...applied, 'reason': 'different'});
    final u = {
      'mergeId': done['mergeId'],
      'requestId': 'undo',
      'reason': 'Undo'
    };
    final up = await f.call('media.management.undo_merge', u);
    final undoRequest = {...u, 'expectedPlan': up['expectedPlan']};
    final undone = await f.call('media.management.undo_merge', undoRequest);
    await f.reopen();
    expect(await f.call('media.management.undo_merge', undoRequest), undone);
    expect(await f.jobs.database.query('media_evidence'), hasLength(2));
  });

  test(
      'undo refuses later bindings, file links or edits without overwriting them',
      () async {
    final done = await commit(request());
    await f.jobs.database.insert('media_overrides', {
      'entity_id': 'target-work',
      'field': 'overview',
      'value': '"later edit"',
      'invocation_id': 'later'
    });
    final u = {
      'mergeId': done['mergeId'],
      'requestId': 'undo',
      'reason': 'Undo'
    };
    final p = await f.call('media.management.undo_merge', u);
    expect(p['canCommit'], isFalse);
    final before = await dump();
    await rejected('media.management.undo_merge',
        {...u, 'expectedPlan': p['expectedPlan']});
    expect(await dump(), before);
  });

  test('receipt failure rolls the whole merge back', () async {
    final r = request(), p = await preview(request());
    final before = await dump();
    await f.jobs.database.execute(
        "CREATE TRIGGER reject_merge BEFORE INSERT ON media_work_merges BEGIN SELECT RAISE(ABORT,'injected receipt failure'); END");
    await rejected('media.management.merge_work',
        {...r, 'expectedPlan': p['expectedPlan']});
    expect(await dump(), before);
  });

  test('BanG-shaped duplicate hierarchy becomes exactly thirteen episodes',
      () async {
    final db = f.jobs.database, r = request();
    final mappings = r['mappings'] as List;
    for (var i = 2; i <= 13; i++) {
      final fileId = await f.file('episode-$i.mkv');
      for (final prefix in ['source', 'target']) {
        await db.insert('media_entities', {
          'id': '$prefix-episode-$i',
          'kind': 'episode',
          'parent_id': '$prefix-release',
          'revision': 0,
          'attributes': jsonEncode({
            'title': 'Episode $i',
            'number': '$i',
            'order': 'local',
            'type': 'regular',
            'localOnly': true
          })
        });
        await db.insert('media_file_episodes', {
          'file_id': fileId,
          'episode_id': '$prefix-episode-$i',
          'relation': 'local_catalog',
          'ordinal': 0,
          'start_ms': 0,
          'end_ms': 10000
        });
      }
      mappings.add(
          {'sourceId': 'source-episode-$i', 'targetId': 'target-episode-$i'});
    }
    await commit(r);
    final work = (await f
        .call('media.library.work', {'workId': 'target-work'}))['work'] as Map;
    expect(
        ((work['releases'] as List).single as Map)['episodes'], hasLength(13));
    expect(await db.query('media_file_episodes'), hasLength(13));
    expect(await db.query('media_locations'), hasLength(13));
  });

  test('an old alias cannot remove the surviving episode through catalog tools',
      () async {
    await commit(request());
    final before = await dump();
    await rejected('media.entities.remove_batch', {
      'entityIds': ['source-episode'],
      'requestId': 'remove',
      'reason': 'Old reference'
    });
    expect(await dump(), before);
    final remove = {
      'entityIds': ['target-work'],
      'requestId': 'remove-current',
      'reason': 'Current reference'
    };
    final p = await f.call('media.entities.remove_batch', remove);
    final d = await f.call('media.entities.remove_batch',
        {...remove, 'preview': false, 'expectedPlan': p['expectedPlan']});
    await f.call('media.entities.restore', {'undoId': d['undoId']});
    expect(await f.jobs.database.query('media_file_episodes'), hasLength(1));
  });

  test(
      'retained identical danmaku pools can be rebound without duplicating or losing their records',
      () async {
    final store = DanmakuStore(f.identities);
    const v = DanmakuVideo(
        sourceId: 'dandanplay',
        videoId: '195660001',
        title: '1',
        durationMs: 10000,
        objectType: 'episode');
    final a = await store.attach('source-episode', v, 'source evidence', null,
        Invocation(origin: 'mcp'));
    final b = await store.attach('target-episode', v, 'target evidence', null,
        Invocation(origin: 'mcp'));
    await commit(request());
    expect(
        await store.attach(
            'source-episode', v, 'repeat', null, Invocation(origin: 'mcp')),
        isIn([a, b]));
    expect(await f.jobs.database.query('danmaku_bindings'), hasLength(2));
  });

  test('a queued first danmaku acquisition without cache_job_id blocks merge',
      () async {
    final store = DanmakuStore(f.identities);
    const v = DanmakuVideo(
        sourceId: 'dandanplay',
        videoId: '195660001',
        title: '1',
        durationMs: 10000,
        objectType: 'episode');
    final bid = await store.attach(
        'source-episode', v, 'source', null, Invocation(origin: 'mcp'));
    final now = DateTime.now().toUtc();
    final job = Job(
        jobId: 'queued-fetch',
        type: 'danmaku.fetch',
        title: 'Waiting',
        state: JobState.paused,
        phase: 'queued',
        progress: JobProgress(completed: 0, unit: 'chunks'),
        createdAt: now,
        updatedAt: now,
        ownerDeviceId: 'fixture-device',
        revision: 0,
        input: {'bindingId': bid, 'video': v.toJson()});
    await f.jobs.database.insert('jobs', {
      'job_id': job.jobId,
      'type': job.type,
      'state': job.state.wireName,
      'revision': 0,
      'created_at': now.toIso8601String(),
      'snapshot': jsonEncode(job.toStorageJson())
    });
    final p = await preview(request());
    expect(p['canCommit'], isFalse);
    expect(
        ((p['preview'] as Map)['conflicts'] as List)
            .any((c) => c['kind'] == 'active_danmaku_jobs'),
        isTrue);
  });

  test('a late acquisition cannot assign its pool after its target was merged',
      () async {
    final store = DanmakuStore(f.identities);
    const v = DanmakuVideo(
        sourceId: 'dandanplay',
        videoId: '195660001',
        title: '1',
        durationMs: 10000,
        objectType: 'episode');
    final bid = await store.attach(
        'source-episode', v, 'source', null, Invocation(origin: 'mcp'));
    await commit(request());
    await expectLater(
        store.assignCache(bid, 'late-pool', 'late-fetch',
            expectedCacheRevision: 0,
            expectedEntityId: 'source-episode',
            expectedEntityRevision: 0),
        throwsA(isA<Failure>()));
    expect((await store.binding(bid))['cache_key'], isNull);
  });

  test('simultaneous retries create one merge audit', () async {
    final r = request(), p = await preview(request());
    final results = await Future.wait([
      for (var i = 0; i < 3; i++)
        f.call('media.management.merge_work',
            {...r, 'expectedPlan': p['expectedPlan']})
    ]);
    expect(
        results.every((r) => r['mergeId'] == results.first['mergeId']), isTrue);
    expect(await f.jobs.database.query('media_work_merges'), hasLength(1));
    expect(await f.jobs.database.query('media_evidence'), hasLength(1));
  });

  test(
      'new tools are routable to the source device and request keys are origin scoped',
      () async {
    expect(meshActionAllowed('media.management.merge_work'), isTrue);
    expect(meshActionAllowed('media.management.undo_merge'), isTrue);
    final r = request(), p = await preview(request(), origin: 'mesh:a');
    final done = await f.call('media.management.merge_work',
        {...r, 'expectedPlan': p['expectedPlan']},
        origin: 'mesh:a');
    expect(done['committed'], isTrue);
    final other = await f.harness.invokeJson(
        'media.management.merge_work',
        {...r, 'expectedPlan': p['expectedPlan']},
        Invocation(origin: 'mesh:b'));
    expect(other, isA<Failed>());
  });
}
