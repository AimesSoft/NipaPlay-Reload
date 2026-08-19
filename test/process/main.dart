
// test/process/hash_to_ddp_info_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/models/database/file_record.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/file_hash.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {

  // 初始化 Flutter 测试环境
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{SettingsKeys.autoMatchDanmakuFirstSearchResultOnHashFail: false});

  final testLabel = color('[File Hash -> Dandanplay Anime & Episode ID]', ColorCode.boldBlue);

  test(testLabel, () async {

    // 输入
    final filePath     = getStringFromEnv(TestEnvironmentVariables.filePath);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (filePath == null || databasePath == null) {
      debugPrint('$testLabel ${color('测试未运行', ColorCode.red)}');
      return;
    }

    // 文件 Hash
    final file = File(filePath);
    expect(file.existsSync(), isTrue, reason: '测试文件不存在: $filePath');
    final fileHash = await computeFileHeadMd5(file.path);
    final fileSize = await file.length();
    final fileName = file.uri.pathSegments.last;
    printMsg(color('$testLabel: 文件前16MiB MD5哈希: ${color(fileHash, ColorCode.gray)}', ColorCode.boldCyan));
    final matchArg = DandanplayFileMatchArgument(
      fileHash: fileHash,
      fileSize: fileSize,
      fileName: fileName,
    );

    // 获取匹配信息
    final matchResult = await AnimeInfoService.getDandanplayFileMatch(matchArg);
    if (matchResult == null) {
      printMsg(color('$testLabel: 未找到匹配的 Dandanplay 文件', ColorCode.red));
      return;
    }
    printMsg(
      '${color('Dandanplay File Match Result', ColorCode.boldCyan)}: '
      'Anime ID=${matchResult.dandanplayAnimeId}, '
      'Episode ID=${matchResult.dandanplayEpisodeId}, '
      'Danmaku Offset=${matchResult.danmakuOffset}',
    );

    await DatabaseService.initialize(databasePath);

    // 插入文件记录
    final fileRecord = DbFileRecord(
      fileHash: fileHash,
      fileName: fileName,
      fileSize: fileSize,
    );
    await DatabaseService.upsertMediaFile(fileRecord);

    // 查找数据库是否有对应的 Dandanplay Episode ID
    final episodeInDb = await DatabaseService.getDandanplayEpisodeRecordById(matchResult.dandanplayEpisodeId);
    if (episodeInDb != null) {

      printMsg(color("找到对应的 Dandanplay Episode 记录:", ColorCode.green));
      printMsg(
        '${color('Dandanplay Episode Record in Database', ColorCode.boldCyan)}: '
        'ID=${episodeInDb.dandanplayEpisodeId}, '
        '标题=${episodeInDb.title}, '
        '集数=${episodeInDb.sortOrder}, '
        'Anime ID=${episodeInDb.dandanplayAnimeId}',
      );
    } else {

      printMsg(color('$testLabel: 数据库中未找到对应的 Dandanplay Episode ID=${matchResult.dandanplayEpisodeId} 的记录', ColorCode.red));

      final ppdAniPkg = await AnimeInfoService.getDandanplayAnimePackageByID(matchResult.dandanplayAnimeId);
      printMsg(
        '${color('Dandanplay Anime Package', ColorCode.boldCyan)}: '
        'ID=${ppdAniPkg!.anime.dandanplayAnimeId}, '
        '标题=${ppdAniPkg.anime.title}, '
        '剧集数=${ppdAniPkg.episodes.length}',
      );

      await DatabaseService.upsertDanDanPlayAnimePackage(ppdAniPkg); // 插入
    }

    await DatabaseService.upsertDandanplayFileDanmaku(fileHash, matchResult.dandanplayEpisodeId, matchResult.danmakuOffset);
  });
}

