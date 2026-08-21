
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('输出 Anime 和 Episode 关联关系', () async {

    final envDbPath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (envDbPath == null || envDbPath.isEmpty) {
      debugPrint('测试数据库路径未设置, 测试未运行');
      return;
    }

    await DatabaseService.initialize(envDbPath);
    await AnimeInfoService.debugAnimeEpisodeRelations();
  });
}
