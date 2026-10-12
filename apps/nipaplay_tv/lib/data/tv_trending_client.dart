import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nipaplay_core/models/bangumi_comment_model.dart';
import 'package:nipaplay_core/models/bangumi_model.dart';
import 'package:nipaplay_core/models/trending_bangumi.dart';
import 'package:nipaplay_core/services/nipaplay_server_router.dart';
import 'package:nipaplay_core/utils/network_settings.dart';

import 'tv_account_service.dart';

/// 排行榜需要登录但当前未登录时抛出（供 UI 引导到「我的」登录）。
class TvLoginRequiredException implements Exception {
  const TvLoginRequiredException();
  @override
  String toString() => '请先登录弹弹play账号后再使用该功能（「我的」→ 登录）';
}

/// TV 版弹弹网关客户端：排行榜 / 番剧详情 / 评论。
///
/// 关键：弹弹网关对 `/api/v2/*` **要求 `Authorization: Bearer <token>`**，
/// 未登录时返回 401（`errorCode:401 请先登录弹弹play账号`）。因此所有请求
/// 都带 [TvAccountService] 的登录凭据；网关地址经 core 的
/// [NipaplayServerRouter] 选择，**跟随用户的服务器/镜像设置**。
class TvTrendingClient {
  TvTrendingClient._();
  static final TvTrendingClient instance = TvTrendingClient._();

  static const _timeout = Duration(seconds: 15);
  static const _userAgent = 'NipaPlay/1.0';

  Future<Map<String, String>> _authHeaders() async {
    final account = TvAccountService.instance;
    await account.load();
    if (!account.isLoggedIn) throw const TvLoginRequiredException();
    return {
      'Accept': 'application/json',
      'User-Agent': _userAgent,
      ...account.authHeaders(),
    };
  }

  Future<dynamic> _getJson(String path, {Map<String, String>? query}) async {
    final headers = await _authHeaders();
    final base = await NipaplayServerRouter.instance.effectiveServer();
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final resp = await http.get(uri, headers: headers).timeout(_timeout);
    if (resp.statusCode == 401) throw const TvLoginRequiredException();
    if (resp.statusCode != 200) {
      throw Exception('请求失败：HTTP ${resp.statusCode}');
    }
    return json.decode(utf8.decode(resp.bodyBytes));
  }

  /// 排行榜（新番热度 Top）。
  Future<List<TrendingBangumiItem>> fetchTop({
    TrendingRankingKind kind = TrendingRankingKind.allHot,
    TrendingPeriod period = TrendingPeriod.week,
    int limit = 10,
  }) async {
    final path = TrendingBangumiQuery(kind: kind, period: period).apiPath;
    final decoded = await _getJson(path);
    final result = TrendingBangumiResult.fromJson(
      (decoded as Map).cast<String, dynamic>(),
    );
    return result.items.take(limit).toList();
  }

  /// 番剧详情（简介 / 评分 / 标签）。失败返回 null（UI 回退到榜单自带信息）。
  Future<BangumiAnime?> fetchAnimeDetail(int animeId) async {
    try {
      final decoded = await _getJson('/api/v2/bangumi/$animeId');
      final map = decoded is Map
          ? (decoded['bangumi'] ?? decoded).cast<String, dynamic>()
          : null;
      if (map == null) return null;
      return BangumiAnime.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// 番剧评论（弹弹网关镜像，page 从 0 开始，每页 20 条）。
  Future<List<DandanplayComment>> fetchComments(
    int animeId, {
    int page = 0,
  }) async {
    try {
      final decoded = await _getJson(
        '/api/v2/bangumi/$animeId/comments',
        query: {'page': '$page'},
      );
      final map = decoded is Map ? decoded.cast<String, dynamic>() : null;
      if (map == null) return const [];
      final raw = map['comments'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => DandanplayComment.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
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
