import 'dart:async';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const playerChannel = MethodChannel('erika_flutter/player');
  const eventsChannel = MethodChannel('erika_flutter/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(
      playerChannel,
      (call) async => call.method == 'create' ? 9 : null,
    );
    messenger.setMockMethodCallHandler(eventsChannel, (_) async => null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(playerChannel, null);
    messenger.setMockMethodCallHandler(eventsChannel, null);
  });

  Future<void> emit(ErikaEventKind kind,
      {required int positionMs, bool buffering = false}) async {
    final delivered = Completer<void>();
    messenger.handlePlatformMessage(
      eventsChannel.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'playerId': 9,
        'kind': kind.index,
        'state': ErikaPlaybackState.playing.index,
        'positionMicros': positionMs * 1000,
        'buffering': buffering,
      }),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
  }

  test('Erika freezes interpolation until an authoritative recovery event',
      () async {
    final player = ErikaPlayerAdapter();
    try {
      player.setMedia('test.mkv', PlayerMediaType.video);
      await player.prepare();
      await Future<void>.delayed(Duration.zero);
      await emit(ErikaEventKind.stateChanged, positionMs: 1000);
      await emit(ErikaEventKind.positionChanged, positionMs: 1000);
      await emit(ErikaEventKind.bufferingChanged,
          positionMs: 0, buffering: true);
      expect(player.buffering.value, isTrue);
      expect(player.state, PlayerPlaybackState.playing);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      final frozenPosition = player.position;
      expect(frozenPosition, greaterThanOrEqualTo(1000));
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(player.position, frozenPosition);

      // An unrelated event's default false must not clear native buffering.
      await emit(ErikaEventKind.positionChanged, positionMs: 1000);
      expect(player.buffering.value, isTrue);
      await emit(ErikaEventKind.positionChanged, positionMs: 1010);
      await emit(ErikaEventKind.bufferingChanged, positionMs: 0);
      expect(player.buffering.value, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(player.position, greaterThanOrEqualTo(1040));
    } finally {
      await player.disposeAsync();
    }
  });
}
