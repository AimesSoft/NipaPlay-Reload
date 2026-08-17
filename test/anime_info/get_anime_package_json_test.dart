
// test/anime/bangumi_episode_data_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/dandanplay_service_io.dart';

import '../environment_variables.dart';


void main() {

  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('根据 Bangumi TV AnimeID 打印原始剧集 JSON', () async {

    // 变量获取ce.getPublicSubjectEpisode
    final envIdStr = Platform.environment[TestEnvironmentVariables.bangumiTvAnimeId]?.trim();
    final envId = int.tryParse(envIdStr ?? '');
    if (envId == null || envId <= 0) {
      final msg = (
        '${color('测试 BangumiTv AnimeID', ColorCode.boldCyan)}: '
        '${color('未设置或无效', ColorCode.red)}'
      );
      if (kDebugMode) print(msg);
      return;
    }

    final bgmID = envId;
    debugPrint('${color('测试 BangumiTv AnimeID', ColorCode.boldCyan)}: $bgmID');

    final episodes = await BangumiApiService.getPublicSubjectEpisodes(bgmID);
    expect(episodes, isNotEmpty);

    final msg = const JsonEncoder.withIndent('  ').convert(<String, dynamic>{'animeId': envId,'episodes': episodes});
    if (kDebugMode) print(msg);
  });


  test('根据 DanDanPlay Anime ID 打印原始剧集 JSON', () async {

    final envIdStr = Platform.environment[TestEnvironmentVariables.dandanplayAnimeId]?.trim();
    final envId = int.tryParse(envIdStr ?? '');
    if (envId == null || envId <= 0) {
      debugPrint(
        '${color(TestEnvironmentVariables.dandanplayAnimeId, ColorCode.boldCyan)}: '
        '${color('未设置或无效', ColorCode.red)}',
      );
      return;
    }

    final ddId = envId;
    if (kDebugMode) print('${color('测试 DanDanPlay AnimeID', ColorCode.boldCyan)}: $ddId');

    final details = await DandanplayService.getBangumiDetails(ddId, useCache: false);
    final bangumi = details['bangumi'] is Map
        ? Map<String, dynamic>.from(details['bangumi'] as Map)
        : <String, dynamic>{};
    final episodes = bangumi['episodes'] is List
        ? bangumi['episodes'] as List
        : (details['episodes'] is List ? details['episodes'] as List : const []);

    expect(episodes, isNotEmpty);
    debugPrint(
      const JsonEncoder.withIndent('  ').convert(
        <String, dynamic>{
          'animeId': ddId,
          'episodes': episodes,
        },
      ),
    );
  });
}
