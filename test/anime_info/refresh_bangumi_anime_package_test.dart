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

  test('刷新 Bangumi Anime Package 到数据库', () async {

    final bangumiAnimeId = getIntFromEnv(TestEnvironmentVariables.bangumiTvAnimeId);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (bangumiAnimeId == null || databasePath == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(databasePath);
    await AnimeInfoService.refreshBangumiAnimePackageById(bangumiAnimeId);

    final anime = await DatabaseService.getBangumiAnimeRecordById(bangumiAnimeId);
    printMsg(
      '${color('Bangumi Anime Record', ColorCode.boldCyan)}: '
      'ID=${anime?.bangumiAnimeId}, 标题=${anime?.title}',
    );
  });
}
