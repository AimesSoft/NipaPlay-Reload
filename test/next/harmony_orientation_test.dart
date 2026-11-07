import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/player/touch_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = PhoneOrientation.harmonyOS;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    PhoneOrientation.harmonyOS = () => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    PhoneOrientation.harmonyOS = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  List<Object?> orientations() => [
    for (final call in calls)
      if (call.method == 'SystemChrome.setPreferredOrientations') call.arguments,
  ];
  const sideways = ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'];

  test('HarmonyOS playback enters landscape on every open and exits upright', () async {
    await PhoneOrientation.video();
    await PhoneOrientation.pages();
    await PhoneOrientation.video();
    expect(orientations(), [sideways, ['DeviceOrientation.portraitUp'], sideways]);
    expect(calls.last.method, 'SystemChrome.setEnabledSystemUIMode');
    expect(calls.last.arguments, 'SystemUiMode.immersiveSticky');
  });

  test('a slow exit cannot restore portrait after the next landscape request', () async {
    final exiting = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      if (calls.length == 1) await exiting.future;
      return null;
    });
    final pages = PhoneOrientation.pages();
    final video = PhoneOrientation.video();
    await Future<void>.delayed(Duration.zero);
    expect(orientations(), [['DeviceOrientation.portraitUp']]);
    exiting.complete();
    await Future.wait([pages, video]);
    expect(orientations(), [['DeviceOrientation.portraitUp'], sideways]);
  });

  test('other phones retain their existing automatic video rotation', () async {
    PhoneOrientation.harmonyOS = () => false;
    await PhoneOrientation.video();
    expect(orientations(), [[
      'DeviceOrientation.portraitUp',
      ...sideways,
    ]]);
    expect(calls.last.arguments, 'SystemUiMode.edgeToEdge');
  });

  test('a missing HarmonyOS system-bar reply cannot block the next player', () async {
    final missingReply = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      if (call.method == 'SystemChrome.setEnabledSystemUIMode' &&
          call.arguments == 'SystemUiMode.edgeToEdge') {
        return missingReply.future;
      }
      return null;
    });
    await PhoneOrientation.pages().timeout(const Duration(seconds: 2));
    await PhoneOrientation.video().timeout(const Duration(seconds: 2));
    expect(orientations(), [['DeviceOrientation.portraitUp'], sideways]);
    expect(calls.last.arguments, 'SystemUiMode.immersiveSticky');
    missingReply.complete(null);
  });
}
