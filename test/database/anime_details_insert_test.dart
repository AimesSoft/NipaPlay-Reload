import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/database/episode_record.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';

import '../environment_variables.dart';


void main() {
  test('输入数据库地址和AnimeID后拉取动画与分集并写入数据库', () async {

    bool canRun = true;

    // 读取环境变量
    final envDbPath = Platform.environment[TestEnvironmentVariables.databasePath]?.trim();
    final envAnimeIdText = Platform.environment[TestEnvironmentVariables.animeId]?.trim();
    if (envDbPath == null || envDbPath.isEmpty) {
      debugPrint('${color('测试数据库路径', ColorCode.boldCyan)}: ${color('未设置', ColorCode.red)}');
      canRun = false;
    }
    if (envAnimeIdText == null || envAnimeIdText.isEmpty) {
      debugPrint('${color('测试 AnimeID', ColorCode.boldCyan)}: ${color('未设置', ColorCode.red)}');
      canRun = false;
    }
    final envAnimeId = int.tryParse(envAnimeIdText ?? '');
    if (envAnimeId == null || envAnimeId <= 0) {
      debugPrint('${color('测试 AnimeID', ColorCode.boldCyan)}: ${color('无效', ColorCode.red)}');
      canRun = false;
    }
    if (!canRun) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    final dbPath = envDbPath!;
    final animeId = envAnimeId!;
    debugPrint('${color('测试数据库路径', ColorCode.boldCyan)}: $dbPath');
    debugPrint('${color('测试 AnimeID', ColorCode.boldCyan)}: $animeId');


    // 初始化数据库服务
    await DatabaseService.initialize(dbPath);

    // 拉取动画详情
    final animeInfo = await AnimeInfoService.getAnimeInfoByDanDanPlayID(animeId);
    final episodeRecords = await AnimeInfoService.getAnimeEpisodesByDanDanPlayID(animeId) ?? <DbEpisodeRecord>{};

    // 打印
    debugPrint('${color('AnimeID', ColorCode.boldCyan)}: $animeId, ${color('Anime标题', ColorCode.boldCyan)}: ${animeInfo!.title}');
    for (final episode in episodeRecords) {
      debugPrint('${color('EpisodeID', ColorCode.boldCyan)}: ${episode.id}, ${color('Episode标题', ColorCode.boldCyan)}: ${episode.title}, ${color('Episode排序', ColorCode.boldCyan)}: ${episode.sortOrder}');
    }

    // 写入数据库
    await DatabaseService.upsertMediaAnime(animeInfo);
    for (final record in episodeRecords) { await DatabaseService.upsertMediaEpisode(record); }

    // 从数据库读取并验证
    final fromDb = await DatabaseService.getEpisodeRecordsByAnimeId(animeId);
    expect(fromDb, isNotEmpty);
    expect(fromDb.length, greaterThanOrEqualTo(episodeRecords.length));
  });
}
