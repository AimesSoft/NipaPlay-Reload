
// lib/services/anime_info/util.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:nipaplay/utils/anime_info_parse.dart';
import 'package:nipaplay/utils/storage_service.dart';

enum JsonFileType {

  anime,
  episode,

  dandanplay,
  danmaku,
  bangumi,

}


typedef JsonData = Map<String, dynamic>;

/// 保存 JSON 数据到本地文件
Future<void> saveJsonToFile(JsonFileType fileType, int id, JsonData jsonData) async {

  final file = File(await _getFilePath(fileType, id));
  final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
  await file.writeAsString(jsonString);

  debugPrint('已保存 JSON 数据到文件: ${await _getFilePath(fileType, id)}');
}


Future<int?> getBangumiAnimeIdByDandanplayAnimeIdFromCache(int ddpAniId) async {

  final cacheFile = File(await _getFilePath(JsonFileType.dandanplay, ddpAniId));
  if (!await cacheFile.exists()) return null;

  final decoded = jsonDecode(await cacheFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Dandanplay Anime 缓存格式无效');
  }

  final anime = decoded['anime'];
  if (anime is! Map) {
    throw const FormatException('Dandanplay Anime 缓存缺少 anime 对象');
  }

  return AnimeInfoParse.getBangumiTvId(
    Map<String, dynamic>.from(anime),
  );
}

Future<void> storeDandanplayEpisodeDanmakuOffset(int commonEpiId, double offset) async {

  final cacheFile = File(await _getFilePath(JsonFileType.episode, commonEpiId));
  if (!await cacheFile.exists()) {
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        <String, dynamic>{'dandanplayOffset': offset},
      ),
    );
    debugPrint('已创建 Dandanplay Episode 缓存并保存 dandanplayOffset: ${cacheFile.path}');
    return;
  }

  final decoded = jsonDecode(await cacheFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Dandanplay Episode 缓存格式无效');
  }

  decoded['dandanplayOffset'] = offset;

  final jsonString = const JsonEncoder.withIndent('  ').convert(decoded);
  await cacheFile.writeAsString(jsonString);

  debugPrint('已更新 Dandanplay Episode 缓存的 dandanplayOffset: ${cacheFile.path}');
}

Future<void> storeDandanplayEpisodeMatchStatus(int commonEpiId, bool isMatched) async {

  final cacheFile = File(await _getFilePath(JsonFileType.episode, commonEpiId));
  if (!await cacheFile.exists()) {
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        <String, dynamic>{'isMatchedDandanplay': isMatched},
      ),
    );
    debugPrint('已创建 Dandanplay Episode 缓存并保存 isMatched: ${cacheFile.path}');
    return;
  }

  final decoded = jsonDecode(await cacheFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Dandanplay Episode 缓存格式无效');
  }

  decoded['isMatchedDandanplay'] = isMatched;

  final jsonString = const JsonEncoder.withIndent('  ').convert(decoded);
  await cacheFile.writeAsString(jsonString);

  debugPrint('已更新 Dandanplay Episode 缓存的 isMatchedDandanplay: ${cacheFile.path}');
}

Future<bool> getDandanplayEpisodeMatchStatus(int commonEpiId) async {
  final cacheFile = File(await _getFilePath(JsonFileType.episode, commonEpiId));
  if (!await cacheFile.exists()) return false;

  final decoded = jsonDecode(await cacheFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Dandanplay Episode 缓存格式无效');
  }

  return decoded['isMatchedDandanplay'] == true;
}


Future<String> _getFilePath(JsonFileType fileType, int id) async {

  final appDir = await StorageService.getAppStorageDirectory();
  return switch (fileType) {
    JsonFileType.anime      => '${appDir.path}/anime/$id.json',
    JsonFileType.episode    => '${appDir.path}/episode/$id.json',

    JsonFileType.dandanplay => '${appDir.path}/cache/dandanplay/$id.json',
    JsonFileType.danmaku    => '${appDir.path}/cache/danmaku/$id.json',
    JsonFileType.bangumi    => '${appDir.path}/cache/bangumi/$id.json',
  };
}