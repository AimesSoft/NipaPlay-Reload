import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RemoteControlSettings', () {
    test('receiver is enabled by default', () async {
      expect(await RemoteControlSettings.isReceiverEnabled(), isTrue);
    });

    test('receiver enabled state can be persisted', () async {
      await RemoteControlSettings.setReceiverEnabled(false);
      expect(await RemoteControlSettings.isReceiverEnabled(), isFalse);

      await RemoteControlSettings.setReceiverEnabled(true);
      expect(await RemoteControlSettings.isReceiverEnabled(), isTrue);
    });
  });
}
