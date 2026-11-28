import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('erika_flutter/player');
  const events = MethodChannel('erika_flutter/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var requested = 0;
  var rejectMode = false;
  Completer<void>? nativeMute;
  var backend = 9;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    requested = 0;
    rejectMode = false;
    nativeMute = null;
    backend = 9;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return 31;
      if (call.method == 'setUpscaler') {
        if (rejectMode) throw PlatformException(code: 'rejected');
        requested = (call.arguments as Map)['mode'] as int;
      }
      if (call.method == 'setDanmakuEnabled' &&
          (call.arguments as Map)['enabled'] == false) {
        await nativeMute?.future;
      }
      if (call.method == 'getUpscalerStatus') {
        return {'requestedMode': requested, 'activeBackend': backend};
      }
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test(
      'existing saved modes keep their indices and all native modes are represented',
      () {
    expect(PlayerUpscalerMode.values.take(4).map((mode) => mode.name),
        ['off', 'erikaArtCnnC4F16', 'erikaArtCnnC4F32', 'erikaArtCnnC4F16Ds']);
    expect(PlayerUpscalerMode.values.map((mode) => mode.nativeName),
        ErikaUpscalerMode.values.map((mode) => mode.name));
  });

  test('new modes reach the native API and new backend status is preserved',
      () async {
    final player = ErikaPlayerAdapter();
    try {
      for (final mode in ErikaPlayerAdapter.availableUpscalerModes) {
        await player.setUpscaler(mode);
        expect(requested,
            ErikaUpscalerMode.values.byName(mode.nativeName).nativeValue);
        final status = await player.getUpscalerStatus();
        expect(status.requestedMode, mode);
        expect(status.activeBackend, PlayerUpscalerBackendStatus.metalFx);
      }
    } finally {
      await player.disposeAsync();
    }
  });

  test('rejected On keeps native ownership', () async {
    final player = ErikaPlayerAdapter();
    addTearDown(player.disposeAsync);
    rejectMode = true;
    await player.setUpscaler(PlayerUpscalerMode.erikaArtCnnC4F16);
    expect(player.supportsNativeDanmaku, isTrue);
  });

  test('rejected Off keeps Flutter ownership', () async {
    final player = ErikaPlayerAdapter();
    addTearDown(player.disposeAsync);
    await player.setUpscaler(PlayerUpscalerMode.erikaArtCnnC4F16);
    expect(player.supportsNativeDanmaku, isFalse);
    rejectMode = true;
    await player.setUpscaler(PlayerUpscalerMode.off);
    expect(player.supportsNativeDanmaku, isFalse);
  });

  test('accepted scalar fallback waits for native mute before showing Flutter',
      () async {
    final player = ErikaPlayerAdapter();
    addTearDown(player.disposeAsync);
    await player.getUpscalerStatus();
    nativeMute = Completer<void>();
    backend = ErikaUpscalerBackendStatus.scalar.nativeValue;
    final update = player.setUpscaler(PlayerUpscalerMode.erikaArtCnnC4F16);
    await Future<void>.delayed(Duration.zero);
    try {
      expect(player.supportsNativeDanmaku, isTrue);
      expect(calls.where((call) => call.method == 'setDanmakuEnabled'),
          hasLength(1));
    } finally {
      nativeMute!.complete();
      await update;
    }
    expect(player.supportsNativeDanmaku, isFalse);
    await player.setDanmakuEnabled(true);
    expect(
        calls
            .where((call) => call.method == 'setDanmakuEnabled')
            .map((call) => (call.arguments as Map)['enabled']),
        [false]);
  });

  test('native visibility resumes after Flutter removes its overlay', () async {
    final player = ErikaPlayerAdapter();
    addTearDown(player.disposeAsync);
    final binding = TestWidgetsFlutterBinding.instance;
    await player.setUpscaler(PlayerUpscalerMode.erikaArtCnnC4F16);
    await player.setUpscaler(PlayerUpscalerMode.off);
    expect(player.supportsNativeDanmaku, isTrue);
    final enable = player.setDanmakuEnabled(true);
    await Future<void>.delayed(Duration.zero);
    final visibility = calls
        .where((call) => call.method == 'setDanmakuEnabled')
        .map((call) => (call.arguments as Map)['enabled']);
    expect(visibility, [false]);
    binding.handleBeginFrame(null);
    binding.handleDrawFrame();
    await enable;
    expect(visibility, [false, true]);
  });

  test('a newer visibility toggle wins during a return to native', () async {
    final player = ErikaPlayerAdapter();
    addTearDown(player.disposeAsync);
    final binding = TestWidgetsFlutterBinding.instance;
    await player.setUpscaler(PlayerUpscalerMode.erikaArtCnnC4F16);
    await player.setUpscaler(PlayerUpscalerMode.off);
    final enable = player.setDanmakuEnabled(true);
    await Future<void>.delayed(Duration.zero);
    await player.setDanmakuEnabled(false);
    binding.handleBeginFrame(null);
    binding.handleDrawFrame();
    await enable;
    expect(
        calls
            .where((call) => call.method == 'setDanmakuEnabled')
            .map((call) => (call.arguments as Map)['enabled']),
        [false, false]);
  });

  test('custom model bytes are loaded before selecting custom mode', () async {
    final directory = await Directory.systemTemp.createTemp('erika-model-');
    final file = File('${directory.path}/sample.esr');
    final bytes = Uint8List.fromList([1, 2, 3]);
    await file.writeAsBytes(bytes);
    final player = ErikaPlayerAdapter();
    try {
      await player.loadUpscalerModelFile(file.path);
      await player.setUpscaler(PlayerUpscalerMode.erikaCustom);
      final loaded =
          calls.singleWhere((call) => call.method == 'loadUpscalerModel');
      expect((loaded.arguments as Map)['data'], bytes);
      expect((loaded.arguments as Map)['name'], 'sample.esr');
      expect(calls.indexOf(loaded),
          lessThan(calls.indexWhere((call) => call.method == 'setUpscaler')));
    } finally {
      await player.disposeAsync();
      await directory.delete(recursive: true);
    }
  });
}
