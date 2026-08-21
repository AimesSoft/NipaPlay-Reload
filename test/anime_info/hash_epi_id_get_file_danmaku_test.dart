
// test/database/hash_epi_id_get_file_danmaku_test.dart

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

  test('Asset Hash -> Dandanplay Danmaku', () async {

    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    final fileHash = getStringFromEnv(TestEnvironmentVariables.fileHash);
    if (databasePath == null || fileHash == null) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(databasePath);
    final assetHash = decodeHex(fileHash, expectedBytes: 16);
    final dandanplayEpisodeId = await DatabaseService.getDandanplayEpisodeIdByAssetHash(assetHash);
    expect(dandanplayEpisodeId, isNotNull);
    await AnimeInfoService.refreshDandanplayDanmakuCacheByEpisodeId(
      dandanplayEpisodeId!,
    );

    final result = await AnimeInfoService.getDandanplayDanmakuByAssetHash(assetHash);
    expect(result, isNotNull);
    printMsg(
      '${color('File Danmaku Result', ColorCode.boldCyan)}: '
      'Dandanplay Offset=${result!.dandanplayOffset}, '
      'User Offset=${result.userOffset}',
    );

    final response = jsonDecode(result.danmakuJson);
    final comments = response is Map && response['comments'] is List
        ? (response['comments'] as List).take(10).toList()
        : const <dynamic>[];
    printMsg(
      '${color('Dandanplay Danmaku JSON (前 10 条)', ColorCode.boldCyan)}: '
      '${const JsonEncoder.withIndent('  ').convert(comments)}',
    );
  });
}