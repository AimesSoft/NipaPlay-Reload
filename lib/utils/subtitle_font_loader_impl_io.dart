import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

Future<Map<String, String>?> ensureSubtitleFontFromAssetImpl({
  required String assetPath,
  required String fileName,
}) async {
  try {
    final supportDir = await getApplicationSupportDirectory();
    final fontsDir = Directory('${supportDir.path}/subtitle_fonts');
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }

    final fontFile = File('${fontsDir.path}/$fileName');
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    if (!await fontFile.exists() || (await fontFile.length()) != bytes.length) {
      await fontFile.writeAsBytes(bytes, flush: true);
      debugPrint('SubtitleFontLoader: 写入字幕字体文件到 ${fontFile.path}');
    }

    return {
      'filePath': fontFile.path,
      'directory': fontsDir.path,
    };
  } catch (e) {
    debugPrint('SubtitleFontLoader: 准备字幕字体失败: $e');
    return null;
  }
}
