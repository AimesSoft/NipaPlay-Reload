import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 把本地图片文件本体写入系统剪贴板（桌面端）。
///
/// Flutter 自带的 `Clipboard` 只能写文本，写入文件路径文本无法在聊天软件
/// 输入框中粘贴成图片/文件。此服务通过平台通道调用原生剪贴板：
/// - macOS：写入 fileURL，并附带 GIF 原始数据与位图数据；
/// - Windows：写入 CF_HDROP 文件列表（等价于资源管理器复制文件）；
/// - Linux：写入 text/uri-list。
///
/// 移动端不做要求，调用方在 [isSupported] 为 false 时回退为复制路径文本。
class ClipboardImageService {
  ClipboardImageService._();

  static const MethodChannel _channel =
      MethodChannel('nipaplay/clipboard_image');

  /// 仅桌面端支持写入文件本体。
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// 将 [filePath] 指向的图片文件写入系统剪贴板。
  ///
  /// 返回 true 表示已按文件本体写入；false 表示平台不支持、文件不存在或
  /// 原生写入失败，调用方应回退为复制路径文本。
  static Future<bool> copyImageFile(String filePath, {String? mimeType}) async {
    if (!isSupported) return false;
    if (filePath.trim().isEmpty) return false;
    try {
      final copied =
          await _channel.invokeMethod<bool>('copyImageFile', <String, dynamic>{
        'path': filePath,
        'mimeType': mimeType ?? 'image/gif',
      });
      return copied ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
