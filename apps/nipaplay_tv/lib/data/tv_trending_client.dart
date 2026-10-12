import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nipaplay_core/models/trending_bangumi.dart';
import 'package:nipaplay_core/services/nipaplay_server_router.dart';
import 'package:nipaplay_core/utils/network_settings.dart';

/// TV 版排行榜 / 新番客户端。
///
/// 走 core 的 [NipaplayServerRouter] 选择有效网关（与普通版 `DandanplayService
/// .getApiBaseUrl()` 同源），因此**自动跟随用户的弹弹服务器设置与主备切换**。
/// 只实现 TV 首页需要的排行查询，避免把普通版 2878 行的 dandanplay 服务整包带进来。
class TvTrendingClient {
  TvTrendingClient._();
  static final TvTrendingClient instance = TvTrendingClient._();

  static const _timeout = Duration(seconds: 15);
  static const _userAgent = 'NipaPlay/1.0 (TV)';

  /// 拉取排行榜。默认取"全部·热度·日榜"，即新番热度 Top。
  Future<List<TrendingBangumiItem>> fetchTop({
    TrendingRankingKind kind = TrendingRankingKind.allHot,
    TrendingPeriod period = TrendingPeriod.week,
    int limit = 10,
  }) async {
    final base = await NipaplayServerRouter.instance.effectiveServer();
    final path =
        TrendingBangumiQuery(kind: kind, period: period).apiPath;
    final uri = Uri.parse('$base$path');
    final resp = await http.get(uri, headers: const {
      'Accept': 'application/json',
      'User-Agent': _userAgent,
    }).timeout(_timeout);

    if (resp.statusCode != 200) {
      throw Exception('排行榜请求失败：HTTP ${resp.statusCode}');
    }
    final decoded = json.decode(utf8.decode(resp.bodyBytes));
    final result = TrendingBangumiResult.fromJson(
      (decoded as Map).cast<String, dynamic>(),
    );
    return result.items.take(limit).toList();
  }

  /// 当前生效的弹弹网关地址（用于设置页展示）。
  Future<String> effectiveServer() =>
      NipaplayServerRouter.instance.effectiveServer();

  /// 用户是否把弹弹服务器设为自定义地址。
  Future<bool> isCustomServer() async {
    final mode = await NetworkSettings.getDandanplayServerMode();
    return mode == DandanplayServerMode.custom;
  }
}
