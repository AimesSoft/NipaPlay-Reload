
// test/database/hash_epi_id_get_file_danmaku_test.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';

void main() {

  test('File Hash & Dandanplay Episode ID -> File Danmaku', () async {

    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    final fileHash = getStringFromEnv(TestEnvironmentVariables.fileHash);
    final dandanplayEpisodeId = getIntFromEnv(TestEnvironmentVariables.dandanplayEpisodeId);
    if (databasePath == null ||
        fileHash == null ||
        dandanplayEpisodeId == null) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(databasePath);

    final result = await DatabaseService.getDandanplayFileDanmakuByFileHashAndEpisodeId(fileHash, dandanplayEpisodeId);
    printMsg(
      '${color('File Danmaku Result', ColorCode.boldCyan)}: '
      'File Exists=${result.fileRecordExists}, '
      'Episode Exists=${result.episodeRecordExists}, '
      'Danmaku Exists=${result.fileDanmaku != null}',
    );


    // 打印文件弹幕信息
    final fileDanmaku = result.fileDanmaku;
    if (fileDanmaku == null) return;
    printMsg(
      '${color('File Danmaku', ColorCode.boldCyan)}: '
      'Dandanplay Offset=${fileDanmaku.danmakuOffsetDandanplay}, '
      'User Offset=${fileDanmaku.danmakuOffsetUser}, '
      'Updated=${fileDanmaku.lastUpdated.toIso8601String()}',
    );
    final response = jsonDecode(fileDanmaku.danmakuJson);
    final comments = response is Map && response['comments'] is List
        ? (response['comments'] as List).take(10).toList()
        : const <dynamic>[];
    printMsg(
      '${color('Dandanplay Danmaku JSON (前 10 条)', ColorCode.boldCyan)}: '
      '${const JsonEncoder.withIndent('  ').convert(comments)}',
    );
  });
}