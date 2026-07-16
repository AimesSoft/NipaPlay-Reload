import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/cpp_native/bindings/danmaku_parser.dart';

String encodeDanmakuXmlText(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String decodeDanmakuXmlText(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

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

List<Map<String, dynamic>> parseBilibiliXmlDanmakuComments(String xmlContent) {
  try {
    final document = XmlDocument.parse(xmlContent);
    final comments = <Map<String, dynamic>>[];

    for (final element in document.findAllElements('d')) {
      final parsedComment = _buildBilibiliDanmakuComment(
        pAttr: element.getAttribute('p') ?? '',
        rawTextContent: element.innerText,
      );
      if (parsedComment != null) {
        comments.add(parsedComment);
      }
    }

    if (comments.isNotEmpty || !xmlContent.contains('<d')) {
      return comments;
    }
  } on XmlParserException {
    // Fall back to a more tolerant parser for slightly malformed exports.
  }

  final comments = <Map<String, dynamic>>[];
  final danmakuRegex = RegExp(
    r'<d\b[^>]*\bp="([^"]+)"[^>]*>([\s\S]*?)</d>',
    caseSensitive: false,
  );

  for (final match in danmakuRegex.allMatches(xmlContent)) {
    final parsedComment = _buildBilibiliDanmakuComment(
      pAttr: match.group(1) ?? '',
      rawTextContent: match.group(2) ?? '',
    );
    if (parsedComment != null) {
      comments.add(parsedComment);
    }
  }

  return comments;
}

Map<String, dynamic>? _buildBilibiliDanmakuComment({
  required String pAttr,
  required String rawTextContent,
}) {
  try {
    final textContent = decodeDanmakuXmlText(rawTextContent);
    if (textContent.isEmpty) return null;

    final pParams = pAttr.split(',');
    if (pParams.length < 4) return null;

    final time = double.tryParse(pParams[0]) ?? 0.0;
    final typeCode = int.tryParse(pParams[1]) ?? 1;
    final fontSize = int.tryParse(pParams[2]) ?? 25;
    final colorCode = int.tryParse(pParams[3]) ?? 16777215;

    final danmakuType = DanmakuMode.fromCode(typeCode).typeName;

    final r = (colorCode >> 16) & 0xFF;
    final g = (colorCode >> 8) & 0xFF;
    final b = colorCode & 0xFF;
    final color = 'rgb($r,$g,$b)';

    // 可选字段: timestamp, senderId, cid
    final timestamp = pParams.length > 4 ? int.tryParse(pParams[4]) : null;
    final senderId = pParams.length > 6 ? pParams[6].trim() : '';
    final danmakuId = pParams.length > 7 ? pParams[7].trim() : '';

    return {
      't': time,
      'c': textContent,
      'y': danmakuType,
      'r': color,
      'fontSize': fontSize,
      'originalType': typeCode,

      if (timestamp != null && timestamp > 0) 'timestamp': timestamp,
      if (senderId.isNotEmpty && senderId != '0') 'senderId': senderId,
      if (danmakuId.isNotEmpty && danmakuId != '0') 'cid': danmakuId,
      'source': 'bilibili', // 标记来源, 便于后续处理
    };
  } catch (_) {
    return null;
  }
}

int parseDanmakuColorToInt(dynamic colorValue) {
  if (colorValue == null) return 0xFFFFFF;

  if (colorValue is int) return colorValue & 0xFFFFFF;
  if (colorValue is num) return colorValue.toInt() & 0xFFFFFF;

  final text = colorValue.toString().trim();
  if (text.isEmpty) return 0xFFFFFF;

  final rgbMatch = RegExp(
    r'rgb\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)',
    caseSensitive: false,
  ).firstMatch(text);
  if (rgbMatch != null) {
    final r = int.tryParse(rgbMatch.group(1) ?? '') ?? 255;
    final g = int.tryParse(rgbMatch.group(2) ?? '') ?? 255;
    final b = int.tryParse(rgbMatch.group(3) ?? '') ?? 255;
    return (_clampColorComponent(r) << 16) |
        (_clampColorComponent(g) << 8) |
        _clampColorComponent(b);
  }

  if (text.startsWith('#')) {
    var hex = text.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    } else if (hex.length == 8) {
      hex = hex.substring(2);
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) return parsed & 0xFFFFFF;
  }

  if (text.startsWith('0x') || text.startsWith('0X')) {
    final parsed = int.tryParse(text.substring(2), radix: 16);
    if (parsed != null) return parsed & 0xFFFFFF;
  }

  final parsed = int.tryParse(text);
  if (parsed != null) return parsed & 0xFFFFFF;

  return 0xFFFFFF;
}

int _clampColorComponent(int value) {
  return value.clamp(0, 255).toInt();
}
