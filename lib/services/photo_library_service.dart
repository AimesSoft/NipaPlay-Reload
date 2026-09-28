import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PhotoLibraryService {
  static const MethodChannel _channel = MethodChannel('nipaplay/photo_library');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> saveImageToPhotos(Uint8List pngBytes) async {
    if (!isSupported) {
      throw UnsupportedError(
        'Photo library save is not supported on this platform',
      );
    }

    await _channel.invokeMethod<void>('saveImage', <String, dynamic>{
      'bytes': pngBytes,
    });
  }

  /// Copies a temporary JPEG or GIF into Android's shared photo library.
  static Future<void> saveFileToPhotos(
    String filePath, {
    required String mimeType,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Gallery file save is only supported on Android');
    }
    await _channel.invokeMethod<void>('saveFile', <String, dynamic>{
      'filePath': filePath,
      'mimeType': mimeType,
    });
  }

  static Future<void> saveTemporaryFileToPhotos(
    String filePath, {
    required String mimeType,
  }) async {
    try {
      await saveFileToPhotos(filePath, mimeType: mimeType);
    } finally {
      try {
        await File(filePath).delete();
      } catch (_) {
        // Temporary files can already have been cleared by the OS.
      }
    }
  }
}
