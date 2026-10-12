import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay_core/constants/danmaku/mode.dart';
import 'package:nipaplay_core/models/danmaku/danmaku_item.dart';
import 'package:nipaplay_core/services/nipaplay_server_router.dart';

import '../data/tv_account_service.dart';

/// TV 版自动弹幕加载器。
///
/// 背景：播放页的 `danmakuItems` 之前恒为空列表（无人加载），弹幕层永远空白。
/// 这里实现"按文件名匹配 → 拉取弹幕"的自动链路，走弹弹网关（跟随用户的
/// 服务器/镜像设置）。
///
/// 匹配流程（与普通版 `DanmakuMatchingService` 同构，端点一致）：
/// 1. `POST /api/v2/match` → animeId / episodeId；
/// 2. `GET  /api/v2/comment/{episodeId}?withRelated=true` → comments；
/// 3. 解析 `p` 字段（格式 `时间,模式,颜色,用户ID`）为 core `DanmakuItem`。
///
/// 需要登录弹弹play账号（网关鉴权）；未登录返回 null（UI 提示登录）。
class TvDanmakuLoader {
  TvDanmakuLoader._();
  static final TvDanmakuLoader instance = TvDanmakuLoader._();

  static const _timeout = Duration(seconds: 20);
  static const _userAgent = 'NipaPlay/1.0';

  static const _appId = 'nipaplayv1';
  static const _appSecret = 'server-managed';

  /// 与主应用 `DandanplayService` 相同的请求头签名（网关要求）。
  Map<String, String> _headers(String? token, String apiPath) {
    final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000)
        .round();
    final source = '$_appId$timestamp$apiPath$_appSecret';
    final signature = base64Encode(sha256.convert(utf8.encode(source)).bytes);
    return {
      'Accept': 'application/json',
      'User-Agent': _userAgent,
      'X-AppId': _appId,
      'X-Timestamp': '$timestamp',
      'X-Signature': signature,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// 加载某视频文件的弹幕。
  ///
  /// 返回 `null` = 未登录或未匹配到（UI 可提示）；
  /// 返回空列表 = 已匹配但该番剧暂无弹幕。
  Future<List<DanmakuItem>?> loadForFile({
    required String fileName,
    int fileSize = 0,
    String? fileHash,
  }) async {
    final account = TvAccountService.instance;
    await account.load();
    if (!account.isLoggedIn) {
      debugPrint('[TVDanmaku] 未登录弹弹play，跳过弹幕匹配');
      return null;
    }

    try {
      final base = await NipaplayServerRouter.instance.effectiveServer();
      final token = account.token;

      // 1) 匹配：与主应用一致 — POST /api/v2/match + 签名头 + JSON body
      const matchPath = '/api/v2/match';
      final matchUri = Uri.parse('$base$matchPath');
      debugPrint('[TVDanmaku] match POST $matchUri file=$fileName '
          '(loggedIn=${account.isLoggedIn}, token=${token != null})');
      final matchHeaders = <String, String>{
        ..._headers(token, matchPath),
        'Content-Type': 'application/json',
      };
      final matchResp = await http
          .post(matchUri,
              headers: matchHeaders,
              body: json.encode({
                'fileName': fileName,
                'fileHash': fileHash ?? '',
                'fileSize': fileSize,
                'matchMode': 'hashAndFileName',
              }))
          .timeout(_timeout);
      debugPrint('[TVDanmaku] match HTTP ${matchResp.statusCode} '
          '${utf8.decode(matchResp.bodyBytes, allowMalformed: true).substring(0, (matchResp.bodyBytes.length > 180 ? 180 : matchResp.bodyBytes.length))}');
      if (matchResp.statusCode != 200) {
        debugPrint('[TVDanmaku] match HTTP ${matchResp.statusCode}');
        return null;
      }
      final matchData =
          json.decode(utf8.decode(matchResp.bodyBytes)) as Map<String, dynamic>;
      final animeId = (matchData['animeId'] as num?)?.toInt() ?? 0;
      final episodeId = (matchData['episodeId'] as num?)?.toInt() ?? 0;
      if (animeId <= 0 || episodeId <= 0) {
        debugPrint('[TVDanmaku] 未匹配到番剧: $fileName');
        return null;
      }

      // 2) 拉取弹幕（端点与主应用一致）
      final commentPath = '/api/v2/comment/$episodeId';
      final danmakuUri =
          Uri.parse('$base$commentPath?withRelated=true&chConvert=0');
      debugPrint('[TVDanmaku] comment GET $danmakuUri');
      final danmakuResp = await http
          .get(danmakuUri, headers: _headers(token, commentPath))
          .timeout(_timeout);
      debugPrint('[TVDanmaku] comment HTTP ${danmakuResp.statusCode}');
      if (danmakuResp.statusCode != 200) {
        debugPrint('[TVDanmaku] comment HTTP ${danmakuResp.statusCode}');
        return const [];
      }
      final payload =
          json.decode(utf8.decode(danmakuResp.bodyBytes)) as Map<String, dynamic>;
      final comments = payload['comments'];
      if (comments is! List) return const [];

      // 3) 解析：p = "时间,模式,颜色,用户ID"
      final items = <DanmakuItem>[];
      for (final c in comments) {
        if (c is! Map) continue;
        final p = (c['p'] as String?) ?? '';
        final parts = p.split(',');
        if (parts.length < 3) continue;
        final seconds = double.tryParse(parts[0]);
        if (seconds == null) continue;
        final text = (c['m'] as String?) ?? '';
        if (text.isEmpty) continue;
        items.add(DanmakuItem(
          time: Duration(milliseconds: (seconds * 1000).round()),
          content: text,
          mode: DanmakuMode.fromCode(int.tryParse(parts[1])),
          colorRgb: int.tryParse(parts[2]) ?? 0xFFFFFF,
        ));
      }
      items.sort((a, b) => a.time.compareTo(b.time));
      debugPrint('[TVDanmaku] 加载 ${items.length} 条弹幕 (animeId=$animeId)');
      return items;
    } catch (e) {
      debugPrint('[TVDanmaku] 加载异常: $e');
      return null;
    }
  }
}