import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';

void main() {

  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final testLabel = color(
    '[Bangumi Anime ID -> Bangumi Anime Package -> Database]',
    ColorCode.boldBlue,
  );

  test(testLabel, () async {

    printMsg(color('$testLabel: 获取输入', ColorCode.boldBlue));
    final bangumiAnimeId = getIntFromEnv(TestEnvironmentVariables.bangumiTvAnimeId);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (bangumiAnimeId == null || databasePath == null) {
      printMsg('$testLabel ${color('测试未运行', ColorCode.red)}');
      return;
    }


    printMsg(color('$testLabel: 获取 Bangumi Anime Package', ColorCode.boldBlue));
    final bangumiAnimePackage = await AnimeInfoService.getBangumiAnimePackageById(bangumiAnimeId);
    if (bangumiAnimePackage == null) {
      throw StateError('未获取到 Bangumi Anime Package: $bangumiAnimeId');
    }
    printMsg(
      '${color('Bangumi Anime Package', ColorCode.boldCyan)}: '
      'ID=${bangumiAnimePackage.anime.bangumiAnimeId}, '
      '标题=${bangumiAnimePackage.anime.title}, '
      '剧集数=${bangumiAnimePackage.episodes.length}',
    );
    for (final episode in bangumiAnimePackage.episodes) {
      printMsg(
        '  ${color('Episode', ColorCode.boldCyan)}: '
        'ID=${episode.bangumiEpisodeId}, '
        '标题=${episode.title}, '
        '集数=${episode.sortOrder}',
      );
    }


    printMsg(color('$testLabel: 数据库操作', ColorCode.boldBlue));
    await DatabaseService.initialize(databasePath);
    await DatabaseService.upsertBangumiAnimePackage(bangumiAnimePackage);


    final animeInDb = await DatabaseService.getBangumiAnimeRecordById(bangumiAnimeId);
    expect(
      animeInDb,
      isNotNull,
      reason: '数据库中未找到 Bangumi Anime ID=$bangumiAnimeId 的记录',
    );
    printMsg(
      '${color('Anime Record in Database', ColorCode.boldCyan)}: '
      'ID=${animeInDb!.bangumiAnimeId}, '
      '标题=${animeInDb.title}',
    );
  });
}
