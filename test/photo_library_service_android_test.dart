import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/photo_library_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nipaplay/photo_library');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final (extension, mimeType) in [
    ('jpg', 'image/jpeg'),
    ('gif', 'image/gif'),
  ]) {
    test('Android saves $extension to the gallery and clears staging',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final directory =
          await Directory.systemTemp.createTemp('nipaplay-gallery-test-');
      final file = File('${directory.path}/capture.$extension');
      await file.writeAsBytes([1, 2, 3]);
      MethodCall? captured;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        captured = call;
        expect(await file.exists(), isTrue);
        return null;
      });

      try {
        await PhotoLibraryService.saveTemporaryFileToPhotos(
          file.path,
          mimeType: mimeType,
        );
        expect(captured?.method, 'saveFile');
        expect(captured?.arguments, {
          'filePath': file.path,
          'mimeType': mimeType,
        });
        expect(await file.exists(), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  }

  test('failed Android gallery save still clears staging', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final directory =
        await Directory.systemTemp.createTemp('nipaplay-gallery-test-');
    final file = File('${directory.path}/capture.gif');
    await file.writeAsBytes([1, 2, 3]);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'SAVE_FAILED'),
    );
    try {
      await expectLater(
        PhotoLibraryService.saveTemporaryFileToPhotos(
          file.path,
          mimeType: 'image/gif',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(await file.exists(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
