import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

class WebRemoteHistorySyncService {
  WebRemoteHistorySyncService._internal();

  static final WebRemoteHistorySyncService instance =
      WebRemoteHistorySyncService._internal();

  static const Duration _syncInterval = Duration(seconds: 5);
  final Map<String, DateTime> _lastSyncTimes = {};

  Future<void> syncProgress({
    required WatchHistoryItem item,
    required int positionMs,
    required int durationMs,
    required double progress,
    bool force = false,
    DateTime? clientUpdatedAt,
    String? filePathOverride,
  }) async {
    if (!kIsWeb) return;

    final filePath = (filePathOverride ?? item.filePath).trim();
    if (filePath.isEmpty) return;

    final baseUrl = await WebRemoteAccessService.resolveCandidateBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) return;

    final syncKey = '$baseUrl|$filePath';
    final now = DateTime.now();
    if (!force) {
      final lastSync = _lastSyncTimes[syncKey];
      if (lastSync != null && now.difference(lastSync) < _syncInterval) {
        return;
      }
    }

    final sanitizedProgress = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    final sanitizedPosition = positionMs < 0 ? 0 : positionMs;
    final sanitizedDuration = durationMs < 0 ? 0 : durationMs;

    final payload = json.encode({
      'filePath': filePath,
      'progress': sanitizedProgress,
      'positionMs': sanitizedPosition,
      'durationMs': sanitizedDuration,
      'animeName': item.animeName,
      'episodeTitle': item.episodeTitle,
      'episodeId': item.episodeId,
      'animeId': item.animeId,
      'videoHash': item.videoHash,
      'clientUpdatedAt':
          (clientUpdatedAt ?? now).toUtc().toIso8601String(),
    });

    try {
      final uri = Uri.parse('$baseUrl/api/history/progress');
      final response = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _lastSyncTimes[syncKey] = now;
      } else {
        debugPrint(
            '[WebRemoteHistorySync] Sync failed (${response.statusCode}): ${response.body}');
      }
    } on TimeoutException catch (_) {
      debugPrint('[WebRemoteHistorySync] Sync timeout: $filePath');
    } catch (e) {
      debugPrint('[WebRemoteHistorySync] Sync error: $e');
    }
  }
}
