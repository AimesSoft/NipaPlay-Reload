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

  /// 通过 iOS 系统文件选择器导出一个已经生成的本地文件。
  static Future<void> exportFile(String filePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError('System file export is only supported on iOS');
    }
    await _channel.invokeMethod<void>('exportFile', <String, dynamic>{
      'filePath': filePath,
    });
  }
}
