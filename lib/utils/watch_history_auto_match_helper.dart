import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/dandanplay_service.dart';

class WatchHistoryAutoMatchHelper {
  static bool shouldAutoMatch(WatchHistoryItem item) {
    if (item.isDandanplayRemote) {
      return false;
    }
    final hasAnimeId = _isValidId(item.animeId);
    final hasEpisodeId = _isValidId(item.episodeId);
    return !(hasAnimeId && hasEpisodeId);
  }

  static bool _isValidId(int? value) => value != null && value > 0;

  static int? _parseNumericId(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Future<WatchHistoryItem> tryAutoMatch(
    BuildContext context,
    WatchHistoryItem item, {
    required String? matchablePath,
    void Function(String message)? onMatched,
  }) async {
    if (!shouldAutoMatch(item)) {
      return item;
    }
    if (matchablePath == null || matchablePath.trim().isEmpty) {
      return item;
    }

    final trimmedPath = matchablePath.trim();
    final isRemote =
        trimmedPath.startsWith('http://') || trimmedPath.startsWith('https://');
    bool pathUsable = isRemote;

    if (!pathUsable) {
      try {
        pathUsable = File(trimmedPath).existsSync();
      } catch (_) {
        pathUsable = false;
      }
    }

    if (!pathUsable) {
      debugPrint('[WatchHistoryAutoMatch] 跳过自动匹配，路径不可用: $trimmedPath');
      return item;
    }

    try {
      debugPrint('[WatchHistoryAutoMatch] 开始自动匹配: ${item.filePath}');
      final videoInfo = await DandanplayService.getVideoInfo(trimmedPath);
      final matches = videoInfo['matches'];

      if (videoInfo['isMatched'] == true && matches is List && matches.isNotEmpty) {
        final firstMatch = matches.first;
        if (firstMatch is! Map) {
          return item;
        }
        final bestMatch = Map<String, dynamic>.from(firstMatch);
        final animeId = _parseNumericId(bestMatch['animeId']);
        final episodeId = _parseNumericId(bestMatch['episodeId']);

        if (animeId == null || episodeId == null) {
          return item;
        }

        final rawAnimeTitle =
            videoInfo['animeTitle'] ?? bestMatch['animeTitle'];
        final rawEpisodeTitle =
            bestMatch['episodeTitle'] ?? videoInfo['episodeTitle'];
        final rawHash = videoInfo['fileHash'] ??
            videoInfo['hash'] ??
            item.videoHash;

        final animeTitle = rawAnimeTitle?.toString();
        final episodeTitle = rawEpisodeTitle?.toString();
        final hashString = rawHash?.toString();

        final updatedItem = item.copyWith(
          animeId: animeId,
          episodeId: episodeId,
          animeName: animeTitle?.isNotEmpty == true
              ? animeTitle
              : item.animeName,
          episodeTitle: episodeTitle?.isNotEmpty == true
              ? episodeTitle
              : item.episodeTitle,
          videoHash: hashString?.isNotEmpty == true
              ? hashString
              : item.videoHash,
        );

        await WatchHistoryDatabase.instance
            .insertOrUpdateWatchHistory(updatedItem);
        try {
          context.read<WatchHistoryProvider>().refresh();
        } catch (_) {
          // ignore, possibly not in provider scope
        }
        onMatched?.call('已为历史记录自动匹配弹幕');
        return updatedItem;
      }
    } catch (e) {
      debugPrint('[WatchHistoryAutoMatch] 自动匹配失败: $e');
    }

    return item;
  }
}
