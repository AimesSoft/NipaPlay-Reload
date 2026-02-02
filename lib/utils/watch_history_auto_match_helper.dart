import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_dandanplay_matcher.dart';
import 'package:nipaplay/services/emby_dandanplay_matcher.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';
import 'package:nipaplay/services/emby_episode_mapping_service.dart';

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

    final serverMatched = await _tryAutoMatchWithServerMatcher(context, item);
    if (serverMatched != null) {
      await _persistMatchedHistory(context, serverMatched);
      onMatched?.call('已为历史记录自动匹配弹幕');
      return serverMatched;
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

        await _persistMatchedHistory(context, updatedItem);

        await _recordServerMappingsIfNeeded(
          updatedItem,
          animeId: animeId,
          episodeId: episodeId,
          animeTitle: animeTitle ?? updatedItem.animeName,
        );

        onMatched?.call('已为历史记录自动匹配弹幕');
        return updatedItem;
      }
    } catch (e) {
      debugPrint('[WatchHistoryAutoMatch] 自动匹配失败: $e');
    }

    return item;
  }

  static Future<WatchHistoryItem?> _tryAutoMatchWithServerMatcher(
    BuildContext context,
    WatchHistoryItem item,
  ) async {
    final filePath = item.filePath;
    if (filePath.startsWith('jellyfin://')) {
      final episodeId = _extractServerEpisodeId(filePath, 'jellyfin://');
      if (episodeId == null) {
        return null;
      }

      final jellyfinService = JellyfinService.instance;
      if (!jellyfinService.isConnected) {
        debugPrint('[WatchHistoryAutoMatch] Jellyfin未连接，跳过服务端匹配');
        return null;
      }

      final episodeInfo = await jellyfinService.getEpisodeDetails(episodeId);
      if (episodeInfo == null) {
        return null;
      }

      final matched = await JellyfinDandanplayMatcher.instance
          .createPlayableHistoryItem(context, episodeInfo, showMatchDialog: false);
      return _mergeMatchedHistoryItem(item, matched);
    }

    if (filePath.startsWith('emby://')) {
      final episodeId = _extractServerEpisodeId(filePath, 'emby://');
      if (episodeId == null) {
        return null;
      }

      final embyService = EmbyService.instance;
      if (!embyService.isConnected) {
        debugPrint('[WatchHistoryAutoMatch] Emby未连接，跳过服务端匹配');
        return null;
      }

      final episodeInfo = await embyService.getEpisodeDetails(episodeId);
      if (episodeInfo == null) {
        return null;
      }

      final matched = await EmbyDandanplayMatcher.instance
          .createPlayableHistoryItem(context, episodeInfo, showMatchDialog: false);
      return _mergeMatchedHistoryItem(item, matched);
    }

    return null;
  }

  static WatchHistoryItem? _mergeMatchedHistoryItem(
    WatchHistoryItem original,
    WatchHistoryItem? matched,
  ) {
    if (matched == null) {
      return null;
    }

    final hasAnimeId = _isValidId(matched.animeId);
    final hasEpisodeId = _isValidId(matched.episodeId);
    if (!hasAnimeId || !hasEpisodeId) {
      return null;
    }

    final matchedHash = matched.videoHash?.trim();
    return original.copyWith(
      animeId: matched.animeId,
      episodeId: matched.episodeId,
      animeName: matched.animeName,
      episodeTitle: matched.episodeTitle,
      videoHash: matchedHash?.isNotEmpty == true ? matchedHash : original.videoHash,
    );
  }

  static Future<void> _persistMatchedHistory(
    BuildContext context,
    WatchHistoryItem item,
  ) async {
    await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(item);
    try {
      context.read<WatchHistoryProvider>().refresh();
    } catch (_) {
      // ignore, possibly not in provider scope
    }
  }

  static Future<void> _recordServerMappingsIfNeeded(
    WatchHistoryItem item, {
    required int animeId,
    required int episodeId,
    required String? animeTitle,
  }) async {
    final filePath = item.filePath;
    if (filePath.startsWith('jellyfin://')) {
      await _recordJellyfinMapping(
        filePath,
        animeId: animeId,
        episodeId: episodeId,
        animeTitle: animeTitle,
      );
    } else if (filePath.startsWith('emby://')) {
      await _recordEmbyMapping(
        filePath,
        animeId: animeId,
        episodeId: episodeId,
        animeTitle: animeTitle,
      );
    }
  }

  static Future<void> _recordJellyfinMapping(
    String filePath, {
    required int animeId,
    required int episodeId,
    required String? animeTitle,
  }) async {
    final jellyfinService = JellyfinService.instance;
    if (!jellyfinService.isConnected) {
      debugPrint('[WatchHistoryAutoMatch] Jellyfin未连接，跳过映射写入');
      return;
    }

    final jellyfinEpisodeId = _extractServerEpisodeId(filePath, 'jellyfin://');
    if (jellyfinEpisodeId == null) {
      return;
    }

    try {
      final episodeInfo = await jellyfinService.getEpisodeDetails(jellyfinEpisodeId);
      if (episodeInfo == null) {
        debugPrint('[WatchHistoryAutoMatch] 无法获取Jellyfin剧集详情，跳过映射写入');
        return;
      }

      final seriesId = episodeInfo.seriesId;
      if (seriesId == null || seriesId.isEmpty) {
        debugPrint('[WatchHistoryAutoMatch] Jellyfin剧集缺少seriesId，无法写入映射');
        return;
      }

      final mappingId = await JellyfinEpisodeMappingService.instance.createOrUpdateAnimeMapping(
        jellyfinSeriesId: seriesId,
        jellyfinSeriesName: episodeInfo.seriesName ?? '',
        jellyfinSeasonId: episodeInfo.seasonId,
        dandanplayAnimeId: animeId,
        dandanplayAnimeTitle: animeTitle ?? '',
      );

      final indexNumber = episodeInfo.indexNumber ?? 0;
      await JellyfinEpisodeMappingService.instance.recordEpisodeMapping(
        jellyfinEpisodeId: episodeInfo.id,
        jellyfinIndexNumber: indexNumber,
        dandanplayEpisodeId: episodeId,
        mappingId: mappingId,
        confirmed: true,
      );
      debugPrint('[WatchHistoryAutoMatch] 已写入Jellyfin映射: episode=${episodeInfo.id}, danmakuEpisode=$episodeId');
    } catch (e) {
      debugPrint('[WatchHistoryAutoMatch] 保存Jellyfin映射失败: $e');
    }
  }

  static Future<void> _recordEmbyMapping(
    String filePath, {
    required int animeId,
    required int episodeId,
    required String? animeTitle,
  }) async {
    final embyService = EmbyService.instance;
    if (!embyService.isConnected) {
      debugPrint('[WatchHistoryAutoMatch] Emby未连接，跳过映射写入');
      return;
    }

    final embyEpisodeId = _extractServerEpisodeId(filePath, 'emby://');
    if (embyEpisodeId == null) {
      return;
    }

    try {
      final episodeInfo = await embyService.getEpisodeDetails(embyEpisodeId);
      if (episodeInfo == null) {
        debugPrint('[WatchHistoryAutoMatch] 无法获取Emby剧集详情，跳过映射写入');
        return;
      }

      final seriesId = episodeInfo.seriesId;
      if (seriesId == null || seriesId.isEmpty) {
        debugPrint('[WatchHistoryAutoMatch] Emby剧集缺少seriesId，无法写入映射');
        return;
      }

      final mappingId = await EmbyEpisodeMappingService.instance.createOrUpdateAnimeMapping(
        embySeriesId: seriesId,
        embySeriesName: episodeInfo.seriesName ?? '',
        embySeasonId: episodeInfo.seasonId,
        dandanplayAnimeId: animeId,
        dandanplayAnimeTitle: animeTitle ?? '',
      );

      final indexNumber = episodeInfo.indexNumber ?? 0;
      await EmbyEpisodeMappingService.instance.recordEpisodeMapping(
        embyEpisodeId: episodeInfo.id,
        embyIndexNumber: indexNumber,
        dandanplayEpisodeId: episodeId,
        mappingId: mappingId,
        confirmed: true,
      );
      debugPrint('[WatchHistoryAutoMatch] 已写入Emby映射: episode=${episodeInfo.id}, danmakuEpisode=$episodeId');
    } catch (e) {
      debugPrint('[WatchHistoryAutoMatch] 保存Emby映射失败: $e');
    }
  }

  static String? _extractServerEpisodeId(String filePath, String prefix) {
    if (!filePath.startsWith(prefix)) {
      return null;
    }
    final raw = filePath.substring(prefix.length);
    if (raw.isEmpty) {
      return null;
    }
    final segments = raw.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.isEmpty) {
      return null;
    }
    return segments.last;
  }
}
