import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:nipaplay/utils/shared_remote_history_helper.dart';

/// 负责与局域网共享媒体主机同步播放进度
class SharedRemotePlaybackSyncService {
  SharedRemotePlaybackSyncService._internal();

  static final SharedRemotePlaybackSyncService instance =
      SharedRemotePlaybackSyncService._internal();

  final Duration _syncInterval = const Duration(seconds: 5);
  final Map<String, DateTime> _lastSyncTimes = {};

  Future<void> syncProgress({
    required String videoUrl,
    required int positionMs,
    required int durationMs,
    required double progress,
    bool force = false,
  }) async {
    if (!SharedRemoteHistoryHelper.isSharedRemoteStreamPath(videoUrl)) {
      return;
    }

    final progressUri = _buildProgressUri(videoUrl);
    if (progressUri == null) {
      debugPrint('[SharedRemoteSync] 无法解析共享媒体进度地址: $videoUrl');
      return;
    }

    final syncKey = _buildSyncKey(progressUri);
    final now = DateTime.now();
    if (!force) {
      final lastSync = _lastSyncTimes[syncKey];
      if (lastSync != null && now.difference(lastSync) < _syncInterval) {
        return;
      }
    }

    final sanitizedProgress = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    final sanitizedDuration = durationMs < 0 ? 0 : durationMs;
    final sanitizedPosition = positionMs < 0 ? 0 : positionMs;

    final payload = json.encode({
      'progress': sanitizedProgress,
      'positionMs': sanitizedPosition,
      'durationMs': sanitizedDuration,
      'clientUpdatedAt': now.toUtc().toIso8601String(),
    });

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final authHeader = _buildBasicAuthHeader(progressUri);
    if (authHeader != null) {
      headers['Authorization'] = authHeader;
    }

    try {
      final response = await http
          .post(progressUri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _lastSyncTimes[syncKey] = now;
        debugPrint('[SharedRemoteSync] 已同步播放进度: ${sanitizedPosition}ms/${sanitizedDuration}ms');
      } else if (response.statusCode == 404) {
        debugPrint('[SharedRemoteSync] 共享媒体记录不存在: ${progressUri.path}');
      } else {
        debugPrint('[SharedRemoteSync] 同步失败(${response.statusCode}): ${response.body}');
      }
    } on TimeoutException catch (_) {
      debugPrint('[SharedRemoteSync] 同步超时: $progressUri');
    } catch (e) {
      debugPrint('[SharedRemoteSync] 同步异常: $e');
    }
  }

  Future<void> syncThumbnail({
    required String videoUrl,
    required String thumbnailPath,
    DateTime? clientUpdatedAt,
    bool force = false,
  }) async {
    if (!SharedRemoteHistoryHelper.isSharedRemoteStreamPath(videoUrl)) {
      return;
    }

    final thumbnailUri = _buildThumbnailUri(videoUrl);
    if (thumbnailUri == null) {
      debugPrint('[SharedRemoteSync] 无法解析共享媒体缩略图地址: $videoUrl');
      return;
    }

    final file = File(thumbnailPath);
    if (!await file.exists()) {
      debugPrint('[SharedRemoteSync] 缩略图文件不存在: $thumbnailPath');
      return;
    }

    final now = clientUpdatedAt ?? DateTime.now();
    final syncKey = _buildSyncKey(thumbnailUri);
    if (!force) {
      final lastSync = _lastSyncTimes[syncKey];
      if (lastSync != null && now.difference(lastSync) < _syncInterval) {
        return;
      }
    }

    late final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      debugPrint('[SharedRemoteSync] 读取缩略图失败: $e');
      return;
    }

    if (bytes.isEmpty) {
      debugPrint('[SharedRemoteSync] 缩略图为空，跳过同步');
      return;
    }

    final payload = json.encode({
      'thumbnailBase64': base64Encode(bytes),
      'format': _resolveThumbnailFormat(thumbnailPath),
      'clientUpdatedAt': now.toUtc().toIso8601String(),
    });

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final authHeader = _buildBasicAuthHeader(thumbnailUri);
    if (authHeader != null) {
      headers['Authorization'] = authHeader;
    }

    try {
      final response = await http
          .post(thumbnailUri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _lastSyncTimes[syncKey] = now;
        debugPrint('[SharedRemoteSync] 已同步缩略图: $thumbnailPath');
      } else if (response.statusCode == 404) {
        debugPrint('[SharedRemoteSync] 主机未支持缩略图同步: ${thumbnailUri.path}');
      } else {
        debugPrint('[SharedRemoteSync] 缩略图同步失败(${response.statusCode}): ${response.body}');
      }
    } on TimeoutException catch (_) {
      debugPrint('[SharedRemoteSync] 缩略图同步超时: $thumbnailUri');
    } catch (e) {
      debugPrint('[SharedRemoteSync] 缩略图同步异常: $e');
    }
  }

  void resetState(String videoUrl) {
    final progressUri = _buildProgressUri(videoUrl);
    if (progressUri == null) {
      return;
    }
    final syncKey = _buildSyncKey(progressUri);
    _lastSyncTimes.remove(syncKey);
  }

  Uri? _buildProgressUri(String videoUrl) {
    return _buildEpisodeActionUri(videoUrl, 'progress');
  }

  Uri? _buildThumbnailUri(String videoUrl) {
    return _buildEpisodeActionUri(videoUrl, 'thumbnail');
  }

  Uri? _buildEpisodeActionUri(String videoUrl, String actionSegment) {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    final shareId = SharedRemoteHistoryHelper.extractSharedEpisodeId(videoUrl);
    if (shareId == null || shareId.isEmpty) {
      return null;
    }

    final segments = List<String>.from(uri.pathSegments);
    if (segments.isEmpty) {
      segments.addAll(['api', 'media', 'local', 'share', 'episodes', shareId, actionSegment]);
    } else if (segments.last.toLowerCase() == 'stream' ||
        segments.last.toLowerCase() == 'progress' ||
        segments.last.toLowerCase() == 'thumbnail') {
      segments[segments.length - 1] = actionSegment;
    } else {
      final episodesIndex =
          segments.lastIndexWhere((segment) => segment.toLowerCase() == 'episodes');
      if (episodesIndex == -1) {
        segments
          ..clear()
          ..addAll(['api', 'media', 'local', 'share', 'episodes', shareId, actionSegment]);
      } else {
        final baseSegments = segments.sublist(0, episodesIndex + 1);
        segments
          ..clear()
          ..addAll(baseSegments)
          ..addAll([shareId, actionSegment]);
      }
    }

    return uri.replace(
      pathSegments: segments,
      query: null,
      fragment: null,
    );
  }

  String _resolveThumbnailFormat(String thumbnailPath) {
    final lower = thumbnailPath.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'jpg';
    }
    return 'png';
  }

  String _buildSyncKey(Uri uri) {
    return '${uri.scheme}://${uri.authority}${uri.path}';
  }

  String? _buildBasicAuthHeader(Uri uri) {
    if (uri.userInfo.isEmpty) {
      return null;
    }

    final separatorIndex = uri.userInfo.indexOf(':');
    String username;
    String password;
    if (separatorIndex >= 0) {
      username = uri.userInfo.substring(0, separatorIndex);
      password = uri.userInfo.substring(separatorIndex + 1);
    } else {
      username = uri.userInfo;
      password = '';
    }

    username = Uri.decodeComponent(username);
    password = Uri.decodeComponent(password);

    return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }
}
