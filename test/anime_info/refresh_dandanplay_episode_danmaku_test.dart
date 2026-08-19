
// test/anime_info/refresh_dandanplay_episode_danmaku_test.dart

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

  test('刷新 Dandanplay Episode Danmaku 到数据库', () async {

    final dandanplayEpisodeId = getIntFromEnv(TestEnvironmentVariables.dandanplayEpisodeId);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (dandanplayEpisodeId == null || databasePath == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(databasePath);
    await AnimeInfoService.refreshDandanplayEpisodeDanmakuById(
      dandanplayEpisodeId,
    );

    printMsg(
      '${color('Dandanplay Danmaku Refresh', ColorCode.boldCyan)}: '
      'Episode ID=$dandanplayEpisodeId 的弹幕 JSON 已刷新',
    );
  });
}
