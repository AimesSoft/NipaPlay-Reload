import 'dart:convert';

import 'package:nipaplay/services/dandanplay_http_client.dart' as http;
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

/// Shared data source for every manual or batch danmaku matching surface.
class DanmakuMatchingService {
  DanmakuMatchingService._();

  static final DanmakuMatchingService instance = DanmakuMatchingService._();

  /// The single client-side policy boundary for every danmaku matching flow.
  Future<void> ensureAccess() => DandanplayService.ensureLoggedInForMatching();

  Future<bool> canAccess() => DandanplayService.canAccessCurrentServer();

  Future<Map<String, dynamic>> matchVideo({
    required String fileName,
    required String fileHash,
    required int fileSize,
  }) async {
    await ensureAccess();
    return DandanplayService.matchVideo(
      fileName: fileName,
      fileHash: fileHash,
      fileSize: fileSize,
    );
  }

  Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    await ensureAccess();
    return DandanplayService.getVideoInfo(videoPath);
  }

  Future<List<Map<String, dynamic>>> searchAnime(String keyword) async {
    await ensureAccess();
    final normalized = keyword.trim();
    if (normalized.isEmpty) return Future.value(const []);
    return DandanplayService.searchAnime(normalized);
  }

  Future<List<Map<String, dynamic>>> getAnimeEpisodes(int animeId) async {
    await ensureAccess();
    if (animeId <= 0) {
      throw ArgumentError.value(animeId, 'animeId', '动画 ID 无效');
    }

    final data = await DandanplayService.getBangumiDetails(animeId);
    final bangumi = data['bangumi'];
    final rawEpisodes = bangumi is Map ? bangumi['episodes'] : data['episodes'];
    if (rawEpisodes is! List) {
      final message = data['errorMessage']?.toString().trim();
      if (data['success'] == false && message?.isNotEmpty == true) {
        throw StateError(message!);
      }
      return const [];
    }

    return [
      for (final entry in rawEpisodes)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }

  /// Title-based episode lookup used by media-server fallback matching.
  Future<List<Map<String, dynamic>>> searchEpisodes(String animeTitle) async {
    await ensureAccess();
    final normalized = animeTitle.trim();
    if (normalized.isEmpty) return const [];

    final appSecret = await DandanplayService.getAppSecret();
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    const apiPath = '/api/v2/search/episodes';
    final baseUrl = await DandanplayService.getApiBaseUrl();
    final response = await http.get(
      WebRemoteAccessService.proxyUri(
        Uri.parse('$baseUrl$apiPath?anime=${Uri.encodeComponent(normalized)}'),
      ),
      headers: {
        'Accept': 'application/json',
        'X-AppId': DandanplayService.appId,
        'X-Signature': DandanplayService.generateSignature(
          DandanplayService.appId,
          timestamp,
          apiPath,
          appSecret,
        ),
        'X-Timestamp': '$timestamp',
        ...DandanplayService.authorizationHeaders,
      },
    );

    if (response.statusCode != 200) {
      throw StateError('搜索剧集失败: HTTP ${response.statusCode}');
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map || decoded['animes'] is! List) return const [];
    return [
      for (final entry in decoded['animes'] as List)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }

  Future<Map<String, dynamic>> sendDanmaku({
    required int episodeId,
    required double time,
    required int mode,
    required int color,
    required String comment,
  }) {
    return DandanplayService.sendDanmaku(
      episodeId: episodeId,
      time: time,
      mode: mode,
      color: color,
      comment: comment,
    );
  }

  Future<Map<String, dynamic>> getDanmaku(String episodeId, int animeId) {
    return DandanplayService.getDanmaku(episodeId, animeId);
  }
}
