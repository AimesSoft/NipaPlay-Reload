
// test/anime_info/get_dandanplay_danmaku_by_asset_hash_test.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info_service.dart';
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
    final fileDanmaku = await AnimeInfoService.getDandanplayDanmakuByAssetHash(assetHash);

    expect(fileDanmaku, isNotNull);
    printMsg(
      '${color('File Danmaku', ColorCode.boldCyan)}: '
      'File Hash=$fileHash, '
      'Dandanplay Danmaku Offset=${fileDanmaku!.dandanplayOffset}, '
      'User Danmaku Offset=${fileDanmaku.userOffset}',
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
