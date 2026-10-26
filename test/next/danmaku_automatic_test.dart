import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:nipaplay/next/danmaku/automatic.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/system/storage.dart';
import 'package:nipaplay/next/harness_hooks.dart';
import 'package:nipaplay/utils/storage_service.dart';

import 'danmaku_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DanmakuFixture f;
  setUp(() async {
    f = DanmakuFixture();
    await f.open();
    StorageService.debugAppStorageDirectoryOverride = f.root;
  });
  tearDown(() async {
    StorageService.debugAppStorageDirectoryOverride = null;
    await f.close();
  });

  AutomaticDanmaku loader(Future<List<DanmakuVideo>> Function(String) match,
          {bool skip = false,
          DanmakuAutoLoadStrategy strategy =
              DanmakuAutoLoadStrategy.remoteAndLocal}) =>
      AutomaticDanmaku(f.service,
          matchHash: match,
          readSettings: () async => (strategy: strategy, skipMatching: skip));

  Future<void> metadataIdentity(String entityId, String videoId,
      {String type = 'episode'}) async {
    final db = f.service.store.db;
    await db.insert('media_external_objects', {
      'id': 'object-$videoId',
      'provider': 'dandanplay',
      'object_type': type,
      'external_id': videoId,
      'scope': type == 'episode' ? 'anime/7001' : '',
    });
    await db.insert('media_bindings', {
      'id': 'binding-$videoId',
      'entity_id': entityId,
      'object_id': 'object-$videoId',
      'relation': 'exact',
      'scope': '{}',
      'status': 'accepted',
      'source': 'agent',
      'bound_by': 'agent',
      'revision': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  test(
      'confirmed metadata episode fetches without hashing even with matching disabled',
      () async {
    final id = await f.file();
    await metadataIdentity(id, ddpVideo.videoId);
    expect(
        await loader((_) async => fail('known ID must not hash'), skip: true)
            .prepare('/fixture/video.mkv', fileId: id),
        true);
    final b = (await f.service.store.bindings(id)).single;
    expect((b['video'] as Map)['videoId'], ddpVideo.videoId);
    expect(f.host.requests, hasLength(1));
    await f.reopen();
    expect(
        await loader((_) async => fail('saved pool must not hash'), skip: true)
            .prepare('/fixture/video.mkv', fileId: id),
        true);
    expect(f.host.requests, hasLength(1));
  });

  test('a work ID and ambiguous exact episodes never invent an episode',
      () async {
    final id = await f.file();
    await metadataIdentity(id, '7001', type: 'anime');
    expect(
        await loader((_) async => fail('disabled hash'), skip: true)
            .prepare('/fixture/video.mkv', fileId: id),
        false);
    await metadataIdentity(id, '7101');
    await metadataIdentity(id, '7102');
    expect(
        await loader((_) async => fail('ambiguous identity must not hash'))
            .prepare('/fixture/video.mkv', fileId: id),
        false);
    expect(f.host.requests, isEmpty);
  });

  test(
      'bind records only; explicit fetch assigns the pool and prepare is separate',
      () async {
    final id = await f.file();
    f.service.durationProbe = (_) async => fail('binding must not probe');
    final video = {...ddpVideo.toJson(), 'durationMs': 0};
    final bound = await f.call('danmaku.bind', {
      'entityId': id,
      'video': video,
      'reason': 'Confirmed episode ID only',
    });
    expect(bound['downloaded'], false);
    expect(bound['jobId'], null);
    expect(f.host.requests, isEmpty);
    expect(await f.engine.list(type: 'danmaku.fetch'), isEmpty);
    expect(f.player.tracks, isEmpty);
    final fetched = await f.call('danmaku.fetch', {
      'video': video,
      'bindingId': bound['bindingId'],
      'requestId': 'explicit-prefetch',
    });
    var job = await f.engine.get(fetched['jobId'] as String);
    while (!job.state.isTerminal) {
      job = await f.engine.wait(job.jobId,
          afterRevision: job.revision, timeout: const Duration(seconds: 3));
    }
    expect(job.state, JobState.succeeded);
    expect(
        (await f.service.store
            .binding(bound['bindingId'] as String))['cache_key'],
        isNotNull);
    expect(f.host.requests, hasLength(1));
  });

  test('unique hash match acquires once, persists, and restores offline',
      () async {
    final id = await f.file();
    var matches = 0;
    final automatic = loader((_) async {
      matches++;
      return [ddpVideo];
    });
    final results = await Future.wait([
      automatic.prepare('/fixture/video.mkv', fileId: id),
      automatic.prepare('/fixture/video.mkv', fileId: id)
    ]);
    expect(results, [true, true]);
    expect(matches, 1);
    final binding = (await f.service.store.bindings(id)).single;
    expect(binding['bound_by'], 'automatic');
    expect(await f.service.store.entries(binding['cache_key'] as String),
        hasLength(3));
    expect(f.host.requests, hasLength(1));
    final plan =
        await SystemStorage(f.root, f.service.store.db, HarnessHooks()).plan({
      'kinds': ['nextDanmaku']
    });
    expect(plan['entries'], isEmpty);
    expect((plan['retained'] as List).single['reason'], 'saved_danmaku');
    await f.reopen();
    expect(
        await loader((_) async => throw StateError('offline'))
            .prepare('/fixture/video.mkv', fileId: id),
        true);
    expect(f.host.requests, hasLength(1));
    await f.service.refreshCurrent();
    expect(f.player.loaded(binding['id'] as String), isNotNull);
  });

  test('existing evicted binding fetches original video without rematching',
      () async {
    final id = await f.file();
    final binding = await f.service.store
        .attach(id, ddpVideo, 'manual', null, Invocation(origin: 'gui'));
    expect(
        await loader((_) async => throw StateError('must not rematch'))
            .prepare('/fixture/video.mkv', fileId: id),
        true);
    expect((await f.service.store.binding(binding))['cache_key'], isNotNull);
    expect(f.host.requests, hasLength(1));
  });

  test('ambiguous and missing hash matches do not choose a title guess',
      () async {
    final id = await f.file();
    final other =
        DanmakuVideo.fromJson({...ddpVideo.toJson(), 'videoId': '7102'});
    for (final candidates in <List<DanmakuVideo>>[
      [],
      [ddpVideo, other]
    ]) {
      expect(
          await loader((_) async => candidates)
              .prepare('/fixture/video.mkv', fileId: id),
          false);
    }
    expect(await f.service.store.bindings(id), isEmpty);
    expect(f.host.requests, isEmpty);
  });

  test('disabled, local-only and receiver URLs never request a hash', () async {
    final id = await f.file();
    Future<List<DanmakuVideo>> match(String _) async => fail('unexpected hash');
    expect(
        await loader(match, skip: true)
            .prepare('/fixture/video.mkv', fileId: id),
        false);
    expect(
        await loader(match, strategy: DanmakuAutoLoadStrategy.local)
            .prepare('/fixture/video.mkv', fileId: id),
        false);
    expect(await loader(match).prepare('mesh:///episode'), false);
    expect(await loader(match).prepare('http://127.0.0.1/grant'), false);
  });

  test('explicit detach is not undone by automatic matching', () async {
    final id = await f.file();
    final binding = await f.service.store
        .attach(id, ddpVideo, 'manual', null, Invocation(origin: 'gui'));
    await f.service.store
        .change(binding, 0, {'status': 'revoked'}, Invocation(origin: 'gui'));
    expect(
        await loader((_) async => fail('must preserve detach'))
            .prepare('/fixture/video.mkv', fileId: id),
        false);
    expect(f.host.requests, isEmpty);
  });

  test('failed acquisition retains the source binding for the next play',
      () async {
    final id = await f.file();
    f.host.failure = const SourceFailure(SourceStatus.schemaChanged);
    final automatic = loader((_) async => [ddpVideo]);
    expect(await automatic.prepare('/fixture/video.mkv', fileId: id), false);
    expect((await f.service.store.bindings(id)).single['cache_key'], isNull);
    expect(await automatic.prepare('/fixture/video.mkv', fileId: id), true);
  });
}
