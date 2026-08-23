import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitForInitialLoad(ChangeNotifier provider) async {
  final completer = Completer<void>();
  void listener() {
    if (!completer.isCompleted) completer.complete();
  }

  provider.addListener(listener);
  await completer.future.timeout(const Duration(seconds: 2));
  provider.removeListener(listener);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy manual strategy migrates to the standalone skip switch',
      () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.danmakuAutoLoadStrategy: 'manual',
    });

    final provider = SettingsProvider();
    await _waitForInitialLoad(provider);

    expect(provider.skipDanmakuMatching, isTrue);
    expect(
      provider.danmakuAutoLoadStrategy,
      DanmakuAutoLoadStrategy.remoteAndLocal,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SettingsKeys.skipDanmakuMatching), isTrue);
    expect(
      prefs.getString(SettingsKeys.danmakuAutoLoadStrategy),
      'remoteAndLocal',
    );
  });

  test('skip switch preserves the selected auto-load strategy', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.danmakuAutoLoadStrategy: 'local',
      SettingsKeys.skipDanmakuMatching: false,
    });

    final provider = SettingsProvider();
    await _waitForInitialLoad(provider);

    await provider.setSkipDanmakuMatching(true);
    await provider.setSkipDanmakuMatching(false);

    expect(provider.skipDanmakuMatching, isFalse);
    expect(
      provider.danmakuAutoLoadStrategy,
      DanmakuAutoLoadStrategy.local,
    );
  });
}
