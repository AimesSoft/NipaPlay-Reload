import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/system_share_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nipaplay/system_share');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('iOS file export opens the native document picker', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    MethodCall? captured;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      captured = call;
      return true;
    });

    final opened = await SystemShareService.exportFile(
      '/tmp/screenshot.jpg',
      mimeType: 'image/jpeg',
    );

    expect(opened, isTrue);
    expect(captured?.method, 'exportFile');
    expect(captured?.arguments, {
      'filePath': '/tmp/screenshot.jpg',
      'mimeType': 'image/jpeg',
    });
  });

  test('Android document cancellation is reported without a save', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => false,
    );

    expect(
      await SystemShareService.exportFile(
        '/tmp/screenshot.jpg',
        mimeType: 'image/jpeg',
      ),
      isFalse,
    );
  });

  test('iOS GIF is passed to the native share sheet as a file', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    MethodCall? captured;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      captured = call;
      return true;
    });

    await SystemShareService.share(
      filePath: '/tmp/capture.gif',
      mimeType: 'image/gif',
    );

    expect(captured?.method, 'share');
    expect((captured?.arguments as Map)['filePath'], '/tmp/capture.gif');
    expect((captured?.arguments as Map)['mimeType'], 'image/gif');
  });
}
