
// test/anime_info/refresh_bangumi_anime_relation_by_cache_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {

  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('从 Bangumi Anime JSON 缓存刷新数据库关系', () async {

    final bangumiAnimeId = getIntFromEnv(TestEnvironmentVariables.bangumiTvAnimeId);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (bangumiAnimeId == null || databasePath == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(databasePath);
    await AnimeInfoService.refreshBangumiAnimeRelationByCache(bangumiAnimeId);
  });
}
