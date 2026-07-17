import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical player User-Agent wins over the legacy setting', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.customPlayerUA: '  CanonicalClient/2.0\r\nInjected  ',
      SettingsKeys.legacyPlayerCustomUserAgent: 'LegacyClient/1.0',
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await PlayerFactory.initialize();

    expect(PlayerFactory.getCustomPlayerUA(), 'CanonicalClient/2.0Injected');
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.customPlayerUA),
      '  CanonicalClient/2.0\r\nInjected  ',
    );
  });
}
