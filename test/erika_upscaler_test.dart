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

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    requested = 0;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return 31;
      if (call.method == 'setUpscaler')
        requested = (call.arguments as Map)['mode'] as int;
      if (call.method == 'getUpscalerStatus') {
        return {'requestedMode': requested, 'activeBackend': 9};
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

  test('iOS hides desktop-only ArtCNN R8F64 and keeps neural modes visible',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final modes = ErikaPlayerAdapter.availableUpscalerModes;
    expect(modes.first, PlayerUpscalerMode.off);
    expect(modes, contains(PlayerUpscalerMode.erikaArtCnnC4F16));
    expect(modes, contains(PlayerUpscalerMode.erikaArtCnnC4F16Dn));
    expect(modes, contains(PlayerUpscalerMode.erikaAnime4kUl));
    expect(modes, contains(PlayerUpscalerMode.erikaAnime4kDenoiseVl));
    expect(modes, contains(PlayerUpscalerMode.erikaFsr1));
    expect(modes, contains(PlayerUpscalerMode.erikaCustom));
    expect(modes, isNot(contains(PlayerUpscalerMode.erikaArtCnnR8F64)),
        reason: 'R8F64 是桌面专属档位');
    // MetalFX 需 iOS 16+、VideoToolbox 超分需 iOS 17+。单元测试跑在宿主
    // OS 上（override 只改平台枚举），宿主版本解析不出 iOS 主版本时按
    // 0 处理、两档隐藏；真机高版本会随系统放开，故用条件断言。
    final iosMajor = int.tryParse(RegExp(r'Version (\d+)')
            .firstMatch(Platform.operatingSystemVersion)
            ?.group(1) ??
        '') ??
        0;
    if (iosMajor < 16) {
      expect(modes, isNot(contains(PlayerUpscalerMode.erikaMetalFxSpatial)),
          reason: 'MetalFX 需要 iOS 16+');
    }
    if (iosMajor < 17) {
      expect(modes, isNot(contains(PlayerUpscalerMode.erikaPlatformVideo)),
          reason: 'VideoToolbox 超分入口需要 iOS 17+');
    }
  });

  test('native setUpscaler failure leaves status unknown and danmaku native',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return 31;
      if (call.method == 'setUpscaler') {
        throw PlatformException(code: 'unsupported');
      }
      return null;
    });
    final player = ErikaPlayerAdapter();
    try {
      await player.setUpscaler(PlayerUpscalerMode.erikaArtCnnC4F16);
      expect(player.supportsNativeDanmaku, isTrue,
          reason: '超分未生效时弹幕留在 native，无需回退 Flutter 叠层');
      final status = await player.getUpscalerStatus();
      expect(status.requestedMode, PlayerUpscalerMode.erikaArtCnnC4F16);
      expect(status.activeBackend, PlayerUpscalerBackendStatus.unknown,
          reason: '失败态与成功未激活（inactive）区分');
    } finally {
      await player.disposeAsync();
      // 恢复 setUp 的默认 mock，避免影响后续测试（若有）。
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'create') return 31;
        if (call.method == 'setUpscaler') {
          requested = (call.arguments as Map)['mode'] as int;
        }
        if (call.method == 'getUpscalerStatus') {
          return {'requestedMode': requested, 'activeBackend': 9};
        }
        return null;
      });
    }
  });
}
