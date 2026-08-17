
// test/anime_info/bangumi_tv_id_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {

  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('ddp ani id -> bgm ani id', () async {

    final ddpAniId = getIntFromEnv(TestEnvironmentVariables.dandanplayAnimeId);
    if (ddpAniId == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    printMsg('${color('Dandanplay Anime ID', ColorCode.boldCyan)}: $ddpAniId');

    final bgmId = await AnimeInfoService.getBangumiIdByDandanplayId(ddpAniId);
    printMsg('${color('Bangumi Anime ID', ColorCode.boldCyan)}: $bgmId');

  });

  test('bgm ani id -> ddp ani id', () async {

    final bgmId = getIntFromEnv(TestEnvironmentVariables.bangumiTvAnimeId);
    if (bgmId == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    printMsg('${color('Bangumi Anime ID', ColorCode.boldCyan)}: $bgmId');

    final ddpId = await AnimeInfoService.getDandanplayIdByBangumiId(bgmId);
    printMsg('${color('Dandanplay Anime ID', ColorCode.boldCyan)}: $ddpId');

  });
}