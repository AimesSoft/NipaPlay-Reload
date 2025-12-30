import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nipaplay/models/shared_remote_library.dart';

class WebRemoteApiClient {
  const WebRemoteApiClient({this.baseUrl});

  final String? baseUrl;

  Uri _resolve(String path, {Map<String, String>? queryParameters}) {
    final normalized = path.startsWith('/') ? path : '/$path';

    Uri uri;
    final rawBaseUrl = baseUrl?.trim();
    if (rawBaseUrl != null && rawBaseUrl.isNotEmpty) {
      uri = Uri.parse(rawBaseUrl).resolve(normalized);
    } else {
      uri = Uri.parse(normalized);
    }

    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParameters);
    }

    return uri;
  }

  Uri resolveExternal(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final rawBaseUrl = baseUrl?.trim();
    if (rawBaseUrl != null && rawBaseUrl.isNotEmpty) {
      return Uri.parse(rawBaseUrl).resolve(normalized);
    }
    return Uri.base.resolve(normalized);
  }

  Uri resolveManageStream(String filePath) {
    final relative = Uri(
      path: '/api/media/local/manage/stream',
      queryParameters: {'path': filePath},
    );
    return resolveExternal(relative.toString());
  }

  Future<String?> fetchInfoSafe() async {
    try {
      final uri = _resolve('/api/info');
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return const JsonEncoder.withIndent('  ').convert(decoded);
      }
      return decoded.toString();
    } catch (_) {
      return null;
    }
  }

  Future<List<SharedRemoteAnimeSummary>> fetchSharedAnimeSummaries() async {
    final uri = _resolve('/api/media/local/share/animes');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid JSON payload');
    }

    final items = (decoded['items'] ?? decoded['data'] ?? const []) as List<dynamic>;
    return items
        .whereType<Map>()
        .map((e) => SharedRemoteAnimeSummary.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<WebSharedAnimeDetail> fetchSharedAnimeDetail(int animeId) async {
    final uri = _resolve('/api/media/local/share/animes/$animeId');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid JSON payload');
    }

    final data = (decoded['data'] ?? decoded) as Map<String, dynamic>;
    final anime = (data['anime'] ?? const <String, dynamic>{}) as Map<String, dynamic>;
    final episodesRaw = (data['episodes'] ?? const []) as List<dynamic>;
    final episodes = episodesRaw
        .whereType<Map>()
        .map((e) => SharedRemoteEpisode.fromJson(e.cast<String, dynamic>()))
        .toList();
    return WebSharedAnimeDetail(anime: anime, episodes: episodes);
  }

  Future<WebManagementData> fetchManagement() async {
    final foldersUri = _resolve('/api/media/local/manage/folders');
    final statusUri = _resolve('/api/media/local/manage/scan/status');

    final folderResponse = await http.get(foldersUri);
    if (folderResponse.statusCode == 404) {
      return const WebManagementData(
        folders: <SharedRemoteScannedFolder>[],
        scanStatus: null,
      );
    }
    if (folderResponse.statusCode != 200) {
      throw Exception('HTTP ${folderResponse.statusCode}');
    }

    final folderDecoded = json.decode(utf8.decode(folderResponse.bodyBytes));
    if (folderDecoded is! Map<String, dynamic>) {
      throw Exception('Invalid folders payload');
    }
    final Map<String, dynamic> folderMap =
        (folderDecoded['data'] as Map<String, dynamic>?) ?? folderDecoded;
    final foldersRaw = (folderMap['folders'] ?? const []) as List<dynamic>;
    final folders = foldersRaw
        .whereType<Map>()
        .map((e) => SharedRemoteScannedFolder.fromJson(e.cast<String, dynamic>()))
        .toList();

    SharedRemoteScanStatus? status;
    try {
      final statusResponse = await http.get(statusUri);
      if (statusResponse.statusCode == 200) {
        final statusDecoded = json.decode(utf8.decode(statusResponse.bodyBytes));
        if (statusDecoded is Map<String, dynamic>) {
          final Map<String, dynamic> statusMap =
              (statusDecoded['data'] as Map<String, dynamic>?) ?? statusDecoded;
          status = SharedRemoteScanStatus.fromJson(statusMap);
        }
      }
    } catch (_) {
      status = null;
    }

    return WebManagementData(folders: folders, scanStatus: status);
  }

  Future<void> addFolder(String folderPath, {required bool scan}) async {
    final uri = _resolve('/api/media/local/manage/folders');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
      body: json.encode({
        'path': folderPath,
        'scan': scan,
        'skipPreviouslyMatchedUnwatched': true,
      }),
    );

    if (response.statusCode == 404) {
      throw Exception('远程端不支持库管理接口');
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }

  Future<void> removeFolder(String folderPath) async {
    final uri = _resolve(
      '/api/media/local/manage/folders',
      queryParameters: {'path': folderPath},
    );
    final response = await http.delete(uri);
    if (response.statusCode == 404) {
      throw Exception('远程端不支持库管理接口');
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }

  Future<void> rescanAll() async {
    final uri = _resolve('/api/media/local/manage/scan/rescan');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
      body: json.encode({'skipPreviouslyMatchedUnwatched': true}),
    );
    if (response.statusCode == 404) {
      throw Exception('远程端不支持库管理接口');
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }

  Future<List<SharedRemoteFileEntry>> browseDirectory(String path) async {
    final uri = _resolve(
      '/api/media/local/manage/browse',
      queryParameters: {'path': path},
    );
    final response = await http.get(uri);
    if (response.statusCode == 404) {
      throw Exception('远程端不支持浏览接口');
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid browse payload');
    }
    final data = (decoded['data'] as Map<String, dynamic>?) ?? decoded;
    final entriesRaw = (data['entries'] ?? const []) as List<dynamic>;
    return entriesRaw
        .whereType<Map>()
        .map((e) => SharedRemoteFileEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<WebRemoteHistoryEntry>> fetchWatchHistory({int limit = 100}) async {
    final uri = _resolve(
      '/api/media/local/share/history',
      queryParameters: {'limit': '$limit'},
    );
    final response = await http.get(uri);
    if (response.statusCode == 404) {
      throw Exception('远程端暂不支持观看记录接口，请更新对方 NipaPlay。');
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid history payload');
    }
    final rawItems = (decoded['items'] ?? const []) as List<dynamic>;
    return rawItems
        .whereType<Map>()
        .map((e) => WebRemoteHistoryEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}

class WebSharedAnimeDetail {
  const WebSharedAnimeDetail({
    required this.anime,
    required this.episodes,
  });

  final Map<String, dynamic> anime;
  final List<SharedRemoteEpisode> episodes;

  String get title {
    final nameCn = anime['nameCn'] as String?;
    final name = anime['name'] as String?;
    if (nameCn != null && nameCn.trim().isNotEmpty) return nameCn;
    return name ?? '未知番剧';
  }

  String? get summary => anime['summary'] as String?;

  String? get imageUrl => anime['imageUrl'] as String?;
}

class WebManagementData {
  const WebManagementData({
    this.folders = const <SharedRemoteScannedFolder>[],
    this.scanStatus,
  });

  final List<SharedRemoteScannedFolder> folders;
  final SharedRemoteScanStatus? scanStatus;
}

class WebRemoteHistoryEntry {
  WebRemoteHistoryEntry({
    required this.episode,
    required this.animeName,
    required this.imageUrl,
  });

  final SharedRemoteEpisode episode;
  final String? animeName;
  final String? imageUrl;

  factory WebRemoteHistoryEntry.fromJson(Map<String, dynamic> json) {
    final episode = SharedRemoteEpisode.fromJson(json);
    return WebRemoteHistoryEntry(
      episode: episode,
      animeName: json['animeName'] as String?,
      imageUrl: json['imageUrl'] as String? ?? json['thumbnailPath'] as String?,
    );
  }
}
