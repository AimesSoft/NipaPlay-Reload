import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart'
    show Player;
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ModelFile extends Fake implements File {
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('erika_flutter/player');
  const events = MethodChannel('erika_flutter/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var requested = 0;
  var rejectMode = false;
  var rejectStatus = false;
  Completer<void>? loadingModel;
  Completer<void>? finishModel;
  Completer<void>? nativeMute;
  var backend = 9;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    requested = 0;
    rejectMode = false;
    rejectStatus = false;
    loadingModel = null;
    finishModel = null;
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
      if (call.method == 'loadUpscalerModel' && loadingModel != null) {
        if (!loadingModel!.isCompleted) {
          loadingModel!.complete();
          await finishModel!.future;
        }
      }
      if (call.method == 'getUpscalerStatus') {
        if (rejectStatus) throw PlatformException(code: 'no-status');
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

  test('disposing during native mute cancels the pending handoff', () async {
    final facade = Player.withDelegate(ErikaPlayerAdapter());
    await facade.getUpscalerStatus();
    nativeMute = Completer<void>();
    final enable = facade.setUpscaler(PlayerUpscalerMode.erikaArtCnnC4F16);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'setDanmakuEnabled'), hasLength(1));
    await facade.disposeAsync();
    nativeMute!.complete();
    expect(await enable, isFalse);
  });

  test('native status errors preserve an accepted handoff and cached mode',
      () async {
    final facade = Player.withDelegate(ErikaPlayerAdapter());
    addTearDown(facade.disposeAsync);
    rejectStatus = true;
    expect(
        await facade.setUpscaler(PlayerUpscalerMode.erikaArtCnnC4F16), isTrue);
    expect(facade.supportsNativeDanmaku, isFalse);
    expect((await facade.getUpscalerStatus())!.requestedMode,
        PlayerUpscalerMode.erikaArtCnnC4F16);
    expect(await facade.setUpscaler(PlayerUpscalerMode.off), isTrue);
    expect(facade.supportsNativeDanmaku, isTrue);
  });

  test('config visibility uses the current renderer and still applies styles',
      () async {
    final facade = Player.withDelegate(ErikaPlayerAdapter());
    addTearDown(facade.disposeAsync);
    await facade.setUpscaler(PlayerUpscalerMode.erikaArtCnnC4F16);
    await facade.setNativeDanmakuConfig(enabled: true, opacity: 0.7);
    final visibility = calls
        .where((c) => c.method == 'setDanmakuEnabled')
        .map((c) => (c.arguments as Map)['enabled']);
    expect(visibility, [false]);
    expect(calls.where((c) => c.method == 'setDanmakuConfig').last.arguments,
        containsPair('opacity', 0.7));
    await facade.setUpscaler(PlayerUpscalerMode.off);
    final enable = facade.setNativeDanmakuConfig(enabled: true);
    await Future<void>.delayed(Duration.zero);
    expect(visibility, [false]);
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleBeginFrame(null);
    binding.handleDrawFrame();
    await enable;
    expect(visibility, [false, true]);
  });

  Future<VideoPlayerState> createStateWithErika() async {
    final dir = await Directory.systemTemp.createTemp('erika-upscaler-state-');
    StorageService.debugAppStorageDirectoryOverride = dir;
    addTearDown(() async {
      StorageService.debugAppStorageDirectoryOverride = null;
      await dir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues(
        {'player_kernel_type': PlayerKernelType.videoPlayer.index});
    await PlayerFactory.initialize();
    // Initialization releases the wakelock after the last preference and
    // storage read. Let all of them finish before replacing the player.
    const wakelock =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    final initialized = Completer<void>();
    messenger.setMockMessageHandler(wakelock, (message) async {
      if (!initialized.isCompleted) initialized.complete();
      return const StandardMessageCodec().encodeMessage(<Object?>[]);
    });
    addTearDown(() => messenger.setMockMessageHandler(wakelock, null));
    final state = VideoPlayerState();
    await initialized.future;
    final facade = Player.withDelegate(ErikaPlayerAdapter());
    state.player = facade;
    addTearDown(() async {
      state.dispose();
      await facade.disposeAsync();
    });
    return state;
  }

  test(
      'state notifies both owners and reloads native danmaku after Flutter yields',
      () async {
    final state = await createStateWithErika();
    state.danmakuList.add({'time': 1, 'content': 'handoff'});
    final owners = <bool>[];
    state.addListener(() => owners.add(state.isNativeDanmakuActive));
    await state.setErikaUpscalerMode(PlayerUpscalerMode.erikaArtCnnC4F16);
    expect(owners.last, isFalse);
    expect(state.danmakuList.single['content'], 'handoff');
    await state.setErikaUpscalerMode(PlayerUpscalerMode.off);
    expect(owners.last, isTrue);
    await Future<void>.delayed(Duration.zero);
    final visibility = calls
        .where((c) => c.method == 'setDanmakuEnabled')
        .map((c) => (c.arguments as Map)['enabled']);
    expect(visibility, [false]);
    expect(
        (calls.lastWhere((c) => c.method == 'loadDanmakuJson').arguments
            as Map)['json'],
        contains('handoff'));
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleBeginFrame(null);
    binding.handleDrawFrame();
    await Future<void>.delayed(Duration.zero);
    expect(visibility, [false, true]);
  });

  test('switching Off supersedes a pending custom model load', () async {
    final state = await createStateWithErika();
    final dir = StorageService.debugAppStorageDirectoryOverride!;
    final file = File('${dir.path}/sample.esr');
    await file.writeAsBytes([1, 2, 3]);
    await state.setErikaUpscalerModelPath(file.path);
    loadingModel = Completer<void>();
    finishModel = Completer<void>();
    final custom = state.setErikaUpscalerMode(PlayerUpscalerMode.erikaCustom);
    await loadingModel!.future;
    try {
      await state.setErikaUpscalerMode(PlayerUpscalerMode.off);
    } finally {
      finishModel!.complete();
      await custom;
    }
    expect(state.erikaUpscalerMode, PlayerUpscalerMode.off);
    expect((await state.player.getUpscalerStatus())!.requestedMode,
        PlayerUpscalerMode.off);
    expect(state.isNativeDanmakuActive, isTrue);
  });

  test('overlapping model imports reach the native player in request order',
      () async {
    final facade = Player.withDelegate(ErikaPlayerAdapter());
    addTearDown(facade.disposeAsync);
    loadingModel = Completer<void>();
    finishModel = Completer<void>();
    await IOOverrides.runZoned(() async {
      final first = facade.loadUpscalerModelFile('first.esr');
      await loadingModel!.future;
      final second = facade.loadUpscalerModelFile('second.esr');
      await Future<void>.delayed(Duration.zero);
      final imports = calls
          .where((c) => c.method == 'loadUpscalerModel')
          .map((c) => (c.arguments as Map)['name']);
      try {
        expect(imports, ['first.esr']);
      } finally {
        finishModel!.complete();
        await Future.wait([first, second]);
      }
      expect(imports, ['first.esr', 'second.esr']);
    }, createFile: (_) => _ModelFile());
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
