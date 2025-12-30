import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemShareService {
  static const MethodChannel _channel = MethodChannel('nipaplay/system_share');

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<void> share({
    String? text,
    String? url,
    String? filePath,
    String? mimeType,
    String? subject,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('System share is not supported on this platform');
    }

    await _channel.invokeMethod<void>('share', <String, dynamic>{
      'text': text,
      'url': url,
      'filePath': filePath,
      'mimeType': mimeType,
      'subject': subject,
    });
  }
}
