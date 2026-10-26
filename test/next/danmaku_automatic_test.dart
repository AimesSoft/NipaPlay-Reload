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
