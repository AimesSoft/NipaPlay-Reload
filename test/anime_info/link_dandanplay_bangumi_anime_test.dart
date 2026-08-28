
// test/anime_info/link_dandanplay_bangumi_anime_test.dart


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

  test('关联 Dandanplay 与 Bangumi 番剧', () async {

    final commonAnimeId = getIntFromEnv(TestEnvironmentVariables.commentAnimeId);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (commonAnimeId == null || databasePath == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(databasePath);
    await AnimeInfoService.linkDandanplayBangumiAnime(commonAnimeId);
    await AnimeInfoService.debugAnimeEpisodeRelations();
  });
}
