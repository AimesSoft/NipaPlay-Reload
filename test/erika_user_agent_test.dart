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
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls = [];
    messenger.setMockMethodCallHandler(playerChannel, (call) async {
      calls.add(call);
      return call.method == 'create' ? 7 : null;
    });
    messenger.setMockMethodCallHandler(eventsChannel, (_) async => null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(playerChannel, null);
    messenger.setMockMethodCallHandler(eventsChannel, null);
  });

  test('Erika forwards the selected UA and clears it for the next open',
      () async {
    final player = ErikaPlayerAdapter();
    try {
      player.setUserAgent('NipaPlay-Test/1.0');
      player.setMedia('https://example.test/video.mp4', PlayerMediaType.video);
      await player.prepare();
      final firstOpen = calls.lastWhere((call) => call.method == 'open');
      expect((firstOpen.arguments as Map)['httpHeaders'],
          {'User-Agent': 'NipaPlay-Test/1.0'});

      player.setUserAgent('');
      player.setMedia('https://example.test/next.mp4', PlayerMediaType.video);
      await player.prepare();
      final nextOpen = calls.lastWhere((call) => call.method == 'open');
      expect((nextOpen.arguments as Map).containsKey('httpHeaders'), isFalse);
    } finally {
      await player.disposeAsync();
    }
  });
}
