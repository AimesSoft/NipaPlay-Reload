
// test/anime_info/get_dandanplay_danmaku_by_asset_hash_test.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/file_hash.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('File Hash -> Dandanplay Danmaku', () async {

    final dbPath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    final fileHash = getStringFromEnv(TestEnvironmentVariables.fileHash);
    if (dbPath == null || fileHash == null) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    final assetHash = decodeHex(fileHash, expectedBytes: 16);

    await DatabaseService.initialize(dbPath);
    final fileDanmakuJson = await AnimeInfoService.getDandanplayDanmakuByAssetHash(assetHash);
    if (fileDanmakuJson == null) {
      printMsg(
        '${color('File Danmaku', ColorCode.boldCyan)}: '
        'File Hash=$fileHash, '
        '未找到对应的 Dandanplay 弹幕数据',
      );
      return;
    }

    printMsg(
      '${color('File Danmaku', ColorCode.boldCyan)}: '
      'File Hash=$fileHash, '
    );

    // 美观打印前 10 条弹幕
    final comments = fileDanmakuJson['comments'] is List
        ? (fileDanmakuJson['comments'] as List).take(10).toList()
        : const <dynamic>[];
    printMsg(
      '${color('Dandanplay Episode Danmaku JSON (前 10 条)', ColorCode.boldCyan)}: '
      '${const JsonEncoder.withIndent('  ').convert(comments)}',
    );
  });
}
