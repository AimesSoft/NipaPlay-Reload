
// test/anime_info/link_dandanplay_bangumi_anime_test.dart

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

  test('关联 Dandanplay 与 Bangumi 番剧', () async {

    final dandanplayAnimeId = getIntFromEnv(TestEnvironmentVariables.dandanplayAnimeId);
    final bangumiAnimeId = getIntFromEnv(TestEnvironmentVariables.bangumiTvAnimeId);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (dandanplayAnimeId == null || bangumiAnimeId == null || databasePath == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(databasePath);

    await AnimeInfoService.linkDandanplayAnimeWithBangumiAnime(dandanplayAnimeId, bangumiAnimeId);

    final dandanplayAnime = await DatabaseService.getDandanplayAnimeRecordById(dandanplayAnimeId);
    final bangumiAnime = await DatabaseService.getBangumiAnimeRecordById(bangumiAnimeId);
    printMsg(
      '${color('Dandanplay Anime Record', ColorCode.boldCyan)}: '
      'ID=${dandanplayAnime?.dandanplayAnimeId}, '
      '关联 Bangumi ID=${dandanplayAnime?.bangumiAnimeId}, '
      '标题=${dandanplayAnime?.title}',
    );
    printMsg(
      '${color('Bangumi Anime Record', ColorCode.boldCyan)}: '
      'ID=${bangumiAnime?.bangumiAnimeId}, 标题=${bangumiAnime?.title}',
    );

    final dandanplayEpisodes = await DatabaseService.getDandanplayEpisodeRecordsById(dandanplayAnimeId);
    final bangumiEpisodes = await DatabaseService.getBangumiEpisodeRecordsById(bangumiAnimeId);
    final bangumiSortOrders = bangumiEpisodes
        .map((episode) => episode.sortOrder)
        .whereType<double>()
        .toSet();
    final matchedCount = dandanplayEpisodes
        .where((episode) => bangumiSortOrders.contains(episode.sortOrder))
        .length;
    printMsg(
      '${color('Episode 匹配情况', ColorCode.boldCyan)}: '
      'Dandanplay=${dandanplayEpisodes.length}, '
      'Bangumi=${bangumiEpisodes.length}, '
      '匹配=$matchedCount',
    );
  });
}
