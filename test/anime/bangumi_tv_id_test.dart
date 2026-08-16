import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info_service.dart';
import 'package:nipaplay/utils/color.dart';

import '../environment_variables.dart';

void main() {
  test('根据 DanDanPlay AnimeID 获取 BangumiTv ID', () async {

    bool canRun = true;

    // 读取环境变量: 必须提供 AnimeID; 可选提供期望的 BangumiTv ID 用于精确断言
    final envDDAnimeIdText = Platform.environment[TestEnvironmentVariables.dandanplayAnimeId]?.trim();
    final envExpectedTvIdText = Platform.environment[TestEnvironmentVariables.expectedBangumiTvId]?.trim();
    if (envDDAnimeIdText == null || envDDAnimeIdText.isEmpty) {
      debugPrint('${color('测试 AnimeID', ColorCode.boldCyan)}: ${color('未设置', ColorCode.red)}');
      canRun = false;
    }
    final animeId = int.tryParse(envDDAnimeIdText ?? '');
    if (animeId == null || animeId <= 0) {
      debugPrint('${color('测试 AnimeID', ColorCode.boldCyan)}: ${color('无效', ColorCode.red)}');
      canRun = false;
    }
    if (!canRun) {
      debugPrint(color('测试未运行', ColorCode.red));
      return;
    }

    final expectedTvId = int.tryParse(envExpectedTvIdText ?? '');
    debugPrint('${color('测试 AnimeID', ColorCode.boldCyan)}: $animeId');
    if (expectedTvId != null && expectedTvId > 0) {
      debugPrint('${color('期望 BangumiTv ID', ColorCode.boldCyan)}: $expectedTvId');
    }

    final tvId = await AnimeInfoService.getBangumiTvIDByDanDanPlayID(animeId!);
    debugPrint('${color('实际 BangumiTv ID', ColorCode.boldCyan)}: $tvId');

    if (expectedTvId != null && expectedTvId > 0) {
      expect(tvId, isNotNull, reason: '已设置期望值时, 实际 BangumiTv ID 不能为空');
      expect(tvId! > 0, isTrue, reason: '接口返回了无效 BangumiTv ID');
      expect(tvId, expectedTvId);
    } else {
      // 部分 DanDanPlay 条目可能没有 tvId, 未提供期望值时仅验证接口调用成功
      expect(true, isTrue);
    }
  });
}
