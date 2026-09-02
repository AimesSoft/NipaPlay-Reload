// lib/utils/anime_info_parse.dart
// 番剧信息解析相关的通用工具

import 'package:nipaplay/services/bangumi_api_service.dart';


abstract final class AnimeInfoParse {

  static double? toDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static int? toPositiveInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static int? toInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  static DateTime? toDateTime(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : DateTime.tryParse(text);
  }

  /// 从 Bangumi 条目 URL 中提取 subject id
  static int? extractBangumiSubjectIdFromUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] == 'subject' && i + 1 < segments.length) {
        return toPositiveInt(segments[i + 1]);
      }
    }
    return null;
  }

  /// 从 Dandanplay 返回的 bangumi 信息中解析 Bangumi TV ID
  static int? getBangumiTvId(Map<String, dynamic> bangumi) {
    final directId = toPositiveInt(
      bangumi['tvId'] ??
          bangumi['subjectId'] ??
          bangumi['bgmId'] ??
          bangumi['bangumiTvId'],
    );
    return directId ?? extractBangumiSubjectIdFromUrl(bangumi['bangumiUrl']?.toString());
  }

  /// 访问 Bangumi API, 得到 sortOrder -> Bangumi Episode ID 的映射
  static Future<Map<double, int>> getBangumiTvEpisodeIdsBySortOrder(
    int? bangumiTvAnimeId,
  ) async {
    if (bangumiTvAnimeId == null) return const <double, int>{};

    final episodes = await BangumiApiService.getPublicSubjectEpisodes(bangumiTvAnimeId);
    final episodeIdsBySortOrder = <double, int>{};
    for (final episode in episodes) {
      final episodeId = toPositiveInt(episode['id']);
      final sortOrder = toDouble(episode['sort'] ?? episode['ep']);
      if (episodeId != null && sortOrder != null) {
        episodeIdsBySortOrder.putIfAbsent(sortOrder, () => episodeId);
      }
    }
    return episodeIdsBySortOrder;
  }

  /// 读取字符串字段, 空字符串视为 null
  static String? getString(Map<String, dynamic> source, String key) {
    final value = source[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// 从 Bangumi subject 的 infobox 中读取第一个匹配的值
  static String? getInfoboxValue(
    Map<String, dynamic> subject,
    bool Function(String key) matches,
  ) {
    final infobox = subject['infobox'];
    if (infobox is! List) return null;

    for (final item in infobox.whereType<Map>()) {
      final key = item['key']?.toString() ?? '';
      if (!matches(key)) continue;
      final value = item['value'];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is List) {
        final values = value
            .whereType<Map>()
            .map((entry) => entry['v']?.toString().trim())
            .whereType<String>()
            .where((entry) => entry.isNotEmpty);
        final joined = values.join('; ');
        if (joined.isNotEmpty) return joined;
      }
    }
    return null;
  }
}
