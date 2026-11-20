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
  late List<MethodCall> calls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls = [];
    messenger.setMockMethodCallHandler(playerChannel, (call) async {
      calls.add(call);
      return call.method == 'create' ? 13 : null;
    });
    messenger.setMockMethodCallHandler(eventsChannel, (_) async => null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(playerChannel, null);
    messenger.setMockMethodCallHandler(eventsChannel, null);
  });

  Future<void> emit(
    ErikaEventKind kind, {
    int positionMs = 0,
    ErikaPlaybackState state = ErikaPlaybackState.playing,
    bool buffering = false,
  }) async {
    final delivered = Completer<void>();
    messenger.handlePlatformMessage(
      eventsChannel.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'playerId': 13,
        'kind': kind.index,
        'state': state.index,
        'positionMicros': positionMs * 1000,
        'buffering': buffering,
      }),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
  }

  Future<ErikaPlayerAdapter> playing() async {
    final player = ErikaPlayerAdapter();
    player.setMedia(
        'https://example.test/jellyfin/video.mkv', PlayerMediaType.video);
    await player.prepare();
    await emit(ErikaEventKind.stateChanged);
    await emit(ErikaEventKind.positionChanged, positionMs: 30000);
    return player;
  }

  test('entering long-press speed does not apply it to elapsed normal playback',
      () async {
    final player = await playing();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final before = player.position;
      final elapsed = before - 30000;
      player.setPlaybackRate(4);
      expect(player.position, lessThan(before + elapsed));
      await Future<void>.delayed(Duration.zero);
      expect(
        (calls.lastWhere((call) => call.method == 'setPlaybackRate').arguments
            as Map)['rate'],
        4,
      );
    } finally {
      await player.disposeAsync();
    }
  });

  test('releasing long-press speed preserves progress and a following seek',
      () async {
    final player = await playing();
    try {
      player.setPlaybackRate(4);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final beforeRelease = player.position;
      player.setPlaybackRate(1);
      final afterRelease = player.position;
      expect(afterRelease, greaterThanOrEqualTo(beforeRelease));

      final forwardTarget = afterRelease + 5000;
      await player.seekAndWait(position: forwardTarget);
      expect(
        (calls.lastWhere((call) => call.method == 'seek').arguments
            as Map)['positionMicros'],
        forwardTarget * 1000,
      );
      await emit(ErikaEventKind.positionChanged, positionMs: forwardTarget);
      expect(player.position, greaterThanOrEqualTo(forwardTarget));

      // A real backwards seek must still accept a smaller native position.
      await player.seekAndWait(position: 5000);
      await emit(ErikaEventKind.positionChanged, positionMs: 5000);
      expect(player.position, inInclusiveRange(5000, 6000));
    } finally {
      await player.disposeAsync();
    }
  });

  test('rate changes during buffering keep the frozen anchor', () async {
    final player = await playing();
    try {
      player.setPlaybackRate(4);
      await emit(ErikaEventKind.bufferingChanged, buffering: true);
      final frozen = player.position;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      player.setPlaybackRate(1);
      expect(player.position, frozen);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(player.position, frozen);

      // Recovery remains authoritative, including a correction behind the UI.
      await emit(ErikaEventKind.positionChanged, positionMs: 29900);
      await emit(ErikaEventKind.bufferingChanged);
      expect(player.position, inInclusiveRange(29900, 30000));
    } finally {
      await player.disposeAsync();
    }
  });

  test('rate changes while paused do not count the paused interval', () async {
    final player = await playing();
    try {
      await emit(ErikaEventKind.stateChanged, state: ErikaPlaybackState.paused);
      await emit(ErikaEventKind.positionChanged, positionMs: 30000);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      player.setPlaybackRate(4);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      player.setPlaybackRate(1);
      expect(player.position, 30000);
    } finally {
      await player.disposeAsync();
    }
  });
}
