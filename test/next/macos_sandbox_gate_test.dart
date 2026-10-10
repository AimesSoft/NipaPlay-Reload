import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sandbox blocks persisted Next enablement and rejects enabling it',
      () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.labsEnableAgentEndpoint: true,
    });
    final labs = LabsSettingsProvider(sandboxStatus: () async => true);
    await labs.ready;
    expect(labs.nextAvailable, isFalse);
    expect(labs.enableAgentEndpoint, isFalse);
    await expectLater(labs.setEnableAgentEndpoint(true), throwsStateError);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(SettingsKeys.labsEnableAgentEndpoint), isTrue);
    labs.dispose();
  });

  test('non-sandbox process restores and persists the Next switch', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.labsEnableAgentEndpoint: true,
    });
    final labs = LabsSettingsProvider(sandboxStatus: () async => false);
    await labs.ready;
    expect(labs.nextAvailable, isTrue);
    expect(labs.enableAgentEndpoint, isTrue);
    await labs.setEnableAgentEndpoint(false);
    expect(labs.enableAgentEndpoint, isFalse);
    expect(
        (await SharedPreferences.getInstance())
            .getBool(SettingsKeys.labsEnableAgentEndpoint),
        isFalse);
    labs.dispose();
  });
}
