import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/next/player/core/session.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/sources/playback_sources.dart';
import 'package:nipaplay/next/player/sources/resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_driver.dart';

final class _Resolver extends NextSourceResolver {
  _Resolver();
  final starts = <Duration?>[];
  Completer<void>? gate;
  @override
  Future<SourcePlan> resolve(PlayableItem item,
      {Duration? start, bool direct = false}) async {
    starts.add(start);
    if (gate case final gate?) await gate.future;
    final detail = item.detailContext ??
        PlaybackDetailContext(
            sourceKind: PlaybackSourceKind.networkStream,
            sourceLabel: 'test',
            sourceKey: 'episodes',
            title: 'test',
            isIdentified: false,
            episodeLoader: () async => List.generate(
                3,
                (index) => PlaybackDetailEpisode(
                    id: '$index',
                    videoPath: 'https://test.invalid/$index.mkv',
                    title: 'episode $index')));
    return SourcePlan(
      item: item,
      detail: detail,
      source: ResolvedSource(
          locator: item.videoPath,
          uri: 'http://127.0.0.1/media?temporary=secret',
          kind: 'network',
          direct: true),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('removed server locators are rejected before resolution', () async {
    for (final scheme in ['jellyfin', 'emby', 'dandanplay']) {
      await expectLater(
          NextSourceResolver()
              .resolve(PlayableItem(videoPath: '$scheme://fixture')),
          throwsA(isA<Failure>()));
    }
    var episodeLoads = 0;
    await expectLater(
        NextSourceResolver().resolve(PlayableItem(
            videoPath: 'https://fixture.invalid/media',
            detailContext: PlaybackDetailContext(
                sourceKind: PlaybackSourceKind.sharedRemoteAnime,
                sourceLabel: 'retired',
                sourceKey: 'retired',
                title: 'retired',
                isIdentified: false,
                episodeLoader: () async {
                  episodeLoads++;
                  return [];
                }))),
        throwsA(isA<Failure>()));
    expect(episodeLoads, 0);
  });
  PlayableItem item(int index) =>
      PlayableItem(videoPath: 'https://test.invalid/$index.mkv');
  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 30));
  void end(FakeHost rig) => rig.drivers.last
      .emit((seq, at) => KernelEnded(rig.drivers.last.instance, seq, at));

  test('danmaku preparation precedes opening and stale requests cannot open',
      () async {
    final rig = FakeHost();
    final sources = PlaybackSources(rig.host, _Resolver());
    addTearDown(sources.dispose);
    addTearDown(() => rig.host.dispose());
    final entered = Completer<void>(), release = Completer<void>();
    sources.prepareDanmaku = (path) async {
      if (path == item(0).videoPath) {
        entered.complete();
        await release.future;
      }
    };
    final old = sources.open(item(0));
    final rejected = expectLater(old, throwsA(isA<Failure>()));
    await entered.future;
    expect(rig.drivers, isEmpty);
    final current = await sources.open(item(1));
    release.complete();
    await rejected;
    expect(rig.host.current.value, same(current));
    expect(current.path, item(1).videoPath);
  });

  test('Mesh episode IDs with colons keep stable locators and get fresh grants',
      () async {
    final rig = FakeHost();
    final resolver = NextSourceResolver();
    var opens = 0;
    resolver.specialSource = (item) async => SourcePlan(
        item: item,
        source: ResolvedSource(
            locator: item.videoPath,
            uri: 'http://127.0.0.1/grant-${++opens}',
            kind: 'mesh',
            direct: true),
        detail: PlaybackDetailContext(
            sourceKind: PlaybackSourceKind.networkStream,
            sourceLabel: 'Mesh',
            sourceKey: 'mesh',
            title: 'Mesh',
            isIdentified: false,
            episodeLoader: () async => const []));
    final sources = PlaybackSources(rig.host, resolver);
    addTearDown(sources.dispose);
    addTearDown(() => rig.host.dispose());
    final item = PlayableItem(videoPath: 'mesh:///mesh-episode%3Aone');
    final first = await sources.open(item);
    expect(first.path, item.videoPath);
    expect(sources.plan!.source.uri, 'http://127.0.0.1/grant-1');
    await sources.open(item);
    expect(sources.plan!.source.uri, 'http://127.0.0.1/grant-2');
    expect(rig.drivers.first.released, true);
  });

  test(
      'fresh grants resume by stable identity and reopening saves latest position',
      () async {
    final rig = FakeHost();
    const stable = 'mesh:///mesh-episode%3Aresume';
    final resolver = NextSourceResolver();
    resolver.specialSource = (item) async => SourcePlan(
        item: item,
        source: ResolvedSource(
            locator: stable, uri: item.videoPath, kind: 'mesh', direct: true),
        detail: PlaybackDetailContext(
            sourceKind: PlaybackSourceKind.networkStream,
            sourceLabel: 'Mesh',
            sourceKey: 'mesh',
            title: 'Mesh',
            isIdentified: false,
            episodeLoader: () async => const []));
    final sources = PlaybackSources(rig.host, resolver);
    addTearDown(sources.dispose);
    addTearDown(() => rig.host.dispose());
    rig.records.positions[stable] = 720000;
    final first = await sources
        .open(PlayableItem(videoPath: 'http://127.0.0.1/grant-one'));
    expect(first.position.inSeconds, inInclusiveRange(720, 721));
    rig.drivers.last.sample(const Duration(minutes: 15));
    final second = await sources
        .open(PlayableItem(videoPath: 'http://127.0.0.1/grant-two'));
    expect(second.position.inSeconds, inInclusiveRange(900, 901));
    final restarted = await sources.open(
        PlayableItem(videoPath: 'http://127.0.0.1/grant-three'),
        start: Duration.zero);
    expect(restarted.position.inSeconds, 0);
    expect(rig.records.positions.keys, everyElement(stable));
  });

  test(
      'synchronized resume works without runtime and overrides older local position',
      () async {
    final rig = FakeHost();
    final resolver = NextSourceResolver();
    var resume = const Duration(minutes: 8);
    resolver.specialSource = (item) async => SourcePlan(
        item: item,
        resumePosition: resume,
        source: ResolvedSource(
            locator: item.videoPath,
            uri: 'http://127.0.0.1/grant',
            kind: 'mesh',
            direct: true),
        detail: PlaybackDetailContext(
            sourceKind: PlaybackSourceKind.networkStream,
            sourceLabel: 'Mesh',
            sourceKey: 'mesh',
            title: 'Mesh',
            isIdentified: false,
            episodeLoader: () async => const []));
    final sources = PlaybackSources(rig.host, resolver);
    addTearDown(sources.dispose);
    addTearDown(() => rig.host.dispose());
    rig.records.positions[item(0).videoPath] = 60000;
    final first = await sources.open(item(0));
    expect(first.position.inSeconds, inInclusiveRange(480, 481));
    await rig.host.close(reason: 'test');
    resume = Duration.zero;
    final completed = await sources.open(item(0));
    expect(completed.position.inSeconds, 0);
  });

  test(
      'network resume uses stable identity and episode switches create fresh kernels',
      () async {
    final rig = FakeHost();
    final resolver = _Resolver();
    final sources = PlaybackSources(rig.host, resolver);
    addTearDown(sources.dispose);
    addTearDown(() => rig.host.dispose());
    rig.records.positions[item(1).videoPath] = 720000;
    final first = await sources.open(item(1));
    await sources.playlist();
    expect(resolver.starts.single, const Duration(minutes: 12));
    expect(first.position.inSeconds, inInclusiveRange(720, 721));
    expect(sources.canPrevious, true);
    expect(sources.canNext, true);
    expect((await sources.playlist())['currentIndex'], 1);
    final oldEpisode = sources.episodes.first;
    await sources.switchEpisode(true);
    expect(rig.drivers.first.released, true);
    expect(rig.drivers.length, 2);
    expect(rig.host.current.value!.path, item(2).videoPath);
    expect(rig.records.positions.keys,
        isNot(contains('http://127.0.0.1/media?temporary=secret')));
    await expectLater(sources.playEpisode(oldEpisode), throwsA(isA<Failure>()));
  });

  test(
      'countdown cancellation fences pending end settings and duplicate end events',
      () async {
    final rig = FakeHost();
    final settings = Completer<(String, int)>();
    final sources = PlaybackSources(rig.host, _Resolver(),
        readEndSettings: () => settings.future);
    addTearDown(sources.dispose);
    addTearDown(() => rig.host.dispose());
    await sources.open(item(0));
    await sources.playlist();
    end(rig);
    end(rig);
    await flush();
    sources.cancelAutoNext();
    settings.complete(('autoNext', 1));
    await flush();
    expect(sources.autoNext, null);
    expect(rig.drivers.length, 1);
  });

  test(
      'automatic next advances once, cancelled countdown stays on the same episode',
      () async {
    final rig = FakeHost();
    final sources = PlaybackSources(rig.host, _Resolver(),
        readEndSettings: () async => ('autoNext', 1));
    addTearDown(sources.dispose);
    addTearDown(() => rig.host.dispose());
    await sources.open(item(0));
    await sources.playlist();
    end(rig);
    end(rig);
    await flush();
    expect(sources.autoNext?['remainingSeconds'], 1);
    expect(sources.cancelAutoNext(), true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(rig.drivers.length, 1);
    await rig.host.current.value!.seek(Duration.zero, origin: 'test');
    end(rig);
    await Future<void>.delayed(const Duration(milliseconds: 1150));
    expect(rig.drivers.length, 2);
    expect(rig.host.current.value!.path, item(1).videoPath);
    expect(sources.autoNext, null);
  });

  for (final action in ['loop', 'pause', 'exitPlayer']) {
    test('end action $action applies to its session only', () async {
      final rig = FakeHost();
      final sources = PlaybackSources(rig.host, _Resolver(),
          readEndSettings: () async => (action, 0));
      addTearDown(sources.dispose);
      addTearDown(() => rig.host.dispose());
      final session =
          await sources.open(item(0), start: const Duration(minutes: 20));
      end(rig);
      await flush();
      if (action == 'loop') {
        expect(session.position.inSeconds, 0);
        expect(session.transport.value.playIntent, true);
        expect(session.transport.value.ended, false);
      } else if (action == 'pause') {
        expect(session.transport.value.playIntent, false);
        expect(session.transport.value.observed, KernelTransport.paused);
      } else {
        expect(session.phase.value, SessionPhase.closed);
        expect(rig.arbiter.owner, null);
        expect(sources.canNext, false);
      }
    });
  }

  test(
      'a late resolver cannot replace a newer open or resurrect a closed controller',
      () async {
    final rig = FakeHost();
    final resolver = _Resolver()..gate = Completer<void>();
    final sources = PlaybackSources(rig.host, resolver);
    addTearDown(() => rig.host.dispose());
    final old = sources.open(item(0));
    final rejected = expectLater(old, throwsA(isA<Failure>()));
    await flush();
    final gate = resolver.gate!;
    resolver.gate = null;
    await sources.open(item(1));
    gate.complete();
    await rejected;
    expect(rig.host.current.value!.path, item(1).videoPath);
    sources.dispose();
  });

  test('closing fences an open still resolving its network URL', () async {
    final rig = FakeHost();
    final resolver = _Resolver()..gate = Completer<void>();
    final sources = PlaybackSources(rig.host, resolver);
    addTearDown(sources.dispose);
    addTearDown(() => rig.host.dispose());
    final opening = sources.open(item(0));
    final rejected = expectLater(opening, throwsA(isA<Failure>()));
    await flush();
    sources.cancelPendingOpen();
    await rig.host.close(reason: 'gui');
    resolver.gate!.complete();
    await rejected;
    expect(rig.drivers, isEmpty);
    expect(rig.host.current.value, null);
  });
}
