
// lib/services/anime_info/util.dart

part of 'anime_info_service.dart';



final String _label =  color('[Anime Info Service]', ColorCode.boldMagenta);
void _printLine(String message) => debugPrint('$_label ${color(message, ColorCode.gray)}');
String _val(Object str) => color(str.toString(), ColorCode.boldWhite);

/// 将字节数格式化为易读的文件大小字符串, 例如 "12.34 MiB"
String _formatFileSize(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  double size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final formatted = unitIndex == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(2);
  return '$formatted ${units[unitIndex]}';
}

final String _bgmLabel = color('Bangumi', ColorCode.pink);
final String _ddpLabel = color('Dandanplay', ColorCode.cyan);

enum JsonFileType {

  anime,
  episode,

  dandanplay,
  danmaku,
  bangumi,

  video,
}


typedef JsonData = Map<String, dynamic>;

/// 保存 JSON 数据到本地文件
Future<void> saveJsonToFile(JsonFileType fileType, int id, JsonData jsonData) async {

  final filePath = await _getFilePathById(fileType, id);
  if (filePath == null) throw ArgumentError('无法获取文件路径: $fileType, $id');
  final file = File(filePath);
  final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
  await file.writeAsString(jsonString);

  debugPrint('已保存 JSON 数据到文件: ${await _getFilePathById(fileType, id)}');
}


Future<int?> getBangumiAnimeIdByDandanplayAnimeIdFromCache(int ddpAniId) async {

  final filePath = await _getFilePathById(JsonFileType.dandanplay, ddpAniId);
  if (filePath == null) return null;
  final cacheFile = File(filePath);
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

Future<bool> getDandanplayEpisodeMatchStatus(int commonEpiId) async {

  final filePath = await _getFilePathById(JsonFileType.episode, commonEpiId);
  if (filePath == null) return false;
  final cacheFile = File(filePath);
  if (!await cacheFile.exists()) return false;

  final decoded = jsonDecode(await cacheFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Dandanplay Episode 缓存格式无效');
  }

  return decoded['isMatchedDandanplay'] == true;
}


Future<String?> _getFilePathById(JsonFileType fileType, int id) async {

  final appDir = await StorageService.getAppStorageDirectory();
  return switch (fileType) {
    JsonFileType.anime      => '${appDir.path}/anime/$id.json',
    JsonFileType.episode    => '${appDir.path}/episode/$id.json',

    JsonFileType.dandanplay => '${appDir.path}/cache/dandanplay/$id.json',
    JsonFileType.danmaku    => '${appDir.path}/cache/danmaku/$id.json',
    JsonFileType.bangumi    => '${appDir.path}/cache/bangumi/$id.json',

    // 其他类型未定义路径
    _ => throw ArgumentError('不支持的 JsonFileType: $fileType'),
  };
}

Future<String?> _getFilePathByHash(JsonFileType fileType, Uint8List hash) async {

  final appDir = await StorageService.getAppStorageDirectory();
  final hashHex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return switch (fileType) {

    JsonFileType.video => '${appDir.path}/video/$hashHex.json',

    // 其他类型未定义路径
    _ => throw ArgumentError('不支持的 JsonFileType: $fileType'),
  };
}

JsonData _decodeAnimePackageCache(String content, String sourceName) {
  final decoded = jsonDecode(content);
  if (decoded is! Map) throw FormatException('$sourceName Anime Package 缓存格式无效');
  return Map<String, dynamic>.from(decoded);
}

DbAnimeEpisodeRelation _parseAnimeEpisodeRelationDandanplay(JsonData jsonObject) {

  final anime = jsonObject['anime'];
  if (anime is! Map) {
    throw const FormatException('Dandanplay Anime Package 缺少 anime 对象');
  }
  final animeId = AnimeInfoParse.toPositiveInt(anime['animeId']);
  if (animeId == null) {
    throw const FormatException('Dandanplay Anime Package 缺少有效的 animeId');
  }

  final episodeIdsBySortOrder = _parseEpisodeIdsBySortOrder(
    jsonObject,
    episodeIdKey: 'episodeId',
    sortOrderKey: 'episodeNumber',
    sourceName: 'Dandanplay',
  );
  return DbAnimeEpisodeRelation(
    animeId: animeId,
    episodeIds: episodeIdsBySortOrder.values,
  );
}

Map<double, int> _parseEpisodeIdsBySortOrder(
  Map<String, dynamic> jsonObject, {
  required String episodeIdKey,
  required String sortOrderKey,
  required String sourceName,
}) {
  final rawEpisodes = jsonObject['episodes'];
  if (rawEpisodes is! List) {
    throw FormatException('$sourceName Anime Package 缺少 episodes 数组');
  }

  final episodeIdsBySortOrder = <double, int>{};
  for (final rawEpisode in rawEpisodes) {
    if (rawEpisode is! Map) continue;
    final episodeId =
        AnimeInfoParse.toPositiveInt(rawEpisode[episodeIdKey]);
    final sortOrder = AnimeInfoParse.toDouble(rawEpisode[sortOrderKey]);
    if (episodeId == null || sortOrder == null) continue;
    episodeIdsBySortOrder.putIfAbsent(sortOrder, () => episodeId);
  }
  return episodeIdsBySortOrder;
}

DbAnimeEpisodeRelation _parseAnimeEpisodeRelationBangumi(JsonData bgmAniPkgJson) {

  final anime = bgmAniPkgJson['anime'];
  if (anime is! Map) throw const FormatException('Bangumi Anime Package 缺少 anime 对象');
  final animeId = AnimeInfoParse.toPositiveInt(anime['id']);
  if (animeId == null) throw const FormatException('Bangumi Anime Package 缺少有效的 id');

  final episodeIdsBySortOrder = _parseEpisodeIdsBySortOrder(
    bgmAniPkgJson,
    episodeIdKey: 'id',
    sortOrderKey: 'sort',
    sourceName: 'Bangumi',
  );
  return DbAnimeEpisodeRelation(
    animeId: animeId,
    episodeIds: episodeIdsBySortOrder.values,
  );
}

// class _Timer {

//   final String label;

//   _Timer(this.label);

//   final Stopwatch _stopwatch = Stopwatch()..start();

//   int elapsedMilliseconds() => _stopwatch.elapsedMilliseconds;

//   void start() {
//     debugPrint('[$label] 开始计时...');
//     _stopwatch.start();
//   }

//   void printElapsed(String message) {
//     final elapsed = _stopwatch.elapsedMilliseconds;
//     debugPrint('[$label] $message, 耗时: ${elapsed}ms');
//   }

//   void stop() {
//     _stopwatch.stop();
//     debugPrint('[$label] 停止计时, 总耗时: ${_stopwatch.elapsedMilliseconds}ms');
//   }
// }