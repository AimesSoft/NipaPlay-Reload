import 'dart:async';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('erika_flutter/player');
  const events = MethodChannel('erika_flutter/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late int nextId;
  Completer<void>? holdOpen, holdDispose;
  bool failOpen = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    nextId = 0;
    calls = [];
    holdOpen = holdDispose = null;
    failOpen = false;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return ++nextId;
      if (call.method == 'open' && call.arguments['playerId'] == 1) {
        if (failOpen) throw PlatformException(code: 'OPEN_FAILED');
        await holdOpen?.future;
      }
      if (call.method == 'dispose' && call.arguments['playerId'] == 1) {
        await holdDispose?.future;
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  Future<void> emit(int id, ErikaEventKind kind, {int position = 0}) async {
    final delivered = Completer<void>();
    await messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'playerId': id,
          'kind': kind.index,
          'state': ErikaPlaybackState.playing.index,
          'positionMicros': position * 1000,
          'buffering': true,
        }),
        (_) => delivered.complete());
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
  }

  test('a missing Stopped and old queued events cannot affect the next media',
      () async {
    final first = Player.withDelegate(ErikaPlayerAdapter())
      ..media = 'first.mkv';
    await first.prepare();
    await first.seekAndWait(position: 10000);
    holdDispose = Completer<void>();
    final next = first.resetAfterMediaExit();
    try {
      expect(next, isNot(same(first)));
      expect(next.position, 0);
      expect(next.state, PlaybackState.stopped);
      expect(next.mediaInfo.duration, 0);
      next.media = 'second.mkv';
      await next.prepare().timeout(const Duration(seconds: 1));
      await emit(1, ErikaEventKind.positionChanged, position: 2200);
      await emit(1, ErikaEventKind.bufferingChanged);
      await emit(1, ErikaEventKind.stateChanged);
      expect(next.position, 0);
      expect(next.isBuffering, isFalse);
      expect(next.state, PlaybackState.paused);
      await emit(2, ErikaEventKind.positionChanged, position: 150);
      expect(next.position, 150);
      expect(calls.where((c) => c.method == 'dispose').length, 1);
      expect(calls.where((c) => c.method == 'stop'), isEmpty);
    } finally {
      holdDispose!.complete();
      await first.disposeAsync();
      await next.disposeAsync();
    }
  });

  test('an in-flight open does not block exit or reopening on a new ID',
      () async {
    holdOpen = Completer<void>();
    final first = Player.withDelegate(ErikaPlayerAdapter())..media = 'slow.mkv';
    final opening = first.prepare();
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'open').length, 1);
    final next = first.resetAfterMediaExit()..media = 'next.mkv';
    try {
      await next.prepare().timeout(const Duration(seconds: 1));
      expect(calls.where((c) => c.method == 'dispose').length, 1);
      expect(
          calls.lastWhere((c) => c.method == 'open').arguments['playerId'], 2);
    } finally {
      holdOpen!.complete();
      await opening;
      await first.disposeAsync();
      await next.disposeAsync();
    }
  });

  test('a second exit cancels an open queued behind native creation', () async {
    final first = Player.withDelegate(ErikaPlayerAdapter())
      ..media = 'first.mkv';
    await first.prepare();
    holdDispose = Completer<void>();
    final second = first.resetAfterMediaExit()..media = 'second.mkv';
    final queued = second.prepare();
    final third = second.resetAfterMediaExit();
    try {
      await queued;
      expect(
          calls.where((c) => c.method == 'open').map((c) => c.arguments['uri']),
          ['first.mkv']);
      expect(third.resetAfterMediaExit(), same(third));
      third.media = 'third.mkv';
      await third.prepare();
      expect(calls.lastWhere((c) => c.method == 'open').arguments['uri'],
          'third.mkv');
    } finally {
      holdDispose!.complete();
      await Future.wait(
          [first.disposeAsync(), second.disposeAsync(), third.disposeAsync()]);
    }
  });

  test('idle and failed open can be followed by another media', () async {
    final first = Player.withDelegate(ErikaPlayerAdapter());
    expect(first.resetAfterMediaExit(), same(first));
    expect(calls, isEmpty);
    failOpen = true;
    first.media = 'bad.mkv';
    await expectLater(first.prepare(), throwsA(isA<PlatformException>()));
    final next = first.resetAfterMediaExit()..media = 'next.mkv';
    await next.prepare();
    expect(next.state, PlaybackState.paused);
    await first.disposeAsync();
    await next.disposeAsync();
  });
}
