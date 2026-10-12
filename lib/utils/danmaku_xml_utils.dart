import 'dart:convert';
import 'danmaku_xml_parse.dart';
export 'danmaku_xml_parse.dart';
import 'package:flutter/foundation.dart';

import 'package:nipaplay/cpp_native/bindings/danmaku_parser.dart';

Map<String, dynamic> convertBilibiliXmlDanmakuToJson(String xmlContent) {
  // 优先使用 C++ 解析器（非 Web 平台）
  if (!kIsWeb) {
    try {
      final jsonStr = DanmakuParser.parseXml(xmlContent);
      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final count = decoded['count'];
        // 防御性检查: 如果 C++ 返回 0 条弹幕但 XML 明显包含 <d 标签，
        // 可能是 FFI content_len 传错、XML 被截断等异常情况，
        // 应 fallback 到 Dart 而非返回空列表导致弹幕消失。
        if (count == 0 && xmlContent.contains('<d')) {
          final comments = parseBilibiliXmlDanmakuComments(xmlContent);
          return {'count': comments.length, 'comments': comments};
        }
        debugPrint('[DanmakuParser] [C++] [OK] convertBilibiliXml: '
            '${decoded['count']} comments via C++ path');
        return decoded;
      }
    } catch (_) {
      debugPrint('[DanmakuParser] [C++] [ERR] convertBilibiliXml: '
          'C++ exception, falling back to Dart');
    }
  }
  // Fallback: 原 Dart 实现
  final comments = parseBilibiliXmlDanmakuComments(xmlContent);
  return {
    'count': comments.length,
    'comments': comments,
  };
}
