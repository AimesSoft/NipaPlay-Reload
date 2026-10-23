import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/perf/budget.dart';
import 'package:nipaplay/next/player/ports/session_playback.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_driver.dart';

/// The playback layer's main-isolate budget (player-core design §4.4) over
/// ten minutes of what MDK sends, fed as fast as it goes: every event the
/// session reduces and every command it takes stays far under B1, and with
/// the controls hidden nothing over the video is told to redraw (B3). The
/// thresholds are three times the budget, for a loaded CI machine; the
/// measured values are printed.
void main() {
  late Directory temp;
  late String video;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('player-budget-');
    video = '${temp.path}/ep.mkv';
    await File(video).writeAsString('not a video');
  });
  tearDown(() => temp.delete(recursive: true));

  test('ten minutes of kernel events: B1 per task, B3 with the controls hidden',
      () async {
    final rig = FakeHost();
    final playback =
        SessionPlayback(rig.host, hideAfter: const Duration(milliseconds: 1));
    var frames = 0;
    playback.frame.addListener(() => frames++);
    await playback.openItem(PlayableItem(videoPath: video));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(playback.showControls, isFalse);
    final session = playback.session!;
    final driver = rig.drivers.single;
    PlayerPerf.reset();
    frames = 0;

    // MDK read 4 times a second for 10 minutes; one in 50 off course (a
    // drift sample), a buffering blip a minute.
    var position = session.position;
    for (var i = 0; i < 4 * 600; i++) {
      position += const Duration(milliseconds: 250);
      if (i % 50 == 0) {
        driver.sample(position + const Duration(milliseconds: 60));
      }
      if (i % 240 == 0) {
        driver.emit((seq, at) => KernelBuffering(driver.instance, seq, at, true));
        driver.emit((seq, at) => KernelBuffering(driver.instance, seq, at, false));
      }
    }
    // Hidden controls: the transport did not change, nothing redraws.
    final quiet = frames;
    // Commands as a person gives them.
    for (var i = 0; i < 50; i++) {
      await PlayerPerf.span('test.pause', () => session.setPaused(true, origin: 'gui'));
      await PlayerPerf.span('test.play', () => session.setPaused(false, origin: 'gui'));
      await PlayerPerf.span(
          'test.seek', () => session.seek(Duration(seconds: 30 + i), origin: 'gui'));
      PlayerPerf.span('test.snapshot', playback.snapshot);
    }

    final read = PlayerPerf.read();
    final spans = read['spans'] as Map<String, Object?>;
    // ignore: avoid_print
    print('budget: ${{
      for (final e in spans.entries)
        e.key: {
          'n': (e.value as Map)['n'],
          'p99Us': (e.value as Map)['p99Us'],
          'maxUs': (e.value as Map)['maxUs']
        }
    }} quiet frames: $quiet');
    for (final name in ['session.kernel', 'facade.transport', 'facade.sync',
        'session.snapshot']) {
      final series = spans[name] as Map?;
      if (series == null) continue;
      expect(series['p99Us'] as int, lessThan(6000), reason: name);
    }
    expect(quiet, 0);
    await playback.close(reason: 'test');
    await playback.dispose();
  });
}
