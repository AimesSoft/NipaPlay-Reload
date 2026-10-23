import 'dart:async';

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

  test('an external subtitle asked for while the media opens waits for it',
      () async {
    final opened = Completer<void>();
    messenger.setMockMethodCallHandler(playerChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'create':
          return 7;
        case 'open':
          await opened.future;
          return null;
        case 'addExternalSubtitle':
          return 11;
        default:
          return null;
      }
    });
    final player = ErikaPlayerAdapter();
    try {
      player.setMedia('/tmp/video.mkv', PlayerMediaType.video);
      final preparing = player.prepare();
      final attached = player.setExternalSubtitleAsync('/tmp/sub.ass');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls.map((call) => call.method), contains('open'));
      expect(calls.map((call) => call.method),
          isNot(contains('addExternalSubtitle')),
          reason: 'the media has not finished opening');
      opened.complete();
      await preparing;
      await attached;
      final methods = calls.map((call) => call.method).toList();
      expect(methods.indexOf('addExternalSubtitle'),
          greaterThan(methods.indexOf('open')));
      final select =
          calls.lastWhere((call) => call.method == 'selectSubtitleTrack');
      expect((select.arguments as Map)['trackId'], 11);
    } finally {
      await player.disposeAsync();
    }
  });

  test('a subtitle waiting for a media that is replaced does not hang',
      () async {
    final player = ErikaPlayerAdapter();
    try {
      player.setMedia('/tmp/first.mkv', PlayerMediaType.video);
      final attached = player.setExternalSubtitleAsync('/tmp/sub.ass');
      player.setMedia('/tmp/second.mkv', PlayerMediaType.video);
      await attached.timeout(const Duration(seconds: 2));
      expect(calls.map((call) => call.method),
          isNot(contains('addExternalSubtitle')),
          reason: 'the request belonged to the media that was replaced');
    } finally {
      await player.disposeAsync();
    }
  });
}
