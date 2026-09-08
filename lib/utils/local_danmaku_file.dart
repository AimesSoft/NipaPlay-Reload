import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/danmaku_xml_utils.dart';
import 'package:nipaplay/utils/legacy_charset_decoder.dart';

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
  return compute(parseLocalDanmakuBytes, bytes);
}

/// 手动导入与同名自动加载共用的解析入口，不依赖文件扩展名或本地路径。
Map<String, dynamic> parseLocalDanmakuBytes(Uint8List bytes) {
  String content;
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if (bytes.length.isOdd) throw const FormatException('UTF-16 弹幕文件不完整');
    final littleEndian = bytes[0] == 0xff;
    content = String.fromCharCodes([
      for (var i = 2; i + 1 < bytes.length; i += 2)
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
    ]);
  } else {
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      final header = latin1.decode(bytes.take(200).toList());
      final declared = RegExp(
        r'''encoding\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(header)?.group(1);
      content = LegacyCharsetDecoder.decode(bytes, declared ?? 'gbk') ??
          (throw const FormatException('无法识别弹幕文件编码'));
    }
  }
  content = content.replaceFirst(RegExp(r'^\uFEFF'), '').trimLeft();
  dynamic comments;
  if (content.startsWith('<')) {
    comments = parseBilibiliXmlDanmakuComments(content);
  } else {
    final decoded = jsonDecode(content);
    if (decoded is List) {
      comments = decoded;
    } else if (decoded is Map) {
      comments = decoded['comments'] ?? decoded['data'];
      if (comments is String) comments = jsonDecode(comments);
    }
  }
  if (comments is! List) {
    throw const FormatException('弹幕文件必须包含 comments/data 数组或 XML 弹幕');
  }
  if (comments.isEmpty) throw const FormatException('弹幕文件中没有弹幕数据');
  return {'comments': comments, 'count': comments.length};
}
