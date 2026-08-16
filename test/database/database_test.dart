
// test/database/database_test.dart
// 数据库相关测试

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';

import '../environment_variables.dart';


void main() {
  test('给定数据库路径后打印相关数据', () async {

    bool canRun = true;

    final envDbPath = Platform.environment[TestEnvironmentVariables.databasePath]?.trim();
    if (envDbPath == null || envDbPath.isEmpty) {
      debugPrint('${color('测试数据库路径', ColorCode.boldCyan)}: ${color('未设置', ColorCode.red)}');
      canRun = false;
    }
    if (!canRun) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    final dbPath = envDbPath!;
    debugPrint('${color('测试数据库路径', ColorCode.boldCyan)}: $dbPath');

    await DatabaseService.initialize(dbPath);

    try {
      final String dbLabel = color('[DB]', ColorCode.blue);

      // 打印出所有表格
      debugPrint('$dbLabel 打印所有表格');
      final tables = await DatabaseService.getTableNames();
      debugPrint('$dbLabel tables: $tables');

      // 打印出 Anime 表的前 5 条记录
      debugPrint('$dbLabel 打印 Anime 表的前 5 条记录');
      final animeRecords = await DatabaseService.getAnimeRecords(5);
      if (animeRecords != null) {
        for (final record in animeRecords) {
          debugPrint('$dbLabel anime record: ${record.toMap()}');
        }
      } else {
        debugPrint('$dbLabel anime record: null');
      }

    } catch (e) {
      debugPrint('数据库测试失败: $e');
      rethrow;

    } finally {
      // await db.close(); // DatabaseService does not expose the db instance anymore
    }
  });
}
