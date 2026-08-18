
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/color.dart';


void printMsg(String msg) {if (kDebugMode) print(msg); }

/// 从环境变量中获取整数值, 如果未设置或无效, 则返回 null
int? getIntFromEnv(String envName) {
  final envIdStr = Platform.environment[envName]?.trim();
  final envId = int.tryParse(envIdStr ?? '');
  if (envId == null || envId <= 0) {
    printMsg(
      '${color('$envName (预计类型: int)', ColorCode.boldCyan)}: '
      '${color('未设置或无效', ColorCode.red)}',
    );
    return null;
  }
  printMsg('${color('$envName (预计类型: int)', ColorCode.boldCyan)}: $envId');
  return envId;
}


String? getStringFromEnv(String envName) {
  final envValue = Platform.environment[envName]?.trim();
  if (envValue == null || envValue.isEmpty) {
    printMsg(
      '${color('$envName (预计类型: String)', ColorCode.boldCyan)}: '
      '${color('未设置或无效', ColorCode.red)}',
    );
    return null;
  }
  printMsg('${color('$envName (预计类型: String)', ColorCode.boldCyan)}: $envValue');
  return envValue;
}

int? toPositiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : null;
}


void saveStringToFile(String filePath, String content) {
  final file = File(filePath);
  file.writeAsStringSync(content);
  printMsg('${color('已保存到文件', ColorCode.boldCyan)}: $filePath');
}