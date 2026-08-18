
// test/process/ddp_ani_id_to_pkg_to_db_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {

  // 初始化 Flutter 测试环境
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{SettingsKeys.autoMatchDanmakuFirstSearchResultOnHashFail: false});

  final testLabel = color('[Dandanplay Anime ID -> Dandanplay Anime Package -> Database]', ColorCode.boldBlue);

  test(testLabel, () async {

    // 输入
    printMsg(color('$testLabel: 获取输入', ColorCode.boldBlue));
    final ddpId = getIntFromEnv(TestEnvironmentVariables.dandanplayAnimeId);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (ddpId == null || databasePath == null) {
      debugPrint('$testLabel ${color('测试未运行', ColorCode.red)}');
      return;
    }

    // 获取 Dandanplay Anime Package
    printMsg(color('$testLabel: 获取 Dandanplay Anime Package', ColorCode.boldBlue));
    final dandanplayAnimePackage = await AnimeInfoService.getDandanplayAnimePackageByID(ddpId);
    printMsg(
      '${color('DanDanPlay Anime Package', ColorCode.boldCyan)}: '
      'ID=${dandanplayAnimePackage!.anime.dandanplayAnimeId}, '
      '标题=${dandanplayAnimePackage.anime.title}, '
      '剧集数=${dandanplayAnimePackage.episodes.length}',
    );
    for (final episode in dandanplayAnimePackage.episodes) {
      printMsg(
        '  ${color('Episode', ColorCode.boldCyan)}: '
        'ID=${episode.dandanplayEpisodeId}, '
        '标题=${episode.title}, '
        '集数=${episode.sortOrder}',
      );
    }

    // 数据库操作
    printMsg(color('$testLabel: 数据库操作', ColorCode.boldBlue));
    await DatabaseService.initialize(databasePath);

    // 将 Dandanplay Anime Package 保存到数据库
    await DatabaseService.upsertDanDanPlayAnimePackage(dandanplayAnimePackage);

    // 验证数据库中是否存在该 Anime
    final animeInDb = await DatabaseService.getDandanplayAnimeRecordById(ddpId);
    expect(animeInDb, isNotNull, reason: '数据库中未找到 Anime ID=$ddpId 的记录');
    printMsg(
      '${color('Anime Record in Database', ColorCode.boldCyan)}: '
      'ID=${animeInDb!.dandanplayAnimeId}, '
      '标题=${animeInDb.title}, '
    );

  });
}

