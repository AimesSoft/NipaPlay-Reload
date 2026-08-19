
// lib/services/anime_info_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/database/dandanplay_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_anime_package.dart';
import 'package:nipaplay/models/database/bangumi_episode_record.dart';
import 'package:nipaplay/models/database/dandanplay_anime_package.dart';
import 'package:nipaplay/models/database/dandanplay_episode_record.dart';
import 'package:nipaplay/models/database/dandanplay_danmaku_record.dart';
import 'package:nipaplay/models/database/file_record.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/services/dandanplay_service_io.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/file_hash.dart';


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


class DandanplayFileMatchArgument {

  final String fileName;
  final String fileHash;
  final int    fileSize;

  DandanplayFileMatchArgument({
    required this.fileName,
    required this.fileHash,
    required this.fileSize,
  });
}

class DandanplayFileMatchResult {

  final int    dandanplayAnimeId;
  final int    dandanplayEpisodeId;
  final double danmakuOffset;

  DandanplayFileMatchResult({
    required this.dandanplayAnimeId,
    required this.dandanplayEpisodeId,
    required this.danmakuOffset,
  });
}

class RefreshDandanplayFileDanmakuResult {

  final DandanplayFileMatchResult? matchResult; // 是否通过 API 自动匹配到单集
  final bool refreshDatabaseSuccess; // 是否成功刷新数据库

  RefreshDandanplayFileDanmakuResult({
    required this.matchResult,
    required this.refreshDatabaseSuccess,
  });
}

/// 获取动画信息的服务类
class AnimeInfoService {

  /// 访问 Dandanplay API: /api/v2/match
  /// 获取文件匹配的 Episode ID 和对应 Anime ID
  static Future<DandanplayFileMatchResult?> getDandanplayFileMatch(DandanplayFileMatchArgument arg) async {
    const apiPath = '/api/v2/match';
    final appSecret = await DandanplayService.getAppSecret();
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    final response = await http.post(
      Uri.parse('${await DandanplayService.getApiBaseUrl()}$apiPath'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': DandanplayService.userAgent,
        'X-AppId': DandanplayService.appId,
        'X-Signature': DandanplayService.generateSignature(
          DandanplayService.appId,
          timestamp,
          apiPath,
          appSecret,
        ),
        'X-Timestamp': '$timestamp',
      },
      body: jsonEncode(<String, dynamic>{
        'fileName': arg.fileName,
        'fileHash': arg.fileHash,
        'fileSize': arg.fileSize,
        'matchMode': 'hashAndFileName',
      }),
    );
    if (response.statusCode != 200) {
      final error = response.headers['x-error-message'] ?? response.body;
      throw Exception('弹弹play 文件匹配失败 (${response.statusCode}): $error');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('弹弹play 文件匹配响应格式无效');
    }
    final matches = decoded['matches'];
    if (matches is! List) return null;

    for (final rawMatch in matches) {
      if (rawMatch is! Map) continue;
      final match = Map<String, dynamic>.from(rawMatch);
      final animeId = _toPositiveInt(match['animeId']);
      final episodeId = _toPositiveInt(match['episodeId']);
      if (animeId != null && episodeId != null) {
        return DandanplayFileMatchResult(
          dandanplayAnimeId: animeId,
          dandanplayEpisodeId: episodeId,
          danmakuOffset: match['shift'].toDouble(),
        );
      }
    }
    return null;
  }

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
      if (animeTitle.isEmpty) return null;

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
            dandanplayAnimeId: animeId,
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
    final bangumiAnimeId = await getBangumiIdByDandanplayId(ddpId);
    return DbDandanplayAnimePackage(
      anime: DbDandanplayAnimeRecord(
        dandanplayAnimeId: anime.dandanplayAnimeId,
        bangumiAnimeId: bangumiAnimeId,
        title: anime.title,
        coverImageUrl: anime.coverImageUrl,
        description: anime.description,
      ),
      episodes: episodes ?? <DbDandanplayEpisodeRecord>{},
    );
  }

  static Future<DbBangumiAnimePackage?> getBangumiAnimePackageById(int bgmId) async {

    /// 根据 Bangumi TV 条目 ID 获取可持久化的动画记录
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

    /// 根据 Bangumi TV 条目 ID 获取可持久化的剧集记录
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
            bangumiAnimeId: bangumiTvAnimeId,
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

  static Future<String?> getDandanplayDanmakuJsonByEpisodeId(int ddpEpiId) async {
    if (ddpEpiId <= 0) {
      throw ArgumentError.value(ddpEpiId, 'ddpEpiId', '必须为正整数');
    }

    final apiPath = '/api/v2/comment/$ddpEpiId';
    final appSecret = await DandanplayService.getAppSecret();
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    final response = await http.get(
      Uri.parse(
        '${await DandanplayService.getApiBaseUrl()}$apiPath?withRelated=true',
      ),
      headers: <String, String>{
        'Accept': 'application/json',
        'User-Agent': DandanplayService.userAgent,
        'X-AppId': DandanplayService.appId,
        'X-Signature': DandanplayService.generateSignature(
          DandanplayService.appId,
          timestamp,
          apiPath,
          appSecret,
        ),
        'X-Timestamp': '$timestamp',
      },
    );
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['comments'] is! List) return null;
    return response.body;
  }


  // ======================================================================== //
  // ======================================================================== //
  // ======================================================================== //

  static final String _label =  color('[Anime Info Service]', ColorCode.boldMagenta);
  static void _printLine(String message) => debugPrint('$_label ${color(message, ColorCode.gray)}');
  static String _val(Object str) => color(str.toString(), ColorCode.boldWhite);

  static final String _bgmLabel = color('Bangumi', ColorCode.pink);
  static final String _ddpLabel = color('Dandanplay', ColorCode.cyan);


  /// 1. 根据 Dandanplay Anime ID 访问 API 获取对应的 Anime 及其所有 Episode 信息 (Anime Package)
  /// 2. 将获取到的 Anime Package 插入更新数据库
  static Future<void> refreshDandanplayAnimePackageById(int ddpAniId) async {

    final idStr = _val(ddpAniId);
    _printLine('开始刷新 $_ddpLabel Anime Package: $idStr');

    final package = await getDandanplayAnimePackageByID(ddpAniId);
    if (package == null) {
      final message = color('未获取到对应 ID 的 Dandanplay Anime Package: $idStr', ColorCode.red);
      _printLine(message);
      return;
    }
    _printLine('获取到 $_ddpLabel Anime Package: $idStr');
    debugPrint(package.toPrintString(indent: '$_label ', enableColor: true));

    _printLine('');
    _printLine('开始将 $_ddpLabel Anime Package 写入数据库: $idStr');
    await DatabaseService.upsertDanDanPlayAnimePackage(package);

    _printLine('');
    _printLine('完成刷新 $_ddpLabel Anime Package: $idStr');
  }

  /// 1. 根据 Bangumi Anime ID 访问 API 获取对应的 Anime 及其所有 Episode 信息
  /// 2. 将获取到的 Anime Package 插入更新数据库
  static Future<void> refreshBangumiAnimePackageById(int bangumiAnimeId) async {
    final idStr = _val(bangumiAnimeId);
    _printLine('开始刷新 $_bgmLabel Anime Package: $idStr');

    final package = await getBangumiAnimePackageById(bangumiAnimeId);
    if (package == null) {
      final message = color(
        '未获取到对应 ID 的 $_bgmLabel Anime Package: $idStr',
        ColorCode.red,
      );
      _printLine(message);
      return;
    }
    _printLine('获取到 $_bgmLabel Anime Package: $idStr');
    debugPrint(package.toPrintString(indent: '$_label ', enableColor: true));

    _printLine('');
    _printLine('开始将 $_bgmLabel Anime Package 写入数据库: $idStr');
    await DatabaseService.upsertBangumiAnimePackage(package);

    _printLine('');
    _printLine('完成刷新 $_bgmLabel Anime Package: $idStr');
  }

  /// 1. 根据 ddpEpiId 查询 dandanplay_episode 表
  /// 2. 如果没有找到对应的记录, 则打印提示信息并直接返回
  /// 3. 调用 API 获取弹幕 JSON
  /// 4. 将获取到的弹幕 JSON 插入更新到 dandanplay_danmaku 表
  static Future<void> refreshDandanplayEpisodeDanmakuById(int ddpEpiId) async {

    final idStr = _val(ddpEpiId);
    _printLine('开始刷新 Dandanplay Episode Danmaku: $idStr');

    // 保证数据库中存在对应的 dandanplay_episode 记录
    final episode = await DatabaseService.getDandanplayEpisodeRecordById(ddpEpiId);
    if (episode == null) {
      _printLine(color('数据库中未找到 Dandanplay Episode: $idStr', ColorCode.red));
      return;
    }

    // 调用 API 获取弹幕 JSON
    final danmakuJson = await getDandanplayDanmakuJsonByEpisodeId(ddpEpiId);
    if (danmakuJson == null) {
      _printLine(color('未获取到弹幕 JSON: $idStr', ColorCode.red));
      return;
    }

    // 将获取到的弹幕 JSON 插入更新到 dandanplay_danmaku 表
    _printLine('开始将 Dandanplay Episode Danmaku 写入数据库: $idStr');
    await DatabaseService.upsertDandanplayDanmaku(
      DbDandanplayDanmakuRecord(
        dandanplayEpisodeId: episode.dandanplayEpisodeId,
        danmakuJson: danmakuJson,
      ),
    );

    _printLine('完成刷新 Dandanplay Episode Danmaku: $idStr');
  }

  /// 1. 根据文件路径得到 FileRecord
  /// 2. 将 FileRecord 插入更新到 file 表
  /// 3. 根据文件信息访问 /api/v2/match API
  /// 4. 如果 API 匹配失败, 则打印提示信息并直接返回:
  ///     - RefreshDandanplayFileDanmakuResult.matchResult 为 null
  ///     - RefreshDandanplayFileDanmakuResult.refreshDatabaseSuccess 为 false
  /// 5. 如果 API 匹配成功:
  ///     1. 将匹配结果整理成 DandanplayFileMatchResult
  ///     2. 根据 DandanplayFileMatchResult.dandanplayEpisodeId 查询 dandanplay_episode 表
  ///     3. 如果没有找到对应的记录, 则打印提示信息并直接返回:
  ///         - RefreshDandanplayFileDanmakuResult.matchResult 为 DandanplayFileMatchResult
  ///         - RefreshDandanplayFileDanmakuResult.refreshDatabaseSuccess 为 false
  ///     4. 如果数据库有对应的记录, 则: 
  ///         1. 更新 file 表对应记录的 episode_id 字段为匹配到的 dandanplayEpisodeId 对应的 episode_id
  ///         2. 插入 file_danmaku 表
  ///         3. 返回:
  ///            - RefreshDandanplayFileDanmakuResult.matchResult 为 DandanplayFileMatchResult
  ///            - RefreshDandanplayFileDanmakuResult.refreshDatabaseSuccess 为 true
  static Future<RefreshDandanplayFileDanmakuResult> refreshDandanplayFileDanmakuByFilePath(String filePath) async {

    final file = File(filePath);
    if (!file.existsSync()) {
      _printLine(color('文件不存在: ${_val(filePath)}', ColorCode.red));
      return RefreshDandanplayFileDanmakuResult(matchResult: null, refreshDatabaseSuccess: false);
    }
    final fileHash = await computeFileHeadMd5(file.path);
    final fileRecord = DbFileRecord(
      fileHash: fileHash,
      fileName: file.uri.pathSegments.last,
      fileSize: await file.length(),
    );

    await DatabaseService.upsertMediaFile(fileRecord);

    final matchResult = await getDandanplayFileMatch(
      DandanplayFileMatchArgument(
        fileName: fileRecord.fileName!,
        fileHash: fileHash,
        fileSize: fileRecord.fileSize!,
      ),
    );
    if (matchResult == null) {
      _printLine(color('文件未匹配到 Dandanplay 剧集: ${_val(fileHash)}', ColorCode.red));
      return RefreshDandanplayFileDanmakuResult(matchResult: null, refreshDatabaseSuccess: false);
    }

    final episode = await DatabaseService.getDandanplayEpisodeRecordById(matchResult.dandanplayEpisodeId);
    if (episode == null) {
      _printLine(color('数据库中未找到 Dandanplay Episode: ${_val(matchResult.dandanplayEpisodeId)}', ColorCode.red));
      return RefreshDandanplayFileDanmakuResult(matchResult: matchResult, refreshDatabaseSuccess: false);
    }

    await DatabaseService.linkEpisodeDandanplayFile(episode.dandanplayEpisodeId, fileHash);
    await DatabaseService.upsertDandanplayFileDanmaku(fileHash, episode.dandanplayEpisodeId, matchResult.danmakuOffset);
    return RefreshDandanplayFileDanmakuResult(matchResult: matchResult, refreshDatabaseSuccess: true);
  }


  /// 关联 Dandanplay 和 Bangumi 番剧
  /// 1. 查找数据库, 确保 ddpAniId 和 bgmAniId 对应的记录都存在
  /// 2. 如果任意一个不存在, 则立刻访问对应 API 获取对应的 Anime Package 并插入更新数据库
  /// 3. 根据两个 pkg 的 episode 排序信息, 相互匹配, 确立对应关系
  /// 4. 更新 dandanplay_anime 和 bangumi_anime 表, 确保其 anime_id 字段相同
  /// 5. 更新 dandanplay_episode 和 bangumi_episode 表, 确保被识别为相同剧集的记录其 episode_id 字段相同
  static Future<void> linkDandanplayAnimeWithBangumiAnime(int ddpAniId, int bgmAniId) async {

    var dandanplayAnime = await DatabaseService.getDandanplayAnimeRecordById(ddpAniId);
    if (dandanplayAnime == null) {
      await refreshDandanplayAnimePackageById(ddpAniId);
      dandanplayAnime = await DatabaseService.getDandanplayAnimeRecordById(ddpAniId);
    }
    var bangumiAnime = await DatabaseService.getBangumiAnimeRecordById(bgmAniId);
    if (bangumiAnime == null) {
      await refreshBangumiAnimePackageById(bgmAniId);
      bangumiAnime = await DatabaseService.getBangumiAnimeRecordById(bgmAniId);
    }
    if (dandanplayAnime == null || bangumiAnime == null) {
      throw StateError('无法获取需要关联的 Dandanplay 或 Bangumi 动画记录');
    }

    await DatabaseService.linkAnimeRecordDandanplayBangumi(ddpAniId, bgmAniId);

    final dandanplayEpisodes = await DatabaseService.getDandanplayEpisodeRecordsById(ddpAniId);
    final bangumiEpisodes = await DatabaseService.getBangumiEpisodeRecordsById(bgmAniId);

    // 以剧集排序信息作为匹配依据
    final bangumiEpisodeIdBySortOrder = <double, int>{};
    for (final episode in bangumiEpisodes) {
      final sortOrder = episode.sortOrder;
      if (sortOrder == null) continue;
      bangumiEpisodeIdBySortOrder.putIfAbsent(sortOrder, () => episode.bangumiEpisodeId);
    }

    var linkedCount = 0;
    for (final episode in dandanplayEpisodes) {
      final sortOrder = episode.sortOrder;
      if (sortOrder == null) continue;
      final bangumiEpisodeId = bangumiEpisodeIdBySortOrder[sortOrder];
      if (bangumiEpisodeId == null) continue;

      await DatabaseService.linkEpisodeRecordDandanplayBangumi(
        episode.dandanplayEpisodeId,
        bangumiEpisodeId,
      );
      linkedCount++;
    }

    _printLine(
      '已关联 Dandanplay Anime ${_val(ddpAniId)} 与 Bangumi Anime ${_val(bgmAniId)}, '
      '匹配剧集数: ${_val(linkedCount)}',
    );
  }
}
