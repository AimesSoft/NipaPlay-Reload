import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/capabilities/playback_controls_capability.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/next_playback.dart'
    show OverlayFrame, VideoStageHost;
import 'package:nipaplay/next/player/ports/session_playback.dart';
import 'package:nipaplay/next/player/ports/session_ports.dart';
import 'package:nipaplay/next/ui/player/timeline.dart';
import 'package:nipaplay/next/ui/player/video_stage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_driver.dart';

/// Next's playback layer as the controls, the capabilities and the stage
/// see it ([SessionPlayback]): pushed facts, a quiet frame while the
/// controls are hidden, playback.wait by events, what is not there yet
/// unavailable with its reason.
void main() {
  late Directory temp;
  late String video;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'seek_step_seconds': 5.0});
    temp = await Directory.systemTemp.createTemp('player-facade-');
    video = '${temp.path}/sintel.mkv';
    await File(video).writeAsString('not a video');
  });
  tearDown(() => temp.delete(recursive: true));

  test('controls hidden: nothing over the video is told to redraw as it plays;'
      ' shown: once a second', () async {
    final rig = FakeHost();
    final playback = SessionPlayback(rig.host,
        hideAfter: const Duration(milliseconds: 100));
    var frames = 0;
    void counted() => frames++;
    playback.frame.addListener(counted);
    await playback.openItem(PlayableItem(videoPath: video));
    final session = playback.session!;
    final driver = rig.drivers.single;
    expect(playback.transport.value.status, 'playing');
    expect(playback.playIntent, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(playback.showControls, isFalse);
    frames = 0;
    // The kernel on course for 1.5 s, and a drift the clock corrects.
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      driver.sample(session.position + const Duration(milliseconds: 5));
    }
    driver.sample(session.position + const Duration(milliseconds: 300));
    expect(frames, 0);
    // The pointer on the controls keeps them up: a redraw a second.
    playback.hover(true);
    expect(playback.showControls, isTrue);
    frames = 0;
    await Future<void>.delayed(const Duration(milliseconds: 2050));
    expect(frames, inInclusiveRange(2, 3));
    playback.hover(false);
    playback.frame.removeListener(counted);
    await playback.close(reason: 'test');
    await playback.dispose();
  });

  test('the play button answers at once; the transport once the kernel says',
      () async {
    final rig = FakeHost();
    final playback = SessionPlayback(rig.host);
    await playback.openItem(PlayableItem(videoPath: video));
    final statuses = <String>[];
    playback.transport.addListener(() => statuses.add(playback.transport.value.status));
    playback.togglePlay();
    expect(playback.playIntent, isFalse);
    await pumpEventQueue();
    expect(statuses, ['paused']);
    await playback.close(reason: 'test');
    expect(playback.transport.value.status, 'idle');
    expect(playback.hasVideo, isFalse);
    await playback.dispose();
  });

  test('playback.state, set_paused, seek and wait over the session', () async {
    final rig = FakeHost();
    final playback = SessionPlayback(rig.host);
    await playback.openItem(PlayableItem(videoPath: video),
        start: const Duration(minutes: 1));
    final state = playback.port.snapshot().toJson();
    expect(state['status'], 'playing');
    expect(state['paused'], isFalse);
    expect(state['hasVideo'], isTrue);
    expect(state['positionMs'], closeTo(60000, 300));
    expect(state['durationMs'], 24 * 60000);
    expect((state['kernel'] as Map)['id'], 'mdk');
    final id = state['sessionId'] as String;
    expect(id, startsWith('internal:$pid:'));

    final waiting = playback.controls.inspect(
        'playback.wait', {'sessionId': id, 'until': 'paused', 'timeoutMs': 3000});
    await pumpEventQueue();
    await playback.port.setPaused(true);
    final waited = await waiting;
    expect(waited['outcome'], 'matched');
    expect((waited['state'] as Map)['paused'], isTrue);

    await playback.port.seekTo(const Duration(minutes: 16, seconds: 48));
    expect(playback.port.snapshot().positionMs, 1008000);

    final timedOut = await playback.controls.inspect('playback.wait',
        {'sessionId': id, 'until': 'playing', 'timeoutMs': 50});
    expect(timedOut['outcome'], 'timeout');
    final changed = await playback.controls
        .inspect('playback.wait', {'sessionId': 'other', 'until': 'ready'});
    expect(changed['outcome'], 'session_changed');

    final closed = await playback.controls.close({});
    expect(closed['closed'], isTrue);
    await playback.dispose();
  });

  test('what the layer does not do yet is unavailable, with the reason',
      () async {
    final rig = FakeHost();
    final playback = SessionPlayback(rig.host);
    Future<Failure> failure(Future<Object?> Function() call) async {
      try {
        await call();
      } on Failure catch (f) {
        return f;
      }
      fail('expected a failure');
    }

    // Nothing open: the tracks are not there, as with Classic.
    final tracks = await failure(() => playback.controls.tracks({}));
    expect(tracks.code, FailureCode.unavailable);
    final cues = await failure(
        () => playback.controls.inspect('subtitle.cues', {'sessionId': 'x'}));
    expect(cues.code, FailureCode.conflict);
    // Danmaku are the layer's own: with nothing open the page is empty.
    final entries = await playback.controls.inspect('danmaku.entries', {});
    expect(entries['sessionId'], isNull);
    expect(entries['total'], 0);
    expect(entries['items'], isEmpty);
    final network = await failure(() => playback.openItem(
        PlayableItem(videoPath: 'jellyfin://item-1')));
    expect(network.code, FailureCode.unavailable);
    expect(network.details['stage'], 'source_resolution');
    await playback.dispose();
  });

  test('the same actions stay in the catalogue when unavailable', () {
    final inner = PlaybackControlsCapability(SessionControls(
        SessionPlayback(FakeHost().host)));
    final wrapped = NotInPlaybackLayer(inner, 'x', 'not yet');
    expect([for (final a in wrapped.actions) a.spec.id],
        [for (final a in inner.actions) a.spec.id]);
    expect([for (final a in wrapped.actions) a.spec.input.toJsonSchema()],
        [for (final a in inner.actions) a.spec.input.toJsonSchema()]);
  });

  testWidgets('the timeline moves by painting: the clock read, nothing rebuilt',
      (tester) async {
    var at = const Duration(minutes: 3);
    final tick = ChangeNotifier();
    var rebuilt = 0;
    final previous = debugOnRebuildDirtyWidget;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 600,
          child: PlayerTimeline(
            live: () => at,
            repaint: tick,
            duration: const Duration(minutes: 24),
            onSeek: (_) {},
          ),
        ),
      ),
    ));
    debugOnRebuildDirtyWidget = (element, builtOnce) => rebuilt++;
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    final paint = find.descendant(
        of: find.byType(PlayerTimeline), matching: find.byType(CustomPaint));
    final render = tester.renderObject<RenderCustomPaint>(paint.last);
    expect(render.debugNeedsPaint, isFalse);
    for (var i = 0; i < 10; i++) {
      at += const Duration(seconds: 1);
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      tick.notifyListeners();
      expect(render.debugNeedsPaint, isTrue);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(rebuilt, 0);
  });

  testWidgets('the stage draws the surface; a click plays or pauses',
      (tester) async {
    final host = _StageHost();
    await tester.pumpWidget(
        MaterialApp(home: NextVideoStage(host: host)));
    expect(find.byType(Texture), findsNothing);
    host.picture.value = const TextureSurface(3, width: 1280, height: 720);
    await tester.pump();
    final texture = tester.widget<Texture>(find.byType(Texture));
    expect(texture.textureId, 3);
    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(ratio.aspectRatio, closeTo(16 / 9, 0.001));
    await tester.tap(find.byType(NextVideoStage));
    await tester.pump(const Duration(milliseconds: 400));
    expect(host.toggles, 1);
    host.picture.value = null;
    await tester.pump();
    expect(find.byType(Texture), findsNothing);
  });
}

final class _StageHost implements VideoStageHost {
  final picture = ValueNotifier<VideoSurface?>(null);
  @override
  ValueListenable<VideoSurface?> get surface => picture;
  @override
  final ValueNotifier<OverlayFrame?> subtitleOverlay = ValueNotifier(null);
  int toggles = 0;
  @override
  void togglePlay() => toggles++;
  @override
  Future<void> toggleFullscreen() async {}
  @override
  void pointerMoved() {}
  @override
  bool key(KeyEvent event) => false;
}
