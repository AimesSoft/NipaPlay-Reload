import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/screen_orientation_manager.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('missing OHOS reset UI reply cannot block the next video',
      (tester) async {
    final missingReply = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) => missingReply.future,
    );
    final manager = ScreenOrientationManager.forTesting(isHarmonyOS: true);
    var nextVideoStarted = false;
    final reset = manager.setSystemUiMode(SystemUiMode.edgeToEdge);
    final nextOpen = reset.then((_) => nextVideoStarted = true);

    await tester.pump(const Duration(milliseconds: 299));
    expect(nextVideoStarted, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await nextOpen;
    expect(nextVideoStarted, isTrue);
    expect(missingReply.isCompleted, isFalse);
  });

  testWidgets('a lost OHOS reply does not strand subsequent UI changes',
      (tester) async {
    final missingReply = Completer<void>();
    final modes = <Object?>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) {
        modes.add(call.arguments);
        return modes.length == 1 ? missingReply.future : Future<void>.value();
      },
    );
    final manager = ScreenOrientationManager.forTesting(isHarmonyOS: true);
    final restore = manager.setSystemUiMode(SystemUiMode.edgeToEdge);
    await tester.pump(const Duration(milliseconds: 300));
    await restore;

    final enterPlayback = manager.setSystemUiMode(SystemUiMode.immersiveSticky);
    await tester.pump();
    await enterPlayback;
    expect(modes, ['SystemUiMode.edgeToEdge', 'SystemUiMode.immersiveSticky']);
    expect(missingReply.isCompleted, isFalse);
  });

  testWidgets('other platforms still wait for the actual platform reply',
      (tester) async {
    final reply = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) => reply.future,
    );
    final manager = ScreenOrientationManager.forTesting(isHarmonyOS: false);
    var completed = false;
    final operation = manager
        .setSystemUiMode(SystemUiMode.edgeToEdge)
        .then((_) => completed = true);
    await tester.pump(const Duration(seconds: 1));
    expect(completed, isFalse);
    reply.complete();
    await tester.pump();
    await operation;
    expect(completed, isTrue);
  });

  testWidgets('real platform failures remain visible', (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => throw PlatformException(code: 'UI_FAILED'),
    );
    final manager = ScreenOrientationManager.forTesting(isHarmonyOS: true);
    final expectation = expectLater(
      manager.setSystemUiMode(SystemUiMode.edgeToEdge),
      throwsA(isA<PlatformException>()),
    );
    await tester.pump();
    await expectation;
  });
}
