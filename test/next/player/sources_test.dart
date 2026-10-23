import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/media_server_playback.dart' as server;
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/next/player/core/session.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/sources/playback_sources.dart';
import 'package:nipaplay/next/player/sources/resolver.dart';
import 'package:nipaplay/next/player/sources/server_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/media_server_transport.dart';

import 'fake_driver.dart';

final class _Resolver extends NextSourceResolver {
  _Resolver({this.remote});
  final ServerProgress? remote;
  final starts = <Duration?>[];
  Completer<void>? gate;
  @override
  Future<SourcePlan> resolve(PlayableItem item, {Duration? start,
      JsonMap selection = const {}, bool direct = false}) async {
    starts.add(start);
    if (gate case final gate?) await gate.future;
    final detail = item.detailContext ?? PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.networkStream, sourceLabel: 'test',
      sourceKey: 'episodes', title: 'test', isIdentified: false,
      episodeLoader: () async => List.generate(3, (index) => PlaybackDetailEpisode(
        id: '$index', videoPath: 'https://test.invalid/$index.mkv',
        title: 'episode $index')));
    return SourcePlan(item: item, detail: detail,
      source: ResolvedSource(locator: item.videoPath,
        uri: 'http://127.0.0.1/media?temporary=secret', kind: 'network', direct: true),
      progress: remote, serverSession: remote?.session);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  PlayableItem item(int index) => PlayableItem(videoPath: 'https://test.invalid/$index.mkv');
  Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 30));
  void end(FakeHost rig) => rig.drivers.last.emit((seq, at) =>
      KernelEnded(rig.drivers.last.instance, seq, at));

  test('network resume uses stable identity and episode switches create fresh kernels', () async {
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
    expect(rig.records.positions.keys, isNot(contains('http://127.0.0.1/media?temporary=secret')));
    await expectLater(sources.playEpisode(oldEpisode), throwsA(isA<Failure>()));
  });

  test('countdown cancellation fences pending end settings and duplicate end events', () async {
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

  test('automatic next advances once, cancelled countdown stays on the same episode', () async {
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
      final session = await sources.open(item(0), start: const Duration(minutes: 20));
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

  test('a late resolver cannot replace a newer open or resurrect a closed controller', () async {
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

  test('remote heartbeat reports real time, seek, pause and final stop in order', () async {
    final reports = <(String, JsonMap)>[];
    final remote = ServerProgress(
      session: server.PlaybackSession(itemId: 'episode', streamUrl: 'not stored',
        isTranscoding: false, mediaSourceId: 'version', playSessionId: 'session'),
      baseUrl: 'http://127.0.0.1:9999', prefix: '', headers: {},
      createTransport: () async => MediaServerTransport.fromClient(MockClient((request) async {
        reports.add((request.url.path, jsonDecode(request.body) as JsonMap));
        return http.Response('', 204);
      })));
    final rig = FakeHost();
    final sources = PlaybackSources(rig.host, _Resolver(remote: remote));
    addTearDown(sources.dispose);
    final session = await sources.open(item(0));
    await session.seek(const Duration(minutes: 13), origin: 'test');
    await Future<void>.delayed(const Duration(milliseconds: 5200));
    rig.drivers.last.sample(const Duration(seconds: 785));
    await session.setPaused(true, origin: 'test');
    await flush();
    await rig.host.close(reason: 'test');
    expect(reports.first.$1, '/Sessions/Playing');
    expect(reports.last.$1, '/Sessions/Playing/Stopped');
    expect(reports.last.$2['PositionTicks'], 7850000000);
    expect(reports.last.$2['IsPaused'], true);
    expect(reports.where((r) => r.$1.endsWith('/Progress')).length, greaterThanOrEqualTo(2));
    expect(sources.progress!.lastReport!['source'], 'session_clock');
    expect(sources.progress!.lastError, null);
    final count = reports.length;
    await flush();
    expect(reports.length, count);
  });
}
