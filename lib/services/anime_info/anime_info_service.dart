
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/database/anime_episode_relation.dart';
import 'package:nipaplay/models/database/asset_record.dart';
import 'package:nipaplay/services/anime_info/util.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/services/dandanplay_service_io.dart';
import 'package:nipaplay/utils/anime_info_parse.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/dandanplay_auth.dart';
import 'package:nipaplay/utils/file_hash.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/utils/storage_service.dart';

part 'anime_info_models.dart';
part 'anime_info_service_impl.dart';

class AnimeInfoService {

  // 主要方法
  // ------------------------------------------------------------------------ //
  static Future<void>      identifyFile    (String filePath, {bool forceMatch = false,}) => _AnimeInfoRepository.identifyFileUseDandanplayMatch(filePath, forceMatch: forceMatch);
  static Future<void>      linkDandanplayBangumiAnime     (int comAniId) => _AnimeInfoRepository.linkDandanplayBangumiAnime(comAniId);
  static Future<JsonData?> getDandanplayDanmakuByAssetHash(Uint8List assetHash) => _AnimeInfoRepository.getDandanplayDanmakuByAssetHash(assetHash);


  // 刷新数据
  // ------------------------------------------------------------------------ //

  // 访问 API 刷新缓存
  static Future<void> refreshDandanplayAnimeCache             (int ddpAniId) => _AnimeInfoRepository.refreshDandanplayAnimeCacheJson(ddpAniId);
  static Future<void> refreshDandanplayAnimeCacheByBangumiId  (int bgmAniId) => _AnimeInfoRepository.refreshDandanplayAnimeCacheByBangumiId(bgmAniId);
  static Future<void> refreshDandanplayDanmakuCacheByEpisodeId(int ddpEpiId) => _AnimeInfoRepository.refreshDandanplayDanmakuCacheByEpisodeId(ddpEpiId);
  static Future<void> refreshBangumiAnimeCacheJson            (int bgmAniId) => _AnimeInfoRepository.refreshBangumiAnimeCacheJson(bgmAniId);

  // 利用缓存刷新数据库
  static Future<void> refreshDandanplayAnimeRelationByCache   (int ddpAniId) => _AnimeInfoRepository.refreshDandanplayAnimeRelationByCache(ddpAniId);
  static Future<void> refreshBangumiAnimeRelationByCache      (int bgmAniId) => _AnimeInfoRepository.refreshBangumiAnimeRelationByCache(bgmAniId);


  // API 请求
  // ------------------------------------------------------------------------ //
  static Future<int?> requestBangumiIdByDandanplayId(int ddpId) => _AnimeInfoRepository.requestBangumiIdByDandanplayId(ddpId);
  static Future<int?> requestDandanplayIdByBangumiId(int bgmId) => _AnimeInfoRepository.requestDandanplayIdByBangumiId(bgmId);
  static Future<DandanplayFileMatchResult?> requestDandanplayFileMatch(DandanplayFileMatchArgument arg,) => _AnimeInfoRepository.requestDandanplayFileMatch(arg);


  // 调试方法
  // ------------------------------------------------------------------------ //
  static Future<String> debugAnimeEpisodeRelations({String? cacheRootPath,}) =>_AnimeInfoRepository.debugAnimeEpisodeRelations(cacheRootPath: cacheRootPath);
}
