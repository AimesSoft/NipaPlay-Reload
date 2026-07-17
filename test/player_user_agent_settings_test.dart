import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saving a player User-Agent sanitizes and applies it immediately',
      () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.legacyPlayerCustomUserAgent:
          '  PersistedClient/1.0\r\nInjected  ',
    });
    addTearDown(() async {
      await PlayerFactory.saveCustomPlayerUA('');
      SharedPreferences.setMockInitialValues({});
    });
    await PlayerFactory.initialize();
    expect(PlayerFactory.getCustomPlayerUA(), 'PersistedClient/1.0Injected');
    var preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.customPlayerUA),
      'PersistedClient/1.0Injected',
    );
    final userAgentKernelChanged = PlayerFactory.onKernelChanged.first;

    await PlayerFactory.saveCustomPlayerUA(
      '  PlayerClient/5.0\r\nInjected  ',
    );

    expect(PlayerFactory.getCustomPlayerUA(), 'PlayerClient/5.0Injected');
    preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.customPlayerUA),
      'PlayerClient/5.0Injected',
    );
    expect(
      await userAgentKernelChanged.timeout(const Duration(seconds: 1)),
      PlayerKernelType.mdk,
    );

  });
}
