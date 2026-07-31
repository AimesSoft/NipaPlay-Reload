import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volume_controller/volume_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'com.kurenai7968.volume_controller.method',
  );

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getVolume accepts an integral platform value', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getVolume');
      return 0;
    });

    expect(await VolumeController.instance.getVolume(), 0.0);
  });
}
