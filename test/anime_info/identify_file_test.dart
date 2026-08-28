
// test/anime_info/identify_file_test.dart

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

  test('刷新文件的 Dandanplay 弹幕关联', () async {

    final filePath = getStringFromEnv(TestEnvironmentVariables.filePath);
    final databasePath = getStringFromEnv(TestEnvironmentVariables.databasePath);
    if (filePath == null || databasePath == null) {
      printMsg(color('测试未运行', ColorCode.red));
      return;
    }

    await DatabaseService.initialize(databasePath);
    await AnimeInfoService.identifyFile(filePath);
  });
}
