
// test/database/hash_get_ddp_epi_test.dart
// 数据库相关测试

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'dart:convert';


import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {

  test('File Hash -> Dandanplay Episode Record & File Danmaku', () async {

    final dbPath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    final fileHash = getStringFromEnv(TestEnvironmentVariables.fileHash);
    if (dbPath == null || fileHash == null) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(dbPath);

    final fileDanmaku = await DatabaseService.getDandanplayFileDanmakuByFileHash(fileHash);
    if (fileDanmaku == null) {
      debugPrint(color('未找到匹配的 File Danmaku', ColorCode.red));
      return;
    }
    printMsg(
      '${color('File Danmaku', ColorCode.boldCyan)}: '
      'File Hash=$fileHash, '
      'Dandanplay Danmaku Offset=${fileDanmaku.danmakuOffsetDandanplay}, '
      'User Danmaku Offset=${fileDanmaku.danmakuOffsetUser}'
    );

    // 美观打印前 10 条弹幕
    final response = jsonDecode(fileDanmaku.danmakuJson);
    final comments = response is Map && response['comments'] is List
        ? (response['comments'] as List).take(10).toList()
        : const <dynamic>[];
    printMsg(
      '${color('Dandanplay Episode Danmaku JSON (前 10 条)', ColorCode.boldCyan)}: '
      '${const JsonEncoder.withIndent('  ').convert(comments)}',
    );
  });
}
