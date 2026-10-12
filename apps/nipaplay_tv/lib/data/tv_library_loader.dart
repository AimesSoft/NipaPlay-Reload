import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay_core/models/dandanplay_remote_model.dart';
import 'package:nipaplay_core/services/webdav_service.dart';

/// 媒体库中的一条可展示内容（番剧卡片的数据源）。
class TvLibraryItem {
  const TvLibraryItem({
    required this.title,
    required this.sourceLabel,
    this.coverUrl = '',
    this.episodeLabel,
    this.rating,
    this.isNew = false,
    this.playUri,
    this.animeId,
    this.episodes = const [],
  });

  final String title;
  final String sourceLabel;
  final String coverUrl;
  final String? episodeLabel;
  final double? rating;
  final bool isNew;

  /// 可直接播放的地址（远程/WebDAV 条目才有）。
  final String? playUri;

  /// 关联的弹弹/Bangumi 番剧 ID（用于拉取详情与评论）。
  final int? animeId;

  /// 分集（用于详情页）。
  final List<TvLibraryEpisode> episodes;
}

class TvLibraryEpisode {
  const TvLibraryEpisode({
    required this.title,
    required this.playUri,
    this.thumbnailUrl = '',
    this.matched = false,
    this.fileName = '',
    this.fileHash = '',
  });

  final String title;
  final String playUri;
  final String thumbnailUrl;
  final bool matched;

  /// 原始文件名（如 `Kill la Kill 01 [BD 1920x1080 HEVC].mkv`）与文件哈希。
  /// **弹幕匹配必须用它**——playUri 是流地址（含 UUID），用它匹配永远失败。
  final String fileName;
  final String fileHash;
}

/// 把各类媒体源解析为统一的番剧条目列表。
///
/// - **弹弹远程服务**：core [DandanplayRemoteService.refreshLibrary] 拉条目，
///   按番剧分组；封面走弹弹网关的图片代理；
/// - **WebDAV**：core [WebDAVService.listDirectory] 列目录，视频文件作为条目，
///   文件夹递归一层取首个视频作封面；
/// - **本地文件/文件夹**：直接列目录（无需网络）。
class TvLibraryLoader {
  const TvLibraryLoader._();

  /// 加载一个媒体源的内容。
  static Future<List<TvLibraryItem>> load({
    required String kind,
    required String location,
    String? username,
    String? password,
    String? token,
    String? accountToken,
  }) async {
    switch (kind) {
      case 'dandanplayRemote':
        return _loadDandanplayRemote(location, token: token ?? accountToken);
      case 'webdav':
        return _loadWebDav(location, username ?? '', password ?? '');
      default:
        return const [];
    }
  }

  // ---------- 弹弹远程服务 ----------
  //
  // 直接请求 `GET /api/v1/library`（不经过 DandanplayRemoteService 单例），
  // 因为该单例只保存一个 baseUrl，**多组弹弹端口会互相覆盖**。
  // 这里按源独立请求，天然支持同时添加多个弹弹服务。
  /// 地址规范化 — 搬自 core `DandanplayRemoteService._normalizeBaseUrl`：
  /// 补 scheme、去尾斜杠、去掉误带的 `/api` 后缀。
  ///
  /// 这是"该来源暂无番剧内容"的根因：用户只填 `192.168.3.39:30000`，
  /// 无 scheme 时 `Uri.parse` 抛 FormatException，异常被上层静默吞掉。
  static String _normalizeBaseUrl(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'http://$v';
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    if (v.endsWith('/api')) {
      v = v.substring(0, v.length - 4);
    }
    return v;
  }

  static Future<List<TvLibraryItem>> _loadDandanplayRemote(
    String baseUrl, {
    String? token,
  }) async {
    final base = _normalizeBaseUrl(baseUrl);
    final uri = Uri.parse('$base/api/v1/library');
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'NipaPlay/1.0',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    debugPrint('[TVLib] dandanplayRemote GET $uri (token=${token != null})');
    final resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20))
        .catchError((e) {
      throw TvLibraryLoadException('请求弹弹远程媒体库失败（$uri）：$e');
    });
    debugPrint('[TVLib] dandanplayRemote $baseUrl -> HTTP ${resp.statusCode}, '
        'bodyLen=${resp.bodyBytes.length}');
    if (resp.statusCode == 401) {
      throw const TvLibraryLoadException('弹弹远程服务鉴权失败（API 密钥无效或缺失）');
    }
    if (resp.statusCode != 200) {
      throw TvLibraryLoadException('访问远程媒体库失败：HTTP ${resp.statusCode}');
    }
    final decoded = json.decode(utf8.decode(resp.bodyBytes));
    if (decoded is! List) {
      debugPrint('[TVLib] dandanplayRemote $baseUrl 响应非列表: ${decoded.runtimeType}');
      throw const TvLibraryLoadException('服务器返回了未知的数据结构');
    }
    final episodes = decoded
        .whereType<Map<String, dynamic>>()
        .map(DandanplayRemoteEpisode.fromJson)
        .toList();

    // 按番剧标题分组
    final groups = <String, List<DandanplayRemoteEpisode>>{};
    for (final e in episodes) {
      final title = e.animeTitle.isNotEmpty ? e.animeTitle : e.name;
      groups.putIfAbsent(title, () => []).add(e);
    }
    debugPrint('[TVLib] dandanplayRemote $baseUrl 解析到 ${episodes.length} 条，'
        '分组 ${groups.length} 个');
    final items = <TvLibraryItem>[];
    groups.forEach((title, list) {
        // 自然排序：第1话 < 第2话 < 第10话（字符串排序会把第10话排到第1话前）
        list.sort((a, b) => _naturalCompare(a.episodeTitle, b.episodeTitle));
      final first = list.first;
      items.add(TvLibraryItem(
        title: title,
        sourceLabel: '弹弹远程',
        animeId: first.animeId,
        // 封面/缩略图走弹弹网关的图片代理（带 token）
        coverUrl: _remoteImage(base, first.hash, token),
        episodeLabel: '${list.length} 集',
        episodes: list
            .map((e) => TvLibraryEpisode(
                  title:
                      e.episodeTitle.isNotEmpty ? e.episodeTitle : e.name,
                  playUri: '$base/api/v1/stream/id/${e.entryId}',
                  thumbnailUrl: _remoteImage(base, e.hash, token),
                  matched: e.animeId != null,
                  fileName: e.name,
                  fileHash: e.hash,
                ))
            .toList(),
      ));
    });
    return items;
  }

  /// 自然排序：数字片段按数值比（第1话 < 第2话 < 第10话）。
  static int _naturalCompare(String a, String b) {
    final ra = RegExp(r'\d+').allMatches(a).map((m) => m.group(0)!).toList();
    final rb = RegExp(r'\d+').allMatches(b).map((m) => m.group(0)!).toList();
    final n = ra.length < rb.length ? ra.length : rb.length;
    for (var i = 0; i < n; i++) {
      final na = int.tryParse(ra[i]) ?? 0;
      final nb = int.tryParse(rb[i]) ?? 0;
      if (na != nb) return na.compareTo(nb);
    }
    if (ra.length != rb.length) return ra.length.compareTo(rb.length);
    return a.compareTo(b);
  }


  static String _remoteImage(String base, String hash, String? token) {
    if (hash.isEmpty) return '';
    final t = (token != null && token.isNotEmpty) ? '?token=$token' : '';
    return '$base/api/v1/image/$hash$t';
  }

  // ---------- WebDAV ----------
  static Future<List<TvLibraryItem>> _loadWebDav(
    String url,
    String username,
    String password,
  ) async {
    final conn = WebDAVConnection(
      name: 'WebDAV',
      url: url,
      username: username,
      password: password,
    );
    final service = WebDAVService.instance;
    final entries = await service.listDirectory(conn, '/');
    final items = <TvLibraryItem>[];
    for (final f in entries) {
      if (f.isDirectory) {
        // 目录：递归一层，取其中的视频作为分集
        final children =
            await service.listDirectory(conn, f.path).catchError((_) => <WebDAVFile>[]);
        final videos = children.where((c) => !c.isDirectory).toList();
        if (videos.isEmpty) continue;
        items.add(TvLibraryItem(
          title: f.name,
          sourceLabel: 'WebDAV',
          episodeLabel: '${videos.length} 集',
          episodes: videos
              .map((v) => TvLibraryEpisode(
                    title: v.name,
                    playUri: _webdavUri(url, v.path, username, password),
                  ))
              .toList(),
        ));
      } else {
        items.add(TvLibraryItem(
          title: f.name,
          sourceLabel: 'WebDAV',
          playUri: _webdavUri(url, f.path, username, password),
        ));
      }
    }
    return items;
  }

  static String _webdavUri(
      String base, String path, String user, String pass) {
    final clean = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    final auth = (user.isNotEmpty || pass.isNotEmpty)
        ? '${Uri.encodeComponent(user)}:${Uri.encodeComponent(pass)}@'
        : '';
    final scheme = clean.startsWith('https') ? 'https' : 'http';
    final host = clean.replaceFirst(RegExp(r'^https?://'), '');
    return '$scheme://$auth$host$p';
  }

  /// 调试用：把条目编码成可读 JSON（日志/自检）。
  static String describe(List<TvLibraryItem> items) =>
      json.encode(items.map((e) => {'t': e.title, 'n': e.episodes.length}).toList());
}

/// 供 UI 捕获的加载错误。
class TvLibraryLoadException implements Exception {
  const TvLibraryLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}
