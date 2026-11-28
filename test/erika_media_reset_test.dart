import 'dart:async';
import 'dart:io';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  Completer<void>? holdScreenshot, holdFirstAttach;
  bool emitDuration = false;
  bool reportSubtitles = true;
  final embeddedSubtitle = {
    'id': 4,
    'kind': ErikaTrackKind.subtitle.index,
    'selected': true,
    'language': 'chi',
    'title': 'Chinese',
  };
  Completer<void>? holdPlayback;
  String? heldMethod;

  setUp(() {
    holdScreenshot = holdFirstAttach = null;
    emitDuration = false;
    reportSubtitles = true;
    heldMethod = null;
    holdPlayback = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    nextId = 0;
    calls = [];
    holdOpen = holdDispose = null;
    failOpen = false;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == heldMethod) await holdPlayback?.future;
      if (call.method == 'create') return ++nextId;
      if (call.method == 'open' && call.arguments['playerId'] == 1) {
        if (failOpen) throw PlatformException(code: 'OPEN_FAILED');
        await holdOpen?.future;
      }
      if (call.method == 'attachOverlay' &&
          holdFirstAttach != null &&
          calls.where((c) => c.method == 'attachOverlay').length == 1) {
        await holdFirstAttach!.future;
      }
      if (call.method == 'screenshot') await holdScreenshot?.future;
      if (call.method == 'open' && emitDuration) {
        final id = call.arguments['playerId'];
        unawaited(messenger.handlePlatformMessage(
            events.name,
            const StandardMethodCodec().encodeSuccessEnvelope({
              'playerId': id,
              'kind': ErikaEventKind.tracksChanged.index,
              if (reportSubtitles) 'trackList': [embeddedSubtitle],
              'durationMicros': 12000000,
              'positionMicros': 1000,
            }),
            (_) {}));
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

  Future<void> emit(int id, ErikaEventKind kind,
      {int position = 0, bool withSubtitles = false}) async {
    final delivered = Completer<void>();
    await messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'playerId': id,
          'kind': kind.index,
          if (withSubtitles) 'trackList': [embeddedSubtitle],
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

  test(
      'kernel swap keeps the current player listenable until its owner disposes it',
      () async {
    final first = Player.withDelegate(ErikaPlayerAdapter())
      ..media = 'first.mkv';
    await first.prepare();
    expect(first.resetAfterMediaExit(switchingKernel: true), same(first));
    void listener() {}
    first.buffering.addListener(listener);
    first.textureId.addListener(listener);
    first.buffering.removeListener(listener);
    first.textureId.removeListener(listener);
    expect(calls.where((call) => call.method == 'dispose'), isEmpty);
    await first.disposeAsync();
  });

  test('retired player ignores stale seeks and selections', () async {
    final first = Player.withDelegate(ErikaPlayerAdapter())
      ..media = 'first.mkv';
    await first.prepare();
    final next = first.resetAfterMediaExit();
    try {
      await first.seekAndWait(position: 3000);
      expect(first.position, 0);
      first.activeSubtitleTracks = [4];
      expect(first.activeSubtitleTracks, isEmpty);
      expect(await first.snapshot(), isNull);
      final replacement = first.resetAfterMediaExit();
      expect(replacement, isNot(same(first)));
      await replacement.disposeAsync();
    } finally {
      await first.disposeAsync();
      await next.disposeAsync();
    }
  });

  Future<({VideoPlayerState state, File a, File b})>
      createPlaybackFixture() async {
    final directory = await Directory.systemTemp.createTemp('erika_exit_');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({
      'player_kernel_type': PlayerKernelType.erika.index,
    });
    await PlayerFactory.initialize();
    final state = VideoPlayerState();
    await state.initialDanmakuSettingsReady;
    emitDuration = true;
    final a = await File('${directory.path}/a.mkv').create();
    final b = await File('${directory.path}/b.mkv').create();
    addTearDown(() async {
      if (holdScreenshot != null && !holdScreenshot!.isCompleted)
        holdScreenshot!.complete();
      state.dispose();
      messenger.setMockMethodCallHandler(paths, null);
      await directory.delete(recursive: true);
    });
    return (state: state, a: a, b: b);
  }

  Future<void> runPlayback(Player player, String method) =>
      method == 'play' ? player.playDirectly() : player.pauseDirectly();

  for (final method in ['play', 'pause']) {
    test('$method on a retired adapter never reaches the plugin', () async {
      final first = Player.withDelegate(ErikaPlayerAdapter())..media = 'a';
      await first.prepare();
      if (method == 'pause') await first.playDirectly();
      final next = first.resetAfterMediaExit();
      addTearDown(next.disposeAsync);
      final count = calls.where((c) => c.method == method).length;
      await runPlayback(first, method);
      expect(calls.where((c) => c.method == method), hasLength(count));
    });

    test('active $method still reports a native error', () async {
      final active = Player.withDelegate(ErikaPlayerAdapter())..media = 'a';
      addTearDown(active.disposeAsync);
      await active.prepare();
      if (method == 'pause') await active.playDirectly();
      heldMethod = method;
      holdPlayback = Completer<void>();
      final error = expectLater(
          runPlayback(active, method), throwsA(isA<PlatformException>()));
      await Future<void>.delayed(Duration.zero);
      holdPlayback!.completeError(PlatformException(code: 'PLAYBACK_FAILED'));
      await error;
    });

    for (final rejected in [false, true]) {
      test('retirement cancels a pending $method (native rejection: $rejected)',
          () async {
        final first = Player.withDelegate(ErikaPlayerAdapter())..media = 'a';
        await first.prepare();
        if (method == 'pause') await first.playDirectly();
        final previous = first.state;
        heldMethod = method;
        holdPlayback = Completer<void>();
        final pending = runPlayback(first, method);
        await Future<void>.delayed(Duration.zero);
        expect(calls.where((c) => c.method == method), isNotEmpty);
        final next = first.resetAfterMediaExit();
        addTearDown(next.disposeAsync);
        if (rejected) {
          holdPlayback!.completeError(PlatformException(code: 'RETIRED'));
        } else {
          holdPlayback!.complete();
        }
        await pending;
        expect(first.state, previous);
        expect(next.state, PlaybackState.stopped);
      });
    }

    test(
        'a late native $method completion cannot change the idle UI after exit',
        () async {
      final fixture = await createPlaybackFixture();
      final state = fixture.state;
      await state.initializePlayer(fixture.a.path, manualMatchHandled: true);
      if (method == 'play') {
        state.pause();
        await Future<void>.delayed(Duration.zero);
        expect(state.status, PlayerStatus.paused);
      }
      final previous = calls.where((c) => c.method == method).length;
      heldMethod = method;
      holdPlayback = Completer<void>();
      if (method == 'play') {
        state.play();
      } else {
        state.pause();
      }
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c.method == method), hasLength(previous + 1));
      await state.resetPlayer();
      expect(state.status, PlayerStatus.idle);
      holdPlayback!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(state.status, PlayerStatus.idle);
    });
  }

  for (final lateTrack in [false, true]) {
    test(
        'a fresh player restores subtitle style with no initial tracks (late track: $lateTrack)',
        () async {
      final fixture = await createPlaybackFixture();
      final state = fixture.state;
      await state.initializePlayer(fixture.a.path, manualMatchHandled: true);
      await state.setSubtitleBold(true);
      expect(state.player.activeSubtitleTracks, [0]);
      await state.resetPlayer();
      reportSubtitles = false;
      await state.initializePlayer(fixture.b.path, manualMatchHandled: true);
      expect(state.player.activeSubtitleTracks, isEmpty);
      final newId =
          calls.lastWhere((c) => c.method == 'open').arguments['playerId'];
      if (lateTrack) {
        await emit(newId, ErikaEventKind.tracksChanged, withSubtitles: true);
        expect(state.player.activeSubtitleTracks, [0]);
        expect(
            calls.where((c) =>
                c.method == 'setSubtitleStyle' &&
                c.arguments['playerId'] == newId &&
                c.arguments['bold'] == true),
            isNotEmpty);
      }
      reportSubtitles = true;
      await state.initializePlayer(fixture.a.path, manualMatchHandled: true);
      expect(state.player.activeSubtitleTracks, [0]);
      final commands =
          calls.where((c) => c.arguments?['playerId'] == newId).toList();
      expect(commands.where((c) => c.method == 'open'), hasLength(2));
      expect(
          commands.where((c) =>
              c.method == 'setSubtitleStyle' && c.arguments['bold'] == true),
          isNotEmpty);
    });
  }

  test(
      'reopening during the exit screenshot uses a new native player before the screenshot finishes',
      () async {
    final (:state, :a, :b) = await createPlaybackFixture();
    final first = state.player;
    await state.initializePlayer(a.path, manualMatchHandled: true);
    expect(state.currentVideoPath, a.path, reason: state.error);
    expect(state.hasVideo, isTrue, reason: state.error);
    await state.setPlaybackRate(1.5);
    await state.setSubtitleBold(true);
    await state.setRememberDanmakuOffset(true);
    state.setManualDanmakuOffset(0.75);
    holdScreenshot = Completer<void>();
    await state.handleBackButton();
    expect(calls.any((call) => call.method == 'screenshot'), isTrue);
    final exiting = state.resetPlayer();
    await state.initializePlayer(b.path, manualMatchHandled: true);
    expect(state.player, isNot(same(first)));
    final newId =
        calls.lastWhere((c) => c.method == 'open').arguments['playerId'];
    expect(
        newId,
        isNot(
            calls.firstWhere((c) => c.method == 'open').arguments['playerId']));
    final newCalls =
        calls.where((call) => call.arguments?['playerId'] == newId).toList();
    final methods = newCalls.map((call) => call.method).toList();
    final play = methods.indexOf('play');
    expect(play, greaterThanOrEqualTo(0));
    expect(methods.indexOf('setPlaybackRate'), inInclusiveRange(0, play - 1));
    expect(
        newCalls
            .firstWhere((call) => call.method == 'setPlaybackRate')
            .arguments['rate'],
        1.5);
    expect(methods.indexOf('setSubtitleStyle'), inInclusiveRange(0, play - 1));
    expect(
        newCalls
            .firstWhere((call) => call.method == 'setSubtitleStyle')
            .arguments['bold'],
        isTrue);
    expect(
        newCalls
            .lastWhere((call) => call.method == 'setDanmakuGlobalOffset')
            .arguments['offsetMicros'],
        750000);
    expect(
        newCalls
            .lastWhere((call) => call.method == 'setVolume')
            .arguments['volume'],
        greaterThan(0));

    holdScreenshot!.complete();
    await exiting;
    expect(state.currentVideoPath, b.path);
    // An episode switch without an explicit exit keeps its existing player.
    final second = state.player;
    await state.initializePlayer(a.path, manualMatchHandled: true);
    expect(state.player, same(second));
    expect(calls.lastWhere((c) => c.method == 'open').arguments['playerId'],
        newId);
  });

  testWidgets(
      'a mounted surface can attach the new player while the old attach is pending',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'player_kernel_type': PlayerKernelType.videoPlayer.index,
    });
    await PlayerFactory.initialize();
    final state = VideoPlayerState();
    state.player = Player.withDelegate(ErikaPlayerAdapter())..media = 'a.mkv';
    holdFirstAttach = Completer<void>();
    Future<void> renderSurface() => tester.pumpWidget(KeyedSubtree(
          key: ValueKey(state.playerSurfaceGeneration),
          child: state.player.buildPlatformVideoSurface()!,
        ));
    try {
      await renderSurface();
      await tester.pump();
      expect(calls.where((c) => c.method == 'attachOverlay'), hasLength(1));
      await state.resetPlayer();
      state.player.media = 'b.mkv';
      await renderSurface();
      await tester.pump();
      final attached = calls
          .where((c) => c.method == 'attachOverlay')
          .map((c) => c.arguments['playerId'])
          .toList();
      expect(attached, hasLength(2));
      expect(attached.last, isNot(attached.first));
    } finally {
      holdFirstAttach!.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      state.dispose();
      debugDefaultTargetPlatformOverride = null;
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
