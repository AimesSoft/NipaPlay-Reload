
// lib/services/anime_info/storage_repository.darts

part of 'anime_info_service.dart';


/// 保存 Dandanplay Episode 的弹幕偏移量到缓存文件
Future<void> storeDandanplayEpisodeDanmakuOffset(Uint8List fileHash, double offset) async {

  final filePath = await _getFilePathByHash(JsonFileType.video, fileHash);
  if (filePath == null) throw ArgumentError('无法获取文件路径: JsonFileType.video, $fileHash');
  final cacheFile = File(filePath);
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

/// 保存 Dandanplay Episode 的匹配状态到缓存文件
Future<void> storeDandanplayEpisodeMatchStatus(Uint8List fileHash, bool isMatched) async {

  final filePath = await _getFilePathByHash(JsonFileType.video, fileHash);
  if (filePath == null) throw ArgumentError('无法获取文件路径: JsonFileType.video, $fileHash');
  final cacheFile = File(filePath);
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


/// 获取 Dandanplay Episode 的匹配状态
Future<bool?> getDandanplayEpisodeMatchStatusByHash(Uint8List fileHash) async {

  final filePath = await _getFilePathByHash(JsonFileType.video, fileHash);
  if (filePath == null) return null;
  final cacheFile = File(filePath);
  if (!await cacheFile.exists()) return null;

  final decoded = jsonDecode(await cacheFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Dandanplay Episode 缓存格式无效');
  }

  return decoded['isMatchedDandanplay'] == true;
}
