import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default restore initializes the kernel and later write failures surface',
    () async {
      const channel = MethodChannel('plugins.flutter.io/shared_preferences');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var failWrites = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getAll') {
          return <String, Object>{
            'flutter.player_kernel_type': PlayerKernelType.mediaKit.index,
            'flutter.${SettingsKeys.customPlayerUA}': 'CustomClient/1.0',
          };
        }
        if (call.method == 'setString' && failWrites) {
          throw PlatformException(
            code: 'write-failed',
            message: 'simulated persistence failure',
          );
        }
        return true;
      });
      SharedPreferences.resetStatic();
      final kernelChanged = Completer<PlayerKernelType>();
      final subscription = PlayerFactory.onKernelChanged.listen((event) {
        if (!kernelChanged.isCompleted) kernelChanged.complete(event);
      });
      addTearDown(() async {
        await subscription.cancel();
        messenger.setMockMethodCallHandler(channel, null);
        SharedPreferences.resetStatic();
      });

      await PlayerFactory.saveCustomPlayerUA('');

      expect(
        await kernelChanged.future.timeout(const Duration(milliseconds: 250)),
        PlayerKernelType.mediaKit,
      );

      failWrites = true;
      await expectLater(
        PlayerFactory.saveCustomPlayerUA('UnsavedClient/2.0'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'write-failed',
          ),
        ),
      );
    },
  );

  test('default User-Agent does not write an empty native option override', () {
    final mdkApplied = <(String, String)>[];
    applyMdkUserAgentProperties(
      (key, value) => mdkApplied.add((key, value)),
      '',
    );
    expect(mdkApplied, isEmpty);

    final mediaKitApplied = <(String, String)>[];
    applyMediaKitUserAgentProperty(
      (key, value) => mediaKitApplied.add((key, value)),
      '',
    );
    expect(mediaKitApplied, isEmpty);
  });

  test(
    'restoring the default User-Agent requests the active native kernel',
    () async {
      addTearDown(() async {
        await PlayerFactory.saveCustomPlayerUA('');
        SharedPreferences.setMockInitialValues({});
      });

      for (final kernel in <PlayerKernelType>[
        PlayerKernelType.mdk,
        PlayerKernelType.mediaKit,
      ]) {
        SharedPreferences.setMockInitialValues({
          'player_kernel_type': kernel.index,
        });
        await PlayerFactory.initialize();
        await PlayerFactory.saveCustomPlayerUA('CustomClient/1.0');

        final kernelChanged = Completer<PlayerKernelType>();
        final subscription = PlayerFactory.onKernelChanged.listen((event) {
          if (!kernelChanged.isCompleted) kernelChanged.complete(event);
        });
        try {
          await PlayerFactory.saveCustomPlayerUA('');
          expect(
            await kernelChanged.future.timeout(
              const Duration(milliseconds: 250),
            ),
            kernel,
          );
        } finally {
          await subscription.cancel();
        }
      }
    },
  );

  test('stream setup does not issue an unconfigured HTTP preflight', () {
    final source = File(
      'lib/utils/video_player_state/video_player_state_player_setup.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('http.head(')));
    expect(
      source,
      contains('PlayerFactory.applyUserAgentForNextOpen(player.setUserAgent);'),
    );
  });
}
