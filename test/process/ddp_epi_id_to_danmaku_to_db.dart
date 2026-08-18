
// test/process/ddp_epi_id_to_danmaku_db.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/database/dandanplay_danmaku_record.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {

  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final testLabel = color('[Dandanplay Episode ID -> Danmaku -> Database]', ColorCode.boldBlue);

  test(testLabel, () async {

    final ddpEpiId = getIntFromEnv(TestEnvironmentVariables.dandanplayEpisodeId);
    final dbPath   = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (ddpEpiId == null || dbPath == null) {
      printMsg('$testLabel ${color('测试未运行', ColorCode.red)}');
      return;
    }

    final danmakuJson = await AnimeInfoService.getDandanplayDanmakuJsonByEpisodeId(ddpEpiId);
    if (danmakuJson == null) {
      printMsg('$testLabel ${color('未获取到弹幕', ColorCode.red)}');
      return;
    }
    printMsg(
      '${color('Dandanplay Danmaku', ColorCode.boldCyan)}: '
      'Episode ID=$ddpEpiId, JSON长度=${danmakuJson.length}',
    );

    await DatabaseService.initialize(dbPath);

    final episode = await DatabaseService.getDandanplayEpisodeRecordById(ddpEpiId);
    if (episode == null) throw StateError('数据库中不存在 Dandanplay Episode ID=$ddpEpiId 的记录');

    await DatabaseService.upsertDandanplayDanmaku(
      DbDandanplayDanmakuRecord(
        dandanplayEpisodeId: ddpEpiId,
        danmakuJson: danmakuJson,
      ),
    );

    printMsg(color('$testLabel: 弹幕已插入或更新数据库', ColorCode.green));
  });
}