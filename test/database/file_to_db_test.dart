
// test/database/file_to_db_test.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/database/asset_record.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/file_hash.dart';

import '../environment_variables.dart';
import '../test_util/io.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('File Path -> File Hash -> DB', () async {

    bool canRun = true;

    final envFilePath = getStringFromEnv(TestEnvironmentVariables.filePath);
    final envDbPath = getStringFromEnv(TestEnvironmentVariables.databasePath);
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

    final file = File(filePath);
    expect(file.existsSync(), isTrue, reason: '测试文件不存在: $filePath');
    final actualHash = await computeFileHeadMd5(file.path);
    expect(actualHash, isNotEmpty);
    debugPrint('计算文件前16MiB的MD5哈希: $actualHash');
    final assetHash = decodeHex(actualHash, expectedBytes: 16);
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : file.path.split('/').last;
    final extensionIndex = fileName.lastIndexOf('.');
    final codec = extensionIndex >= 0 && extensionIndex < fileName.length - 1
        ? fileName.substring(extensionIndex + 1).toLowerCase()
        : null;
    final fileSize = await file.length();
    final record = DbAssetRecord(
      hashPre16MiBMd5: assetHash,
      size: fileSize,
      codec: codec,
    );


    await DatabaseService.initialize(dbPath);
    await DatabaseService.upsertAssetRecord(record);
  });
}
