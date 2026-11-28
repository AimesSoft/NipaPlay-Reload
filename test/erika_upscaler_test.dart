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
}
