import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'local_danmaku_bytes.dart';
export 'local_danmaku_bytes.dart';

List<XTypeGroup> get localDanmakuFileTypes => [
      const XTypeGroup(
        label: '弹幕文件 (XML / JSON)',
        extensions: ['xml', 'json'],
        mimeTypes: [
          'application/xml',
          'text/xml',
          'application/json',
          'text/plain'
        ],
        uniformTypeIdentifiers: ['public.xml', 'public.json', 'public.text'],
      ),
      // 部分 Android 文档提供器将 XML/JSON 标为 octet-stream 或未知类型。
      // 保留所有文件入口，选择后根据内容验证，而不是依赖提供器的 MIME。
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        const XTypeGroup(label: '所有文件'),
    ];

Future<Map<String, dynamic>> readLocalDanmakuFile(XFile file) async {
  final bytes = await file.readAsBytes();
  return {
    ...await compute(parseLocalDanmakuBytes, bytes),
    'filePath': file.path
  };
}
