
// test/anime_info/refresh_dandanplay_anime_cache_json_test.dart

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

  test('刷新 Dandanplay Anime Info 到 JSON 缓存', () async {

    final dandanplayAnimeId = getIntFromEnv(TestEnvironmentVariables.dandanplayAnimeId);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (dandanplayAnimeId == null || databasePath == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(databasePath);
    await AnimeInfoService.refreshDandanplayAnimeCache(dandanplayAnimeId);
  });
}
