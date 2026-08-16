
// lib/services/anime_info_service.dart

import 'package:nipaplay/models/database/anime_record.dart';
import 'package:nipaplay/models/database/episode_record.dart';
import 'package:nipaplay/services/dandanplay_service_io.dart';


double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

int? _toPositiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

int? _extractBangumiSubjectIdFromUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;
  for (var i = 0; i < segments.length; i++) {
    if (segments[i] == 'subject' && i + 1 < segments.length) {
      return _toPositiveInt(segments[i + 1]);
    }
  }
  return null;
}


/// 获取动画信息的服务类
class AnimeInfoService {

  static Future<DbAnimeRecord?> getAnimeInfoByDanDanPlayID(int animeId) async {
    // 这里直接调用 DandanplayService.getBangumiDetails, 并从返回的结果中提取动画信息
    final details = await DandanplayService.getBangumiDetails(animeId, useCache: false);

    final bangumi = details['bangumi'] is Map ? Map<String, dynamic>.from(details['bangumi'] as Map) : <String, dynamic>{};
    final animeTitle = (bangumi['animeTitle'] ?? bangumi['title'] ?? '').toString().trim();
    if (animeTitle.isEmpty) throw Exception('接口未返回有效动画标题: $details');

    return DbAnimeRecord(id: animeId, title: animeTitle);
  }

  static Future<Set<DbEpisodeRecord>?> getAnimeEpisodesByDanDanPlayID(int animeId) async {
    final details = await DandanplayService.getBangumiDetails(animeId, useCache: false);

    final bangumi = details['bangumi'] is Map ? Map<String, dynamic>.from(details['bangumi'] as Map) : <String, dynamic>{};
    final rawEpisodes = bangumi['episodes'] is List
        ? (bangumi['episodes'] as List)
        : (details['episodes'] is List ? (details['episodes'] as List) : const []);

    final episodeRecords = <DbEpisodeRecord>{};
    for (final raw in rawEpisodes) {
      if (raw is! Map) continue;
      final episode = Map<String, dynamic>.from(raw);
      final episodeId = _toPositiveInt(episode['episodeId']);
      if (episodeId == null) continue;
      episodeRecords.add(
        DbEpisodeRecord(
          id: episodeId,
          animeId: animeId,
          title: episode['episodeTitle']?.toString(),
          sortOrder: _toDouble(episode['episodeNumber']),
        ),
      );
    }
    return episodeRecords;
  }

  static Future<int?> getBangumiTvIDByDanDanPlayID(int animeId) async {
    final details = await DandanplayService.getBangumiDetails(animeId, useCache: false);
    final bangumi = details['bangumi'] is Map ? Map<String, dynamic>.from(details['bangumi'] as Map) : <String, dynamic>{};

    // 兼容不同返回结构: 优先取显式ID字段, 缺失时从 bangumiUrl 解析 subjectId
    final directId = _toPositiveInt(
      bangumi['tvId'] ??
          bangumi['subjectId'] ??
          bangumi['bgmId'] ??
          bangumi['bangumiTvId'],
    );
    if (directId != null) return directId;

    return _extractBangumiSubjectIdFromUrl(bangumi['bangumiUrl']?.toString());
  }
}
