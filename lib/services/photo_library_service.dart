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
}
