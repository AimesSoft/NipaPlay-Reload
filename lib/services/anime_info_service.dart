
// lib/services/anime_info_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/database/anime_episode_relation.dart';
import 'package:nipaplay/models/database/asset_record.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/services/dandanplay_service_io.dart';
import 'package:nipaplay/utils/anime_info_parse.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/dandanplay_auth.dart';
import 'package:nipaplay/utils/file_hash.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/utils/storage_service.dart';


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

typedef _AnimeEpisodeDebugTitles = ({
  Map<int, String> dandanplayAnime,
  Map<int, String> bangumiAnime,
  Map<int, String> dandanplayEpisode,
  Map<int, String> bangumiEpisode,
});


class DandanplayDanmakuResult {

  final String danmakuJson;
  final double dandanplayOffset;
  final double userOffset;

  DandanplayDanmakuResult({
    required this.danmakuJson,
    required this.dandanplayOffset,
    required this.userOffset,
  });
}

/// 获取动画信息的服务类
class AnimeInfoService {

  static final String _label =  color('[Anime Info Service]', ColorCode.boldMagenta);
  static void _printLine(String message) => debugPrint('$_label ${color(message, ColorCode.gray)}');
  static String _val(Object str) => color(str.toString(), ColorCode.boldWhite);

  static final String _bgmLabel = color('Bangumi', ColorCode.pink);
  static final String _ddpLabel = color('Dandanplay', ColorCode.cyan);

  static Future<String> debugAnimeEpisodeRelations({String? cacheRootPath}) async {
    final resolvedCacheRootPath = cacheRootPath ?? (await StorageService.getCacheDirectory()).path;
    final titles = await _loadAnimeEpisodeDebugTitles(resolvedCacheRootPath);
    return DatabaseService.buildAnimeEpisodeRelationReport(
      dandanplayAnimeTitles: titles.dandanplayAnime,
      bangumiAnimeTitles: titles.bangumiAnime,
      dandanplayEpisodeTitles: titles.dandanplayEpisode,
      bangumiEpisodeTitles: titles.bangumiEpisode,
    );
  }


  /// - 根据文件路径得到 FileRecord
  /// - 将 FileRecord 插入更新到 file 表
  /// - 如果 priorityLinkOpt == null, 查找 file_external 表, 获取 linkOptions (默认值所有 bit 为 1)
  /// - 判断是否需要匹配 Dandanplay 数据, 如果不要, 则直接打印提示信息并返回
  /// - 如果要, 根据文件信息访问 /api/v2/match API
  /// - 如果 API 匹配失败, 则打印提示信息并直接返回
  /// - 如果 API 匹配成功, 根据匹配到的 Dandanplay Episode ID 查询 dandanplay_episode 表
  /// - 如果没有找到对应的记录, 则刷新 Dandanplay Anime 缓存和数据库关系
  /// - 确保数据库内有对应的 dandanplay_episode 记录后, 执行 linkEpisodeDandanplayFile
  /// 
  /// - 根据 linkOptions 判断是否需要匹配 Bangumi 数据, 如果不要, 则直接打印提示信息并返回
  /// - 如果要, 根据匹配到的 ddpEpiId 查询数据库表, 看看有没有对应的 bangumiEpisodeId
  /// - 如果有, 打印提示信息并返回
  /// - 如果没有, 根据 ddpEpiId 查询 dandanplay_anime 表, 看看有没有对应的 bangumiAnimeId
  /// - 如果没有, 打印提示信息并返回
  /// - 如果有, 根据 bangumiAnimeId 执行 refreshBangumiAnimePackageById
  /// - 最后再次查询数据库确认
  /// 
  /// 整个过程随时打印详细执行信息, 方便调试和查看执行结果
  static Future<void> identifyFileAndSyncDatabase(String filePath, {int? priorityLinkOpt}) async {

    _printLine('开始刷新文件关联信息: ${_val(filePath)}');

    // 计算文件哈希, 写入 file 表
    final file = File(filePath);
    if (!file.existsSync()) {
      _printLine(color('文件不存在: ${_val(filePath)}', ColorCode.red));
      return;
    }
    final fileHash = await computeFileHeadMd5(file.path);
    final assetHash = decodeHex(fileHash, expectedBytes: 16);
    final fileSize = await file.length();
    final fileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : file.path.split('/').last;
    final extensionIndex = fileName.lastIndexOf('.');
    final codec = extensionIndex >= 0 && extensionIndex < fileName.length - 1
        ? fileName.substring(extensionIndex + 1).toLowerCase()
        : null;
    await DatabaseService.upsertAssetRecord(
      DbAssetRecord(
        hashPre16MiBMd5: assetHash,
        size: fileSize,
        codec: codec,
      ),
    );
    _printLine('文件记录已写入数据库: ${_val(fileHash)}');

    // 决定本次使用的关联选项
    final assetEpisodeInfo =
        await DatabaseService.getAssetEpisodeInfo(assetHash);
    final linkOptions = priorityLinkOpt ??
        assetEpisodeInfo?.linkOptions ??
        DatabaseService.defaultLinkOptions;
    _printLine('本次使用的关联选项: ${_val(linkOptions)}');


    // ------------------------------ Dandanplay ------------------------------ //

    if (linkOptions & DatabaseService.linkDandanplay == 0) {
      _printLine(color('关联选项未开启 Dandanplay 匹配, 结束刷新', ColorCode.yellow));
      return;
    }

    // 根据文件信息访问 /api/v2/match API
    final matchArgument = DandanplayFileMatchArgument(fileHash: fileHash, fileSize: fileSize, fileName: fileName);
    final matchResult = await requestDandanplayFileMatch(matchArgument);
    if (matchResult == null) {
      _printLine(color('文件未匹配到 Dandanplay 剧集: ${_val(fileHash)}', ColorCode.red));
      return;
    }

    final ddpAniId = matchResult.dandanplayAnimeId;
    final ddpEpiId = matchResult.dandanplayEpisodeId;
    _printLine('匹配到 Dandanplay Anime: ${_val(ddpAniId)}, Episode: ${_val(ddpEpiId)}');

    // 确保数据库中存在对应的 dandanplay_episode 记录
    if (!await DatabaseService.hasEpisode(
      DbAnimeEpisodeRelationType.dandanplay,
      ddpEpiId,
    )) {
      _printLine('数据库中未找到 Dandanplay Episode: ${_val(ddpEpiId)}, 开始刷新 Anime Package');
      await refreshDandanplayAnimeCacheJson(ddpAniId);
      await refreshDandanplayAnimeRelationByCache(ddpAniId);
      if (!await DatabaseService.hasEpisode(
        DbAnimeEpisodeRelationType.dandanplay,
        ddpEpiId,
      )) {
        _printLine(color('刷新后仍未找到 Dandanplay Episode: ${_val(ddpEpiId)}', ColorCode.red));
        return;
      }
    }

    // 将文件关联到 Dandanplay Episode, 并设置弹幕偏移量
    await DatabaseService.linkVideoAssetToEpisode(assetHash, ddpEpiId);
    await DatabaseService.setAssetDanmakuOffsets(assetHash, dandanplay: matchResult.danmakuOffset);
    _printLine('文件已关联 Dandanplay Episode: ${_val(ddpEpiId)}, 弹幕偏移量: ${_val(matchResult.danmakuOffset)}');


    // -------------------------------- Bangumi ------------------------------- //

    if (linkOptions & DatabaseService.linkBangumi == 0) {
      _printLine(color('关联选项未开启 Bangumi 匹配, 结束刷新', ColorCode.yellow));
      return;
    }

    final linkedCommonEpiId = await DatabaseService.getCommonEpisodeId(
      DbAnimeEpisodeRelationType.dandanplay,
      ddpEpiId,
    );
    final linkedBgmEpiId = linkedCommonEpiId == null
        ? null
        : await DatabaseService.getSourceEpisodeId(
            DbAnimeEpisodeRelationType.bangumi,
            linkedCommonEpiId,
          );
    if (linkedBgmEpiId != null) {
      _printLine('已存在关联的 Bangumi Episode: ${_val(linkedBgmEpiId)}, 结束刷新');
      return;
    }

    final generalAnimeId = await DatabaseService.getCommonAnimeId(
      DbAnimeEpisodeRelationType.dandanplay,
      ddpAniId,
    );
    if (generalAnimeId == null) {
      _printLine(color('Dandanplay Anime ${_val(ddpAniId)} 没有共通 Anime ID', ColorCode.red));
      return;
    }
    _printLine('开始关联共通 Anime: ${_val(generalAnimeId)}');
    await linkDandanplayBangumiAnime(generalAnimeId);

    // 再次查询确认关联结果
    final refreshedCommonEpiId = await DatabaseService.getCommonEpisodeId(
      DbAnimeEpisodeRelationType.dandanplay,
      ddpEpiId,
    );
    final refreshedBgmEpiId = refreshedCommonEpiId == null
        ? null
        : await DatabaseService.getSourceEpisodeId(
            DbAnimeEpisodeRelationType.bangumi,
            refreshedCommonEpiId,
          );
    if (refreshedBgmEpiId == null) {
      _printLine(color('关联后仍未找到对应的 Bangumi Episode: ${_val(ddpEpiId)}', ColorCode.red));
      return;
    }
    _printLine('完成刷新, 关联的 Bangumi Episode: ${_val(refreshedBgmEpiId)}');
  }

  /// 1. 根据 Dandanplay Episode ID 访问 Dandanplay API 获取对应的弹幕 JSON 字符串, 如果失败, 则打印提示信息并返回
  /// 2. 将弹幕 JSON 字符串写入 cache/danmaku/{ddpEpiId}.json
  static Future<void> refreshDandanplayDanmakuCacheByEpisodeId(int ddpEpiId) async {

    String danmakuJson;
    try {
      danmakuJson = await _requestDandanplayDanmakuJson(ddpEpiId);
    } catch (error) {
      _printLine(color('获取 Dandanplay Episode ${_val(ddpEpiId)} 弹幕失败: $error', ColorCode.red));
      return;
    }

    final cacheRoot = await StorageService.getCacheDirectory();
    final cacheDirectory = Directory('${cacheRoot.path}/danmaku/dandanplay');
    await cacheDirectory.create(recursive: true);
    final cacheFile = File('${cacheDirectory.path}/$ddpEpiId.json');
    await cacheFile.writeAsString(danmakuJson);
    _printLine(
      '已缓存 Dandanplay Episode ${_val(ddpEpiId)} 弹幕: '
      '${_val(cacheFile.path)}',
    );
  }


  /// 1. 根据 Dandanplay Anime ID 访问 API 获取对应的 Anime 及其所有 Episode 信息
  /// 2. 将动画及其所有剧集整理成一个 JSON 对象
  /// 3. 将该 JSON 对象覆盖写入 `<应用数据根目录>/cache/dandanplay/{ddpAniId}.json`
  static Future<void> refreshDandanplayAnimeCacheJson(int ddpAniId) async {

    final idStr = _val(ddpAniId);
    _printLine('开始刷新 $_ddpLabel Anime Package: $idStr');

    // 获取原始请求
    final packageJson = await _getDandanplayAnimePackageById(ddpAniId);
    if (packageJson == null) {
      final message = color('未获取到对应 ID 的 Dandanplay Anime Package: $idStr', ColorCode.red);
      _printLine(message);
      return;
    }

    // 将 JSON 缓存到本地
    final cacheDirectory = Directory('${(await StorageService.getCacheDirectory()).path}/dandanplay');
    await cacheDirectory.create(recursive: true);
    final cacheFile = File('${cacheDirectory.path}/$ddpAniId.json');
    await cacheFile.writeAsString(const JsonEncoder.withIndent('  ').convert(packageJson));
    _printLine('已缓存 $_ddpLabel Anime Package: ${_val(cacheFile.path)}');
  }

  /// 1. 查看缓存文件是否存在, 如果不存在, 则打印提示信息并返回
  /// 2. 读取缓存文件, 解析 JSON, 提取 Anime ID 和 Episode ID 的对应关系
  /// 3. 将对应关系插入更新数据库
  static Future<void> refreshDandanplayAnimeRelationByCache(int ddpAniId) async {
    final cacheRoot = await StorageService.getCacheDirectory();
    final cacheFile = File('${cacheRoot.path}/dandanplay/$ddpAniId.json');
    if (!await cacheFile.exists()) {
      _printLine(
        color(
          '未找到 Dandanplay Anime ${_val(ddpAniId)} 缓存: '
          '${_val(cacheFile.path)}',
          ColorCode.yellow,
        ),
      );
      return;
    }

    final packageJson = _decodeAnimePackageCache(
      await cacheFile.readAsString(),
      'Dandanplay',
    );
    final relation = _parseAnimeEpisodeRelationDandanplay(packageJson);
    if (relation.animeId != ddpAniId) {
      throw FormatException(
        'Dandanplay Anime 缓存 ID 不一致: '
        '文件名=$ddpAniId, 内容=${relation.animeId}',
      );
    }

    await DatabaseService.upsertAnimeEpisodeRelation(
      relation,
      DbAnimeEpisodeRelationType.dandanplay,
    );
    _printLine(
      '已从缓存更新 Dandanplay Anime ${_val(ddpAniId)} 关系, '
      'Episode 数量: ${_val(relation.episodeIds.length)}',
    );
  }

  /// 1. 根据 Bangumi Anime ID 访问 API 获取对应的 Anime 及其所有 Episode 信息
  /// 2. 将动画及其所有剧集整理成一个 JSON 对象
  /// 3. 将该 JSON 对象覆盖写入 `<应用数据根目录>/cache/bangumi/{bangumiAnimeId}.json`
  static Future<void> refreshBangumiAnimeCacheJson(int bangumiAnimeId) async {

    final idStr = _val(bangumiAnimeId);
    _printLine('开始刷新 $_bgmLabel Anime Package: $idStr');

    final packageJson = await _getBangumiAnimePackageById(bangumiAnimeId);

    final cacheDirectory = Directory(
      '${(await StorageService.getCacheDirectory()).path}/bangumi',
    );
    await cacheDirectory.create(recursive: true);
    final cacheFile = File('${cacheDirectory.path}/$bangumiAnimeId.json');
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(packageJson),
    );
    _printLine('已缓存 $_bgmLabel Anime Package: ${_val(cacheFile.path)}');
  }

  /// 1. 查看缓存文件是否存在, 如果不存在, 则打印提示信息并返回
  /// 2. 读取缓存文件, 解析 JSON, 提取 Anime ID 和 Episode ID 的对应关系
  /// 3. 将对应关系插入更新数据库
  static Future<void> refreshBangumiAnimeRelationByCache(int bangumiAnimeId) async {

    final cacheRoot = await StorageService.getCacheDirectory();
    final cacheFile = File('${cacheRoot.path}/bangumi/$bangumiAnimeId.json');
    if (!await cacheFile.exists()) {
      _printLine(color('未找到 Bangumi Anime ${_val(bangumiAnimeId)} 缓存: ${_val(cacheFile.path)}', ColorCode.yellow));
      return;
    }

    final packageJson = _decodeAnimePackageCache(
      await cacheFile.readAsString(),
      'Bangumi',
    );
    final relation = _parseAnimeEpisodeRelationBangumi(packageJson);
    if (relation.animeId != bangumiAnimeId) {
      throw FormatException(
        'Bangumi Anime 缓存 ID 不一致: '
        '文件名=$bangumiAnimeId, 内容=${relation.animeId}',
      );
    }

    await DatabaseService.upsertAnimeEpisodeRelation(
      relation,
      DbAnimeEpisodeRelationType.bangumi,
    );
    _printLine(
      '已从缓存更新 Bangumi Anime ${_val(bangumiAnimeId)} 关系, '
      'Episode 数量: ${_val(relation.episodeIds.length)}',
    );
  }

  /// 关联 Dandanplay 和 Bangumi 番剧
  /// 1. 根据共通 Anime ID 查询 Dandanplay 与 Bangumi Anime ID
  /// 2. 任意一方不存在时打印提示并返回
  /// 3. 确保两侧缓存存在, 抽取 Episode 排序信息并建立对应关系
  /// 4. 匹配剧集使用两方较小的共通 Episode ID
  static Future<void> linkDandanplayBangumiAnime(int generalAnimeId) async {

    final ddpAniId = await DatabaseService.getSourceAnimeId(DbAnimeEpisodeRelationType.dandanplay, generalAnimeId);
    final bgmAniId = await DatabaseService.getSourceAnimeId(DbAnimeEpisodeRelationType.bangumi, generalAnimeId);
    if (ddpAniId == null || bgmAniId == null) {
      final missingSources = <String>[
        if (ddpAniId == null) 'Dandanplay',
        if (bgmAniId == null) 'Bangumi',
      ];
      _printLine(
        color(
          '共通 Anime ${_val(generalAnimeId)} 缺少 '
          '${missingSources.join(' / ')} 记录, 终止关联',
          ColorCode.yellow,
        ),
      );
      return;
    }

    final cacheRoot = await StorageService.getCacheDirectory();
    final dandanplayCacheFile = File('${cacheRoot.path}/dandanplay/$ddpAniId.json');
    final bangumiCacheFile = File('${cacheRoot.path}/bangumi/$bgmAniId.json');

    final missingCacheFiles = <File>[
      if (!await dandanplayCacheFile.exists()) dandanplayCacheFile,
      if (!await bangumiCacheFile.exists()) bangumiCacheFile,
    ];
    if (missingCacheFiles.isNotEmpty) {
      _printLine(
        color(
          '缺少 Anime Package 缓存, 终止关联: '
          '${missingCacheFiles.map((file) => file.path).join(', ')}',
          ColorCode.yellow,
        ),
      );
      return;
    }

    final dandanplayPackageJson = _decodeAnimePackageCache(
      await dandanplayCacheFile.readAsString(),
      'Dandanplay',
    );
    final bangumiPackageJson = _decodeAnimePackageCache(
      await bangumiCacheFile.readAsString(),
      'Bangumi',
    );
    final dandanplayPackage =_parseAnimeEpisodeRelationDandanplay(dandanplayPackageJson);
    final bangumiPackage = _parseAnimeEpisodeRelationBangumi(bangumiPackageJson);
    final episodeMatches = _getDandanplayBangumiEpisodeMatch(dandanplayPackageJson, bangumiPackageJson);

    await DatabaseService.upsertAnimeEpisodeRelation(
      dandanplayPackage,
      DbAnimeEpisodeRelationType.dandanplay,
    );
    await DatabaseService.upsertAnimeEpisodeRelation(
      bangumiPackage,
      DbAnimeEpisodeRelationType.bangumi,
    );

    var linkedCount = 0;
    for (final (dandanplayEpisodeId, bangumiEpisodeId) in episodeMatches) {
      if (dandanplayEpisodeId == null || bangumiEpisodeId == null) continue;

      final dandanplayCommonEpisodeId =
          await DatabaseService.getCommonEpisodeId(
        DbAnimeEpisodeRelationType.dandanplay,
        dandanplayEpisodeId,
      );
      final bangumiCommonEpisodeId =
          await DatabaseService.getCommonEpisodeId(
        DbAnimeEpisodeRelationType.bangumi,
        bangumiEpisodeId,
      );
      if (dandanplayCommonEpisodeId == null ||
          bangumiCommonEpisodeId == null) {
        throw StateError(
          '数据库中缺少待关联的 Episode 记录: '
          'Dandanplay=$dandanplayEpisodeId, Bangumi=$bangumiEpisodeId',
        );
      }
      final commonEpisodeId =
          dandanplayCommonEpisodeId < bangumiCommonEpisodeId
              ? dandanplayCommonEpisodeId
              : bangumiCommonEpisodeId;

      await DatabaseService.linkToEpisode(
        DbAnimeEpisodeRelationType.dandanplay,
        dandanplayEpisodeId,
        commonEpisodeId,
      );
      await DatabaseService.linkToEpisode(
        DbAnimeEpisodeRelationType.bangumi,
        bangumiEpisodeId,
        commonEpisodeId,
      );
      linkedCount++;
    }

    _printLine(
      '已关联 Dandanplay Anime ${_val(ddpAniId)} 与 Bangumi Anime ${_val(bgmAniId)}, '
      '共通 Anime ID: ${_val(generalAnimeId)}, 匹配剧集数: ${_val(linkedCount)}',
    );
  }

  /// 1. 查找 asset 表, 获取对应通用 Episode ID, 如果没有, 则打印提示信息并返回 null
  /// 2. 查找 dandanplay_episode 表, 获取对应的 Dandanplay Episode ID 和弹幕相关配置, 如果没有, 则打印提示信息并返回 null
  /// 3. 根据 Dandanplay Episode ID 查找 cache/danmaku/{ddpEpiId}.json, 如果没有, 则打印提示信息并返回 null
  /// 4. 返回 DandanplayDanmakuResult 对象, 包含弹幕 JSON 字符串和弹幕配置
  static Future<DandanplayDanmakuResult?> getDandanplayDanmakuByAssetHash(Uint8List assetHash) async {

    final commonEpisodeId = await DatabaseService.getCommonEpisodeIdByAssetHash(assetHash);
    if (commonEpisodeId == null) {
      _printLine(color('视频资产没有关联共通 Episode', ColorCode.yellow));
      return null;
    }

    final ddpEpiId = await DatabaseService.getSourceEpisodeId(DbAnimeEpisodeRelationType.dandanplay, commonEpisodeId);
    if (ddpEpiId == null) {
      _printLine(color('共通 Episode ${_val(commonEpisodeId)} 没有 Dandanplay 记录', ColorCode.yellow));
      return null;
    }

    final assetEpisodeInfo =
        await DatabaseService.getAssetEpisodeInfo(assetHash);
    final dandanplayOffset =
        assetEpisodeInfo?.dandanplayDanmakuOffset ?? 0.0;
    final userOffset = assetEpisodeInfo?.userDanmakuOffset ?? 0.0;

    final cacheRoot = await StorageService.getCacheDirectory();
    final cacheFile = File('${cacheRoot.path}/danmaku/$ddpEpiId.json');
    if (!await cacheFile.exists()) {
      _printLine(color('未找到 Dandanplay Episode ${_val(ddpEpiId)} 弹幕缓存', ColorCode.yellow));
      return null;
    }

    return DandanplayDanmakuResult(
      danmakuJson: await cacheFile.readAsString(),
      dandanplayOffset: dandanplayOffset,
      userOffset: userOffset,
    );
  }


  // ======================================================================== //

  /// 访问 Dandanplay API: /api/v2/match
  /// 获取文件匹配的 Episode ID 和对应 Anime ID
  static Future<DandanplayFileMatchResult?> requestDandanplayFileMatch(DandanplayFileMatchArgument arg) async {

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
      final animeId = AnimeInfoParse.toPositiveInt(match['animeId']);
      final episodeId = AnimeInfoParse.toPositiveInt(match['episodeId']);
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
  static Future<int?> requestBangumiIdByDandanplayId(int ddpId) async {
    final details = await DandanplayService.getBangumiDetails(ddpId, useCache: false);
    final bangumi = details['bangumi'] is Map ? Map<String, dynamic>.from(details['bangumi'] as Map) : <String, dynamic>{};

    return AnimeInfoParse.getBangumiTvId(bangumi);
  }

  /// 根据 Bangumi TV 条目 ID 获取弹弹play 动画 ID
  static Future<int?> requestDandanplayIdByBangumiId(int bgmId) async {
    final details =
        await DandanplayService.getBangumiByBgmId(bgmId);
    if (details == null) return null;

    final bangumi = details['bangumi'] is Map
        ? Map<String, dynamic>.from(details['bangumi'] as Map)
        : <String, dynamic>{};
    return AnimeInfoParse.toPositiveInt(bangumi['animeId'] ?? details['animeId']);
  }


  // ======================================================================== //
  // ======================================================================== //
  // ======================================================================== //

  static Future<Map<String, dynamic>?> _getDandanplayAnimePackageById(
    int dandanplayAnimeId,
  ) async {
    final details = await DandanplayService.getBangumiDetails(
      dandanplayAnimeId,
      useCache: false,
    );
    final bangumi = details['bangumi'] is Map
        ? Map<String, dynamic>.from(details['bangumi'] as Map)
        : <String, dynamic>{};
    final returnedAnimeId = AnimeInfoParse.toPositiveInt(
      bangumi['animeId'] ?? details['animeId'],
    );
    if (returnedAnimeId == null) return null;

    final rawEpisodes = bangumi['episodes'] is List
        ? bangumi['episodes'] as List
        : (details['episodes'] is List
            ? details['episodes'] as List
            : const <dynamic>[]);
    final episodes = rawEpisodes
        .whereType<Map>()
        .map((episode) => Map<String, dynamic>.from(episode))
        .toList();
    final anime = Map<String, dynamic>.from(
      bangumi.isNotEmpty ? bangumi : details,
    )
      ..remove('episodes')
      ..['animeId'] = returnedAnimeId;
    return <String, dynamic>{
      'anime': anime,
      'episodes': episodes,
    };
  }

  static DbAnimeEpisodeRelation _parseAnimeEpisodeRelationDandanplay(
    Map<String, dynamic> jsonObject,
  ) {
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

  static Future<Map<String, dynamic>> _getBangumiAnimePackageById(
    int bangumiAnimeId,
  ) async {
    final anime = await BangumiApiService.getPublicSubject(bangumiAnimeId);
    final returnedAnimeId = AnimeInfoParse.toPositiveInt(anime['id']);
    if (returnedAnimeId == null) {
      throw const FormatException('Bangumi Anime Package 缺少有效的 id');
    }
    final episodes =
        await BangumiApiService.getPublicSubjectEpisodes(bangumiAnimeId);
    return <String, dynamic>{
      'anime': anime,
      'episodes': episodes,
    };
  }

  static DbAnimeEpisodeRelation _parseAnimeEpisodeRelationBangumi(
    Map<String, dynamic> jsonObject,
  ) {
    final anime = jsonObject['anime'];
    if (anime is! Map) {
      throw const FormatException('Bangumi Anime Package 缺少 anime 对象');
    }
    final animeId = AnimeInfoParse.toPositiveInt(anime['id']);
    if (animeId == null) {
      throw const FormatException('Bangumi Anime Package 缺少有效的 id');
    }

    final episodeIdsBySortOrder = _parseEpisodeIdsBySortOrder(
      jsonObject,
      episodeIdKey: 'id',
      sortOrderKey: 'sort',
      sourceName: 'Bangumi',
    );
    return DbAnimeEpisodeRelation(
      animeId: animeId,
      episodeIds: episodeIdsBySortOrder.values,
    );
  }

  static Map<double, int> _parseEpisodeIdsBySortOrder(
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

  static Map<String, dynamic> _decodeAnimePackageCache(
    String content,
    String sourceName,
  ) {
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw FormatException('$sourceName Anime Package 缓存格式无效');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<_AnimeEpisodeDebugTitles> _loadAnimeEpisodeDebugTitles(
    String cacheRootPath,
  ) async {
    final titles = (
      dandanplayAnime: <int, String>{},
      bangumiAnime: <int, String>{},
      dandanplayEpisode: <int, String>{},
      bangumiEpisode: <int, String>{},
    );
    final dandanplayAnimeIds = await DatabaseService.getAllAnimeIds(
      DbAnimeEpisodeRelationType.dandanplay,
    );
    for (final animeId in dandanplayAnimeIds) {
      final file = File('$cacheRootPath/dandanplay/$animeId.json');
      if (!await file.exists()) continue;
      final package = _decodeAnimePackageCache(
        await file.readAsString(),
        file.path,
      );
      final anime = package['anime'];
      if (anime is Map) {
        final title = _dandanplayAnimeTitle(anime);
        if (title != null) titles.dandanplayAnime[animeId] = title;
      }
      _collectDebugEpisodeTitles(
        package,
        idKey: 'episodeId',
        titleKeys: const <String>['episodeTitle'],
        target: titles.dandanplayEpisode,
      );
    }

    final bangumiAnimeIds = await DatabaseService.getAllAnimeIds(
      DbAnimeEpisodeRelationType.bangumi,
    );
    for (final animeId in bangumiAnimeIds) {
      final file = File('$cacheRootPath/bangumi/$animeId.json');
      if (!await file.exists()) continue;
      final package = _decodeAnimePackageCache(
        await file.readAsString(),
        file.path,
      );
      final anime = package['anime'];
      if (anime is Map) {
        final title = _firstNonEmptyString(
          anime,
          const <String>['name_cn', 'name'],
        );
        if (title != null) titles.bangumiAnime[animeId] = title;
      }
      _collectDebugEpisodeTitles(
        package,
        idKey: 'id',
        titleKeys: const <String>['name_cn', 'name'],
        target: titles.bangumiEpisode,
      );
    }
    return titles;
  }

  static String? _dandanplayAnimeTitle(Map<dynamic, dynamic> anime) {
    final direct = _firstNonEmptyString(
      anime,
      const <String>['animeTitle', 'title'],
    );
    if (direct != null) return direct;

    final rawTitles = anime['titles'];
    if (rawTitles is! List) return null;
    for (final rawTitle in rawTitles) {
      if (rawTitle is! Map) continue;
      final title = rawTitle['title'];
      if (title is String && title.trim().isNotEmpty) return title;
    }
    return null;
  }

  static void _collectDebugEpisodeTitles(
    Map<String, dynamic> package, {
    required String idKey,
    required List<String> titleKeys,
    required Map<int, String> target,
  }) {
    final episodes = package['episodes'];
    if (episodes is! List) return;
    for (final episode in episodes) {
      if (episode is! Map || episode[idKey] is! num) continue;
      final title = _firstNonEmptyString(episode, titleKeys);
      if (title != null) {
        target[(episode[idKey] as num).toInt()] = title;
      }
    }
  }

  static String? _firstNonEmptyString(
    Map<dynamic, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }



  /// 抽取两个 JSON 文件的 episode 排序信息, 相互匹配, 确立对应关系
  /// 返回 Set<(int?, int?)>, 其中第一个元素为 Dandanplay Episode ID, 第二个元素为对应的 Bangumi Episode ID
  static Set<(int?, int?)> _getDandanplayBangumiEpisodeMatch(Map<String, dynamic> ddpJson, Map<String, dynamic> bgmJson) {

    final dandanplayEpisodeIdsBySortOrder = _parseEpisodeIdsBySortOrder(
      ddpJson,
      episodeIdKey: 'episodeId',
      sortOrderKey: 'episodeNumber',
      sourceName: 'Dandanplay',
    );
    final bangumiEpisodeIdsBySortOrder = _parseEpisodeIdsBySortOrder(
      bgmJson,
      episodeIdKey: 'id',
      sortOrderKey: 'sort',
      sourceName: 'Bangumi',
    );

    final matches = <(int?, int?)>{};
    for (final entry in dandanplayEpisodeIdsBySortOrder.entries) {
      matches.add((
        entry.value,
        bangumiEpisodeIdsBySortOrder[entry.key],
      ));
    }
    for (final entry in bangumiEpisodeIdsBySortOrder.entries) {
      if (!dandanplayEpisodeIdsBySortOrder.containsKey(entry.key)) {
        matches.add((null, entry.value));
      }
    }
    return matches;
  }

  static Future<String> _requestDandanplayDanmakuJson(int ddpEpiId) async {
    final apiPath = '/api/v2/comment/$ddpEpiId';
    final baseUrl = await NetworkSettings.getDandanplayServer();
    final appSecret = await DandanplayAuth.getAppSecret();
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    final uri = Uri.parse('$baseUrl$apiPath').replace(
      queryParameters: const <String, String>{
        'withRelated': 'true',
      },
    );
    final response = await http.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'User-Agent': DandanplayAuth.userAgent,
        'X-AppId': DandanplayAuth.appId,
        'X-AppSecret': appSecret,
        'X-Signature': DandanplayAuth.generateSignature(
          timestamp: timestamp,
          apiPath: apiPath,
          appSecret: appSecret,
        ),
        'X-Timestamp': '$timestamp',
      },
    );
    if (response.statusCode != 200) {
      final error = response.headers['x-error-message'] ?? response.body;
      throw Exception(
        '弹弹play弹幕请求失败 (${response.statusCode}): $error',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['comments'] is! List) {
      throw const FormatException('弹弹play弹幕响应格式无效');
    }
    return response.body;
  }
}
