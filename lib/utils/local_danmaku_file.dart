import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/danmaku_xml_utils.dart';
import 'package:nipaplay/utils/legacy_charset_decoder.dart';
import 'package:xml/xml.dart';
import 'package:nipaplay/utils/dandanplay_comments.dart';

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

/// 手动导入与同名自动加载共用的解析入口，不依赖文件扩展名或本地路径。
/// [allowEmpty] 允许显式空数组或不含 d 元素的 i 根节点作为空池。
Map<String, dynamic> parseLocalDanmakuBytes(Uint8List bytes,
    {bool allowEmpty = false}) {
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
  var explicitEmptyPool = false;
  String platform = 'unknown';
  String? platformVideoId;
  if (content.startsWith('<')) {
    final document = XmlDocument.parse(content);
    explicitEmptyPool = document.rootElement.name.local == 'i' &&
        document.findAllElements('d').isEmpty;
    final server = document
        .findAllElements('chatserver')
        .firstOrNull
        ?.innerText
        .trim()
        .toLowerCase();
    platform = switch (server) {
      'comment.bilibili.com' || 'bilibili' || 'api.bilibili.com' => 'bilibili',
      'youku' || 'acs.youku.com' => 'youku',
      'dandanplay' || 'api.dandanplay.net' => 'dandanplay',
      _ => 'unknown'
    };
    final chatid =
        document.findAllElements('chatid').firstOrNull?.innerText.trim();
    platformVideoId = chatid == null || chatid.isEmpty ? null : chatid;
    comments = parseBilibiliXmlDanmakuComments(content);
    comments = [
      for (final row in comments as List)
        {
          ...row as Map,
          'source': platform,
          'platformVideoId': platformVideoId,
          'platformDanmakuId': row['cid']?.toString()
        }
    ];
  } else {
    final decoded = jsonDecode(content);
    if (decoded is List) {
      comments = decoded;
    } else if (decoded is Map) {
      platform = decoded['platform'] as String? ?? 'unknown';
      platformVideoId = decoded['platformVideoId'] as String?;
      comments = decoded['comments'] ?? decoded['data'];
      if (comments is String) comments = jsonDecode(comments);
    }
    explicitEmptyPool = comments is List && comments.isEmpty;
  }
  if (comments is! List) {
    throw const FormatException('弹幕文件必须包含 comments/data 数组或 XML 弹幕');
  }
  if (comments.isEmpty && !(allowEmpty && explicitEmptyPool)) {
    throw const FormatException('弹幕文件中没有弹幕数据');
  }
  comments = [
    for (final row in comments)
      if (row is Map && row.containsKey('p') && row.containsKey('m'))
        parseDandanplayComment(Map<String, dynamic>.from(row))
      else
        row
  ];
  return {
    'comments': comments,
    'count': comments.length,
    'platform': platform,
    'platformVideoId': platformVideoId
  };
}
