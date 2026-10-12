import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nipaplay_core/models/trending_bangumi.dart';
import 'package:nipaplay_core/services/nipaplay_server_router.dart';
import 'package:nipaplay_core/utils/network_settings.dart';

import 'tv_account_service.dart';

/// 排行榜需要登录但当前未登录时抛出（供 UI 引导到「我的」登录）。
class TvLoginRequiredException implements Exception {
  const TvLoginRequiredException();
  @override
  String toString() => '请先登录弹弹play账号后再使用排行榜（「我的」→ 登录）';
}

/// TV 版排行榜 / 新番客户端。
///
/// 关键：弹弹网关对 `/api/v2/*` **要求 `Authorization: Bearer <token>`**，
/// 未登录时返回 401（`errorCode:401 请先登录弹弹play账号`）。因此本客户端
/// 必须带 [TvAccountService] 的登录凭据；网关地址经 core 的
/// [NipaplayServerRouter] 选择，**跟随用户的服务器/镜像设置**。
class TvTrendingClient {
  TvTrendingClient._();
  static final TvTrendingClient instance = TvTrendingClient._();

  static const _timeout = Duration(seconds: 15);
  static const _userAgent = 'NipaPlay/1.0';

  /// 拉取排行榜（新番热度 Top）。
  Future<List<TrendingBangumiItem>> fetchTop({
    TrendingRankingKind kind = TrendingRankingKind.allHot,
    TrendingPeriod period = TrendingPeriod.week,
    int limit = 10,
  }) async {
    final account = TvAccountService.instance;
    if (!account.isLoggedIn) {
      throw const TvLoginRequiredException();
    }

    final base = await NipaplayServerRouter.instance.effectiveServer();
    final path = TrendingBangumiQuery(kind: kind, period: period).apiPath;
    final uri = Uri.parse('$base$path');

    final resp = await http.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent': _userAgent,
      // 弹弹网关鉴权：与普通版 DandanplayService.authorizationHeaders 一致。
      ...account.authHeaders(),
    }).timeout(_timeout);

    if (resp.statusCode == 401) {
      throw const TvLoginRequiredException();
    }
    if (resp.statusCode != 200) {
      throw Exception('排行榜请求失败：HTTP ${resp.statusCode}');
    }
    final decoded = json.decode(utf8.decode(resp.bodyBytes));
    final result = TrendingBangumiResult.fromJson(
      (decoded as Map).cast<String, dynamic>(),
    );
    return result.items.take(limit).toList();
  }

  /// 当前生效的弹弹网关地址（用于设置/我的页展示）。
  Future<String> effectiveServer() =>
      NipaplayServerRouter.instance.effectiveServer();

  /// 用户是否把弹弹服务器设为自定义地址。
  Future<bool> isCustomServer() async {
    final mode = await NetworkSettings.getDandanplayServerMode();
    return mode == DandanplayServerMode.custom;
  }
}
