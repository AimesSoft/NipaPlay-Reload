import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/constants/settings_keys.dart';
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

  test('external playback window resize defaults off and persists', () async {
    SharedPreferences.setMockInitialValues(const {});
    final provider = SettingsProvider();
    await _waitForInitialLoad(provider);

    expect(provider.externalPlayerShrinkWindow, isFalse);

    await provider.setExternalPlayerShrinkWindow(true);
    final prefs = await SharedPreferences.getInstance();
    expect(provider.externalPlayerShrinkWindow, isTrue);
    expect(prefs.getBool(SettingsKeys.externalPlayerShrinkWindow), isTrue);
  });

  test('external player type loads and persists', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.externalPlayerType: ExternalPlayerType.vlc.name,
    });
    final provider = SettingsProvider();
    await _waitForInitialLoad(provider);

    expect(provider.externalPlayerType, ExternalPlayerType.vlc);

    await provider.setExternalPlayerType(ExternalPlayerType.mpvNet);
    final prefs = await SharedPreferences.getInstance();
    expect(provider.externalPlayerType, ExternalPlayerType.mpvNet);
    expect(
      prefs.getString(SettingsKeys.externalPlayerType),
      ExternalPlayerType.mpvNet.name,
    );
  });
}
