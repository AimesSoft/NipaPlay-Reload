
// test/anime_info/refresh_dandanplay_episode_danmaku_json_cache_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info/anime_info_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {

  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('刷新 Dandanplay Episode Danmaku 到缓存', () async {

    final dandanplayEpisodeId = getIntFromEnv(TestEnvironmentVariables.dandanplayEpisodeId);
    if (dandanplayEpisodeId == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    await AnimeInfoService.refreshDandanplayDanmakuCacheByEpisodeId(dandanplayEpisodeId);
  });
}
