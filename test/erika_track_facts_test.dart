import 'dart:async';
import 'dart:io';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/subtitle_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const playerChannel = MethodChannel('erika_flutter/player');
  const eventsChannel = MethodChannel('erika_flutter/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(playerChannel, (call) async {
      if (call.method == 'create') return 9;
      return null;
    });
    messenger.setMockMethodCallHandler(eventsChannel, (_) async => null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(playerChannel, null);
    messenger.setMockMethodCallHandler(eventsChannel, null);
  });

  Future<void> emit(Map<String, Object?> event) async {
    final delivered = Completer<void>();
    messenger.handlePlatformMessage(
      eventsChannel.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'playerId': 9,
        'state': ErikaPlaybackState.ready.index,
        ...event,
      }),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
  }

  Future<ErikaPlayerAdapter> opened() async {
    final player = ErikaPlayerAdapter();
    player.setMedia('test.mkv', PlayerMediaType.video);
    await player.prepare();
    await Future<void>.delayed(Duration.zero);
    await emit({
      'kind': ErikaEventKind.tracksChanged.index,
      'trackList': [
        {
          'id': 1,
          'kind': ErikaTrackKind.video.index,
          'selected': true,
          'codec': 'hevc',
          'width': 3840,
          'height': 2160,
          'profile': 'Main 10',
          'pixelFormat': 'yuv420p10le',
          'bitRate': 7000000,
          'frameRateNumerator': 24000,
          'frameRateDenominator': 1001,
        },
        {
          'id': 2,
          'kind': ErikaTrackKind.audio.index,
          'selected': true,
          'codec': 'aac',
          'sampleRate': 48000,
          'channels': 2,
          'bitRate': 128000,
        },
      ],
    });
    await emit({
      'kind': ErikaEventKind.videoParamsChanged.index,
      'video': {'width': 3840, 'height': 2160, 'primaries': 3, 'transfer': 3},
    });
    return player;
  }

  test(
      'switching from an Erika external subtitle removes it before selecting the embedded track',
      () async {
    SharedPreferences.setMockInitialValues({});
    final enteredRemove = Completer<void>();
    final finishRemove = Completer<void>();
    final selections = <int?>[];
    messenger.setMockMethodCallHandler(playerChannel, (call) async {
      switch (call.method) {
        case 'create':
          return 9;
        case 'addExternalSubtitle':
          return 33;
        case 'removeSubtitleTrack':
          expect(call.arguments['trackId'], 33);
          enteredRemove.complete();
          await finishRemove.future;
        case 'selectSubtitleTrack':
          selections.add(call.arguments['trackId'] as int?);
      }
      return null;
    });
    final player = await opened();
    addTearDown(player.disposeAsync);
    await emit({
      'kind': ErikaEventKind.tracksChanged.index,
      'trackList': [
        {'id': 21, 'kind': ErikaTrackKind.subtitle.index, 'selected': false},
        {'id': 23, 'kind': ErikaTrackKind.subtitle.index, 'selected': false},
      ],
    });
    final manager = SubtitleManager(player: Player.withDelegate(player));
    final dir = await Directory.systemTemp.createTemp('erika-subtitle-switch-');
    addTearDown(() => dir.delete(recursive: true));
    final sup = await File('${dir.path}/track.sup').writeAsBytes([0]);
    await manager.addExternalSubtitleToStack(sup.path);
    await Future<void>.delayed(Duration.zero);
    expect(selections, contains(33));
    final first = manager.selectEmbeddedSubtitleTrack(0);
    await Future<void>.delayed(Duration.zero);
    expect(enteredRemove.isCompleted, isTrue);
    final last = manager.selectEmbeddedSubtitleTrack(1);
    expect(selections, [33]);
    finishRemove.complete();
    await Future.wait([first, last]);
    await Future<void>.delayed(Duration.zero);
    expect(selections, [33, null, 23]);
  });

  test('Erika tracks carry their bit rates and frame rate', () async {
    final player = await opened();
    try {
      // The parameters event that follows the track list keeps what it said.
      expect(player.mediaInfo.video!.single.codecName, 'hevc');
      expect(player.mediaInfo.video!.single.codec.width, 3840);
      final video = player.mediaInfo.video!.single.codec.name!;
      expect(video, contains('bitRate: 7000000'));
      expect(video, contains('23.976'));
      expect(video, contains('fps'));
      expect(player.mediaInfo.audio!.single.codec.bitRate, 128000);
      final tracks =
          player.getDetailedMediaInfo()['tracks'] as Map<String, dynamic>;
      expect((tracks['audio'] as List).single['bitRate'], 128000);
    } finally {
      player.dispose();
    }
  });
}
