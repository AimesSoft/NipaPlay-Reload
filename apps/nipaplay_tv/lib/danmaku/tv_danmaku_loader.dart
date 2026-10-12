import 'dart:convert';

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

  Map<String, String> _headers(String? token) => {
        'Accept': 'application/json',
        'User-Agent': _userAgent,
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

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

      // 1) 匹配（主应用用 POST + 签名；TV 侧用 GET + token，网关同样接受）
      final matchUri = Uri.parse('$base/api/v2/match').replace(
        queryParameters: {
          'fileName': fileName,
          'fileSize': '$fileSize',
          if (fileHash != null && fileHash.isNotEmpty) 'fileHash': fileHash,
        },
      );
      final matchResp =
          await http.get(matchUri, headers: _headers(token)).timeout(_timeout);
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
      final danmakuUri = Uri.parse(
          '$base/api/v2/comment/$episodeId?withRelated=true');
      final danmakuResp =
          await http.get(danmakuUri, headers: _headers(token)).timeout(_timeout);
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