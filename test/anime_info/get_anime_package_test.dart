
// test/anime_info/bangumi_tv_record_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {

  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('bgm ani id -> bgm ani pkg', () async {

    final bgmAniId = getIntFromEnv(TestEnvironmentVariables.bangumiTvAnimeId);
    if (bgmAniId == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    printMsg('${color('测试 Bangumi AnimeID', ColorCode.boldCyan)}: $bgmAniId');

    final anime = await AnimeInfoService.getBangumiAnimePackageById(bgmAniId);
    if (anime == null) {
      printMsg(color('未获取到 Bangumi Anime Package', ColorCode.red));
      return;
    }

    printMsg(
      '${color('Bangumi Anime ID', ColorCode.boldCyan)}: ${anime.anime.bangumiAnimeId}, '
      '${color('动画标题', ColorCode.boldCyan)}: ${anime.anime.title}',
    );

    for (final episode in anime.episodes) {
      printMsg(
        '${color('BangumiTv EpisodeID', ColorCode.boldCyan)}: '
        '${episode.bangumiEpisodeId}, ${color('Episode标题', ColorCode.boldCyan)}: '
        '${episode.title}, ${color('Episode排序', ColorCode.boldCyan)}: '
        '${episode.sortOrder}',
      );
    }
  });

  test('ddp ani id -> ddp ani pkg', () async {

    final ddpAniId = getIntFromEnv(TestEnvironmentVariables.dandanplayAnimeId);
    if (ddpAniId == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    printMsg('${color('测试 DanDanPlay AnimeID', ColorCode.boldCyan)}: $ddpAniId');

    final aniPkg = await AnimeInfoService.getDandanplayAnimePackageByID(ddpAniId);
    if (aniPkg == null) {
      printMsg(color('未获取到 DanDanPlay Anime Package', ColorCode.red));
      return;
    }

    printMsg(
      '${color('DanDanPlay AnimeID', ColorCode.boldCyan)}: '
      '${aniPkg.anime.dandanplayAnimeId}, ${color('动画标题', ColorCode.boldCyan)}: '
      '${aniPkg.anime.title}',
    );
    for (final episode in aniPkg.episodes) {
      printMsg(
        '${color('DanDanPlay EpisodeID', ColorCode.boldCyan)}: '
        '${episode.dandanplayEpisodeId}, ${color('Episode标题', ColorCode.boldCyan)}: '
        '${episode.title}, ${color('Episode排序', ColorCode.boldCyan)}: '
        '${episode.sortOrder}',
      );
    }
  });
}
