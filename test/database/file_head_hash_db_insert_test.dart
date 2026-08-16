
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/database/file_record.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/file_hash.dart';

import '../environment_variables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('给定文件路径时可计算前16MiB哈希并写入file表', () async {

    bool canRun = true;

    final envFilePath = Platform.environment[TestEnvironmentVariables.filePath]?.trim();
    final envDbPath = Platform.environment[TestEnvironmentVariables.databasePath]?.trim();
    if (envFilePath == null || envFilePath.isEmpty) {
      debugPrint('${color('测试文件路径', ColorCode.boldCyan)}: ${color('未设置', ColorCode.red)}');
      canRun = false;
    }
    if (envDbPath == null || envDbPath.isEmpty) {
      debugPrint('${color('测试数据库路径', ColorCode.boldCyan)}: ${color('未设置', ColorCode.red)}');
      canRun = false;
    }
    if (!canRun) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    // 准备变量
    final filePath = envFilePath!;
    final dbPath = envDbPath!;
    debugPrint('${color('测试文件路径', ColorCode.boldCyan)}: $filePath');
    debugPrint('${color('测试数据库路径', ColorCode.boldCyan)}: $dbPath');

    final file = File(filePath);
    expect(file.existsSync(), isTrue, reason: '测试文件不存在: $filePath');
    final actualHash = await computeFileHeadMd5(file.path);
    expect(actualHash, isNotEmpty);
    debugPrint('计算文件前16MiB的MD5哈希: $actualHash');

    // 初始化数据库服务
    await DatabaseService.initialize(dbPath);

    final record = DbFileRecord(
      fileHash: actualHash,
      fileName: file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : file.path.split('/').last,
      fileSize: await file.length(),
    );
    await DatabaseService.upsertMediaFile(record);

    final fromDb = await DatabaseService.getMediaFileByHash(actualHash);

    expect(fromDb, isNotNull);
    expect(fromDb!.fileHash, actualHash);
    expect(fromDb.fileName, record.fileName);
  });
}
