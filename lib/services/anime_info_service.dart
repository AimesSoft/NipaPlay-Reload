
// lib/services/anime_info_service.dart

import 'package:nipaplay/models/database/dandanplay_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_anime_package.dart';
import 'package:nipaplay/models/database/bangumi_episode_record.dart';
import 'package:nipaplay/models/database/dandanplay_anime_package.dart';
import 'package:nipaplay/models/database/dandanplay_episode_record.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
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

int? _toInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

DateTime? _toDateTime(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
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

int? _getBangumiTvId(Map<String, dynamic> bangumi) {
  final directId = _toPositiveInt(
    bangumi['tvId'] ??
        bangumi['subjectId'] ??
        bangumi['bgmId'] ??
        bangumi['bangumiTvId'],
  );
  return directId ?? _extractBangumiSubjectIdFromUrl(bangumi['bangumiUrl']?.toString());
}

Future<Map<double, int>> _getBangumiTvEpisodeIdsBySortOrder(
  int? bangumiTvAnimeId,
) async {
  if (bangumiTvAnimeId == null) return const <double, int>{};

  final episodes =
      await BangumiApiService.getPublicSubjectEpisodes(bangumiTvAnimeId);
  final episodeIdsBySortOrder = <double, int>{};
  for (final episode in episodes) {
    final episodeId = _toPositiveInt(episode['id']);
    final sortOrder = _toDouble(episode['sort'] ?? episode['ep']);
    if (episodeId != null && sortOrder != null) {
      episodeIdsBySortOrder.putIfAbsent(sortOrder, () => episodeId);
    }
  }
  return episodeIdsBySortOrder;
}

String? _getString(Map<String, dynamic> source, String key) {
  final value = source[key]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

String? _getInfoboxValue(
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

// ========================================================================== //
// ========================================================================== //
// ========================================================================== //

/// 获取动画信息的服务类
class AnimeInfoService {

  /// 根据 DanDanPlay AnimeID 获取 BangumiTv ID
  static Future<int?> getBangumiIdByDandanplayId(int ddpId) async {
    final details = await DandanplayService.getBangumiDetails(ddpId, useCache: false);
    final bangumi = details['bangumi'] is Map ? Map<String, dynamic>.from(details['bangumi'] as Map) : <String, dynamic>{};

    return _getBangumiTvId(bangumi);
  }

  /// 根据 Bangumi TV 条目 ID 获取弹弹play 动画 ID
  static Future<int?> getDandanplayIdByBangumiId(int bgmId) async {
    final details =
        await DandanplayService.getBangumiByBgmId(bgmId);
    if (details == null) return null;

    final bangumi = details['bangumi'] is Map
        ? Map<String, dynamic>.from(details['bangumi'] as Map)
        : <String, dynamic>{};
    return _toPositiveInt(bangumi['animeId'] ?? details['animeId']);
  }

  static Future<DbDandanplayAnimePackage?> getDandanplayAnimePackageByID(int ddpId) async {

    Future<DbDandanplayAnimeRecord?> getDanDanPlayAnimeInfoByDanDanPlayID(int animeId) async {
      // 这里直接调用 DandanplayService.getBangumiDetails, 并从返回的结果中提取动画信息
      final details = await DandanplayService.getBangumiDetails(animeId, useCache: false);

      final bangumi = details['bangumi'] is Map ? Map<String, dynamic>.from(details['bangumi'] as Map) : <String, dynamic>{};
      final animeTitle = (bangumi['animeTitle'] ?? bangumi['title'] ?? '').toString().trim();
      if (animeTitle.isEmpty) throw Exception('接口未返回有效动画标题: $details');

      return DbDandanplayAnimeRecord(
        dandanplayAnimeId: animeId,
        title: animeTitle,
        coverImageUrl: bangumi['imageUrl']?.toString(),
        description: bangumi['description']?.toString(),
      );
    }

    Future<Set<DbDandanplayEpisodeRecord>?> getDanDanPlayAnimeEpisodesByDanDanPlayID(int animeId) async {
      final details = await DandanplayService.getBangumiDetails(animeId, useCache: false);

      final bangumi = details['bangumi'] is Map ? Map<String, dynamic>.from(details['bangumi'] as Map) : <String, dynamic>{};
      final rawEpisodes = bangumi['episodes'] is List
          ? (bangumi['episodes'] as List)
          : (details['episodes'] is List ? (details['episodes'] as List) : const []);
      final bangumiTvEpisodeIdsBySortOrder =
          await _getBangumiTvEpisodeIdsBySortOrder(_getBangumiTvId(bangumi));

      final episodeRecords = <DbDandanplayEpisodeRecord>{};
      for (final raw in rawEpisodes) {
        if (raw is! Map) continue;
        final episode = Map<String, dynamic>.from(raw);
        final episodeId = _toPositiveInt(episode['episodeId']);
        if (episodeId == null) continue;
        final sortOrder = _toDouble(episode['episodeNumber']);
        episodeRecords.add(
          DbDandanplayEpisodeRecord(
            dandanplayEpisodeId: episodeId,
            animeId: animeId,
            bangumiTvId: bangumiTvEpisodeIdsBySortOrder[sortOrder],
            title: episode['episodeTitle']?.toString(),
            sortOrder: sortOrder,
          ),
        );
      }
      return episodeRecords;
    }

    final anime = await getDanDanPlayAnimeInfoByDanDanPlayID(ddpId);
    if (anime == null) return null;
    final episodes = await getDanDanPlayAnimeEpisodesByDanDanPlayID(ddpId);
    return DbDandanplayAnimePackage(anime: anime, episodes: episodes ?? <DbDandanplayEpisodeRecord>{});
  }

  static Future<DbBangumiAnimePackage?> getBangumiAnimePackageById(int bgmId) async {


    /// 根据 Bangumi TV 条目 ID 获取可持久化的动画记录。
    Future<DbBangumiAnimeRecord> getBangumiAnimeRecordById(
      int bangumiTvAnimeId,
    ) async {
      final subject = await BangumiApiService.getPublicSubject(bangumiTvAnimeId);
      final imageUrls = subject['images'] is Map
          ? Map<String, dynamic>.from(subject['images'] as Map)
          : const <String, dynamic>{};

      return DbBangumiAnimeRecord(
        bangumiAnimeId: _toPositiveInt(subject['id']) ?? bangumiTvAnimeId,
        airDate: _toDateTime(subject['date']),
        title: _getString(subject, 'name'),
        titleCn: _getString(subject, 'name_cn'),
        aliases: _getInfoboxValue(
          subject,
          (key) => key.contains('别名') || key.contains('Alias'),
        ),
        description: _getString(subject, 'summary'),
        episodeCount: _toInt(subject['eps']),
        officialSiteUrl: _getInfoboxValue(
          subject,
          (key) => key.contains('官网') || key.toLowerCase().contains('official'),
        ),
        coverImageUrl: _getString(imageUrls, 'large') ??
            _getString(imageUrls, 'common') ??
            _getString(imageUrls, 'medium'),
      );
    }

    /// 根据 Bangumi TV 条目 ID 获取可持久化的剧集记录。
    Future<Set<DbBangumiEpisodeRecord>>
        getBangumiEpisodeRecordsByAnimeId(int bangumiTvAnimeId) async {
      final episodes =
          await BangumiApiService.getPublicSubjectEpisodes(bangumiTvAnimeId);
      final records = <DbBangumiEpisodeRecord>{};
      for (final episode in episodes) {
        final episodeId = _toPositiveInt(episode['id']);
        if (episodeId == null) continue;
        records.add(
          DbBangumiEpisodeRecord(
            bangumiEpisodeId: episodeId,
            animeId: bangumiTvAnimeId,
            episodeNumber: _toInt(episode['ep']),
            sortOrder: _toDouble(episode['sort']),
            airDate: _toDateTime(episode['airdate']),
            durationSeconds: _toInt(episode['duration_seconds']),
            title: _getString(episode, 'name'),
            titleCn: _getString(episode, 'name_cn'),
            description: _getString(episode, 'desc'),
          ),
        );
      }
      return records;
    }

    final animeRecord = await getBangumiAnimeRecordById(bgmId);
    final episodeRecords = await getBangumiEpisodeRecordsByAnimeId(bgmId);
    return DbBangumiAnimePackage(anime: animeRecord, episodes: episodeRecords);
  }
}
