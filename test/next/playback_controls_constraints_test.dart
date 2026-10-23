import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/player/classic/classic_playback_controls.dart';
import 'package:nipaplay/next/capabilities/playback_controls_capability.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import 'test_support.dart';

class _Delegate extends Fake implements AbstractPlayer {
  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 10000, audio: [
        PlayerAudioStreamInfo(
            codec: PlayerAudioCodecParams(), rawRepresentation: 'audio')
      ], subtitle: []);
  @override
  List<int> get activeAudioTracks => [0];
}

class _Video extends Fake implements VideoPlayerState {
  @override
  bool get hasVideo => true;
  @override
  String? get currentVideoPath => '/tmp/x13.mkv';
  @override
  final Player player = Player.withDelegate(_Delegate());
  @override
  Duration get duration => const Duration(seconds: 10);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Harness harness;
  setUp(() => harness =
      Harness([PlaybackControlsCapability(ClassicPlaybackControls(_Video()))]));

  test('capture never overwrites an existing artifact', () async {
    final directory = await Directory.systemTemp.createTemp('x13-output-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/keep.png').writeAsString('existing');
    await invokeFailed(harness, 'playback.capture',
        {'kind': 'screenshot', 'outputPath': file.path}, FailureCode.conflict);
    expect(await file.readAsString(), 'existing');
  });

  test('track indexes are validated before changing the player', () async {
    await invokeFailed(
        harness,
        'playback.select_track',
        {'kind': 'audio', 'origin': 'embedded', 'index': 1},
        FailureCode.notFound);
    await invokeFailed(
        harness,
        'playback.select_track',
        {'kind': 'audio', 'origin': 'embedded', 'index': -1},
        FailureCode.invalidInput);
  });

  test('invalid GIF intervals cannot start an export', () async {
    for (final interval in [(1000, 1000), (1000, 11000)]) {
      await invokeFailed(
          harness,
          'playback.capture',
          {
            'kind': 'gif',
            'outputPath': '/tmp/x13-invalid.gif',
            'startMs': interval.$1,
            'endMs': interval.$2
          },
          FailureCode.invalidInput);
    }
  });

  test('external telemetry is a read action and never invents progress',
      () async {
    expect(harness.lookup('playback.external_state')!.spec.effect, Effect.read);
    final state = await invokeCompleted(harness, 'playback.external_state', {});
    expect(state['active'], false);
    expect(state['positionMs'], isNull);
    expect(state['telemetryAvailable'], false);
  });
}
