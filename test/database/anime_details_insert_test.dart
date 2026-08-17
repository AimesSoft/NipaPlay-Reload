
// test/database/anime_details_insert_test.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {

  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('ddp id -> ddp ani pkg 插入数据库', () async {

    // 读取环境变量
    final dbPath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    final animeId = getIntFromEnv(TestEnvironmentVariables.dandanplayAnimeId);
    if (dbPath == null || animeId == null) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    // 初始化数据库服务
    await DatabaseService.initialize(dbPath);

    // 拉取动画详情
    final pkg = await AnimeInfoService.getDandanplayAnimePackageByID(animeId);
    if (pkg == null) {
      debugPrint(color('未获取到 DanDanPlay Anime Package', ColorCode.red));
      return;
    }

    // 打印
    printMsg(
      '${color('DanDanPlay Anime ID', ColorCode.boldCyan)}: ${pkg.anime.dandanplayAnimeId}, '
      '${color('动画标题', ColorCode.boldCyan)}: ${pkg.anime.title}',
    );
    for (final episode in pkg.episodes) {
      printMsg(
        '${color('DanDanPlay EpisodeID', ColorCode.boldCyan)}: '
        '${episode.dandanplayEpisodeId}, ${color('Episode标题', ColorCode.boldCyan)}: '
        '${episode.title}, ${color('Episode排序', ColorCode.boldCyan)}: ${episode.sortOrder}',
      );
    }

    // 写入数据库
    await DatabaseService.upsertDanDanPlayAnimePackage(pkg);

    // 从数据库读取并验证
    final fromDb = await DatabaseService.getDandanplayEpisodeRecordsById(animeId);
    expect(fromDb, isNotNull);
    expect(fromDb, isNotEmpty);
    expect(fromDb!.length, greaterThanOrEqualTo(pkg.episodes.length));
  });

  test('bgm id -> bgm ani pkg 插入数据库', () async {

    // 读取环境变量
    final dbPath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    final animeId = getIntFromEnv(TestEnvironmentVariables.bangumiTvAnimeId);
    if (dbPath == null || animeId == null) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    // 初始化数据库服务
    await DatabaseService.initialize(dbPath);

    // 拉取动画详情
    final pkg = await AnimeInfoService.getBangumiAnimePackageById(animeId);
    if (pkg == null) {
      debugPrint(color('未获取到 Bangumi Anime Package', ColorCode.red));
      return;
    }

    // 打印
    printMsg(
      '${color('Bangumi Anime ID', ColorCode.boldCyan)}: ${pkg.anime.bangumiAnimeId}, '
      '${color('动画标题', ColorCode.boldCyan)}: ${pkg.anime.title}',
    );
    for (final episode in pkg.episodes) {
      printMsg(
        '${color('BangumiTv EpisodeID', ColorCode.boldCyan)}: '
        '${episode.bangumiEpisodeId}, ${color('Episode标题', ColorCode.boldCyan)}: '
        '${episode.title}, ${color('Episode排序', ColorCode.boldCyan)}: '
        '${episode.sortOrder}',
      );
    }

    // 写入数据库
    await DatabaseService.upsertBangumiAnimePackage(pkg);

    // 从数据库读取并验证
    final fromDb = await DatabaseService.getBangumiEpisodeRecordsById(animeId);
    expect(fromDb, isNotNull);
    expect(fromDb, isNotEmpty);
    expect(fromDb!.length, greaterThanOrEqualTo(pkg.episodes.length));

  });
}
