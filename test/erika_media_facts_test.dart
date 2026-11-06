import 'dart:async';
import 'dart:convert';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/player/core/arbiter.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/kernel/erika_driver.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const playerChannel = MethodChannel('erika_flutter/player');
  const eventsChannel = MethodChannel('erika_flutter/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Object? containerReply;
  Object? tracksReply;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    containerReply = jsonEncode({
      'ok': true,
      'status': 0,
      'value': {
        'format': 'matroska,webm',
        'bitRate': 8000000,
        'mediaOpen': true,
      },
    });
    tracksReply = jsonEncode({
      'ok': true,
      'status': 0,
      'value': [
        {'id': 1, 'kind': 0, 'selected': true, 'dolbyVisionProfile': 8},
        {'id': 2, 'kind': 1, 'selected': true, 'dolbyVisionProfile': null},
      ],
    });
    messenger.setMockMethodCallHandler(playerChannel, (call) async {
      if (call.method == 'create') return 9;
      if (call.method == 'invokeJson' &&
          (call.arguments as Map)['method'] == 'container') {
        return containerReply;
      }
      if (call.method == 'invokeJson' &&
          (call.arguments as Map)['method'] == 'tracks') {
        return tracksReply;
      }
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

  test('external subtitle failure cannot fail the Erika media open plan',
      () async {
    var subtitleCalls = 0;
    messenger.setMockMethodCallHandler(playerChannel, (call) async {
      if (call.method == 'create') return 9;
      if (call.method == 'addExternalSubtitle') {
        subtitleCalls++;
        throw PlatformException(
            code: 'ERIKA_ERROR', message: 'invalid subtitle');
      }
      return null;
    });
    final lease =
        await KernelArbiter().acquire(KernelOwner.next, reason: 'test');
    final driver =
        ErikaDriver(lease, const KernelConfig(kernel: KernelId.erika));
    try {
      driver.adapter.setMedia('test.mkv', PlayerMediaType.video);
      await driver.adapter.prepare();
      final tracks = await driver.planOpened(
        const KernelTrackPlan(subtitle: FileKernelSubtitle('broken.ass')),
        const MediaFacts(duration: Duration(minutes: 1)),
      );
      expect(tracks.subtitle, KernelSubtitle.none);
      expect(subtitleCalls, 0);
      // The later selection still reports the actual error to its caller.
      await expectLater(
          driver.switchSubtitle(const FileKernelSubtitle('broken.ass'), null),
          throwsA(isA<PlatformException>()));
      expect(subtitleCalls, 1);
      expect(driver.adapter.state, PlayerPlaybackState.paused);
    } finally {
      await driver.disposeKernel();
      lease.release();
    }
  });

  test('Erika tracks carry their bit rates, frame rate and dynamic range',
      () async {
    final player = await opened();
    try {
      expect(player.videoProfile, 'Main 10');
      expect(player.videoPixelFormat, 'yuv420p10le');
      expect(player.videoBitRate, 7000000);
      expect(player.videoDynamicRange, 'pq');
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

  test('the container comes from Erika once asked for', () async {
    final player = await opened();
    try {
      expect(player.containerFormat, isNull);
      await player.readMediaFacts();
      expect(player.containerFormat, 'matroska,webm');
      expect(player.containerBitRate, 8000000);
      expect(player.getDetailedMediaInfo()['container'],
          {'format': 'matroska,webm', 'bitRate': 8000000});
      // The container signals Dolby Vision; the PQ transfer says no more.
      expect(player.videoDynamicRange, 'dolby_vision');
      player.setMedia('next.mkv', PlayerMediaType.video);
      expect(player.containerFormat, isNull);
    } finally {
      player.dispose();
    }
  });

  test('an Erika without the container method leaves it unknown', () async {
    containerReply = jsonEncode({
      'ok': false,
      'status': 3,
      'code': 'unknown_method',
      'error': 'unsupported Erika presenter method: container',
    });
    final player = await opened();
    try {
      await player.readMediaFacts();
      expect(player.containerFormat, isNull);
      expect(player.containerBitRate, isNull);
    } finally {
      player.dispose();
    }
  });
}
