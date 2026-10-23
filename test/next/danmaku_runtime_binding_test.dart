import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/danmaku/runtime.dart';
import 'package:nipaplay/next/player/classic/classic_backed_playback.dart';
import 'package:nipaplay/next/player/perf/budget.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'danmaku_test_support.dart';
import 'player_test_support.dart' show ClassicKernel;

final class _Player extends Fake implements VideoPlayerState {
  final listeners = <VoidCallback>{};
  @override
  final Player player = Player.withDelegate(ClassicKernel());
  @override
  Future<bool> Function(String path)? nextLocalDanmakuLoader;
  @override
  String? get currentVideoPath => '/fixture/delayed.mkv';
  @override
  int playbackGeneration = 1;
  @override
  int get playbackRequestGeneration => 1;
  @override
  PlayableItem? get lastPlaybackRequest => null;
  @override
  PlayerStatus get status => PlayerStatus.playing;
  @override
  bool get hasVideo => true;
  @override
  int danmakuListVersion = 1;
  @override
  Duration position = Duration.zero;
  @override
  Duration get duration => const Duration(seconds: 360);
  @override
  Map<String, Map<String, dynamic>> get danmakuTracks => {};
  @override
  Map<String, bool> get danmakuTrackEnabled => {};
  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners.remove(listener);
  }

  /// What Classic does while it plays: notify, every 120 ms.
  void notify() {
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}

int _refreshes() =>
    ((PlayerPerf.read()['counts'] as Map)['danmaku.refreshCurrent']
        as Map?)?['n'] as int? ??
    0;

Future<void> _idle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
      'late player binding can stop and restart without duplicate listeners or stale ports',
      () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final runtime = await DanmakuRuntime.create(f.identities);
    addTearDown(runtime.close);
    runtime.attach(f.engine);
    expect(runtime.service.player.target, isNull);
    final player = _Player();
    final playback = ClassicBackedPlayback(player);
    final harness = Harness([runtime.capability]);
    runtime.startRestoring(harness, playback);
    runtime.startRestoring(harness, playback);
    expect(player.listeners, hasLength(1));
    expect(player.nextLocalDanmakuLoader, isNotNull);
    expect(runtime.service.player.target!.durationMs, 360000);
    await runtime.stopRestoring();
    expect(player.listeners, isEmpty);
    expect(player.nextLocalDanmakuLoader, isNull);
    expect(runtime.service.player.target, isNull);
    runtime.startRestoring(harness, playback);
    expect(player.listeners, hasLength(1));
    await runtime.stopRestoring();
    expect(await f.jobs.database.query('media_entities'), hasLength(1));
    expect(await f.jobs.database.query('media_locations'), hasLength(1));
    expect(await f.jobs.list(), isEmpty);
  });

  test(
      'a minute of Classic notifying while the position moves restores '
      'nothing; another media or other tracks restore once', () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final runtime = await DanmakuRuntime.create(f.identities);
    addTearDown(runtime.close);
    runtime.attach(f.engine);
    final player = _Player();
    final harness = Harness([runtime.capability]);
    runtime.startRestoring(harness, ClassicBackedPlayback(player));
    addTearDown(runtime.stopRestoring);
    await _idle();
    PlayerPerf.reset();
    for (var i = 0; i < 500; i++) {
      player.position = Duration(milliseconds: 120 * i);
      player.notify();
    }
    await _idle();
    expect(_refreshes(), 0);
    player.danmakuListVersion++;
    player.notify();
    await _idle();
    expect(_refreshes(), 1);
    player.playbackGeneration++;
    player.notify();
    await _idle();
    expect(_refreshes(), 2);
  });
}
