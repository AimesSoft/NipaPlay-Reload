import 'dart:async';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('erika_flutter/player');
  const events = MethodChannel('erika_flutter/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('exit discards old events while native stop is pending', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final stop = Completer<void>();
    final stopRequested = Completer<void>();
    var opens = 0;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') return 9;
      if (call.method == 'open') opens++;
      if (call.method == 'stop') {
        stopRequested.complete();
        await stop.future;
      }
      return null;
    });
    Future<void> emit(ErikaEventKind kind,
        {int position = 0,
        ErikaPlaybackState state = ErikaPlaybackState.paused}) async {
      final delivered = Completer<void>();
      await messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope({
            'playerId': 9,
            'kind': kind.index,
            'state': state.index,
            'positionMicros': position * 1000,
          }),
          (_) => delivered.complete());
      await delivered.future;
      await Future<void>.delayed(Duration.zero);
    }

    final player = ErikaPlayerAdapter();
    try {
      player.setMedia('first.mkv', PlayerMediaType.video);
      await player.prepare();
      await player.seekAndWait(position: 10000);
      var resetFinished = false;
      final reset =
          player.stopAndResetMedia().then((_) => resetFinished = true);
      await stopRequested.future;
      await emit(ErikaEventKind.positionChanged, position: 2200);
      expect(player.position, 0);
      expect(resetFinished, isFalse);
      stop.complete();
      await reset;
      player.setMedia('second.mkv', PlayerMediaType.video);
      final reopened = player.prepare();
      // The old Opening can itself be buffered on the platform channel.
      await emit(ErikaEventKind.stateChanged,
          state: ErikaPlaybackState.opening);
      await emit(ErikaEventKind.positionChanged, position: 2200);
      expect(player.position, 0);
      expect(opens, 1);
      // Reopening before the previous Stopped event was polled would
      // discard that event in liberika. Only now may the second open run.
      await emit(ErikaEventKind.stateChanged,
          state: ErikaPlaybackState.stopped);
      await reopened;
      expect(opens, 2);
      await emit(ErikaEventKind.positionChanged, position: 2400);
      expect(player.position, 0);
      await emit(ErikaEventKind.stateChanged,
          state: ErikaPlaybackState.opening);
      await emit(ErikaEventKind.positionChanged, position: 150);
      expect(player.position, 150);
    } finally {
      if (!stop.isCompleted) stop.complete();
      await player.disposeAsync();
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(events, null);
    }
  });
}
