import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/runtime.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'danmaku_test_support.dart';

final class _Player extends Fake implements VideoPlayerState {
  final listeners = <VoidCallback>{};
  @override
  String? get currentVideoPath => '/fixture/delayed.mkv';
  @override
  int get playbackGeneration => 1;
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
    final harness = Harness([runtime.capability]);
    runtime.startRestoring(harness, player);
    runtime.startRestoring(harness, player);
    expect(player.listeners, hasLength(1));
    expect(runtime.service.player.target!.durationMs, 360000);
    await runtime.stopRestoring();
    expect(player.listeners, isEmpty);
    expect(runtime.service.player.target, isNull);
    runtime.startRestoring(harness, player);
    expect(player.listeners, hasLength(1));
    await runtime.stopRestoring();
    expect(await f.jobs.database.query('media_entities'), hasLength(1));
    expect(await f.jobs.database.query('media_locations'), hasLength(1));
    expect(await f.jobs.list(), isEmpty);
  });
}
