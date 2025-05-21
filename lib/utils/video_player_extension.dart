// 为VideoPlayerState添加扩展功能，以便处理流媒体URL

import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/models/watch_history_model.dart';

/// 扩展VideoPlayerState类，添加对流媒体URL的支持
extension VideoPlayerStateExtension on VideoPlayerState {
  /// 播放流媒体URL
  /// 
  /// [streamUrl] 流媒体URL，通常是Jellyfin服务器返回的直接播放链接
  /// [historyItem] 与此视频关联的观看历史记录项
  /// [isJellyfin] 是否是来自Jellyfin的流（默认为true）
  Future<void> playStreamUrl(String streamUrl, {
    required WatchHistoryItem historyItem,
    bool isJellyfin = true
  }) async {
    try {
      debugPrint('准备播放流媒体: $streamUrl');
      debugPrint('历史记录: ${historyItem.animeName} - ${historyItem.episodeTitle}, animeId=${historyItem.animeId}, episodeId=${historyItem.episodeId}');
      
      // 创建一个新的WatchHistoryItem，确保filePath是实际的流媒体URL
      final playableHistoryItem = WatchHistoryItem(
        filePath: streamUrl,  // 直接使用流媒体URL
        animeName: historyItem.animeName,
        episodeTitle: historyItem.episodeTitle,
        episodeId: historyItem.episodeId,
        animeId: historyItem.animeId,
        watchProgress: historyItem.watchProgress,
        lastPosition: historyItem.lastPosition,
        duration: historyItem.duration,
        lastWatchTime: historyItem.lastWatchTime,
        thumbnailPath: historyItem.thumbnailPath,
        isFromScan: historyItem.isFromScan,
      );
      
      // 如果是Jellyfin流媒体，尝试额外的元数据提取
      if (isJellyfin && streamUrl.contains('jellyfin') && streamUrl.contains('/Videos/')) {
        try {
          debugPrint('检测到Jellyfin流媒体，尝试额外的元数据提取');
          final metadata = await JellyfinDandanplayMatcher.instance.extractMetadataFromStreamUrl(streamUrl);
          
          if (metadata['success'] == true) {
            debugPrint('成功从URL提取额外元数据: ${metadata['seriesName']} - ${metadata['episodeTitle']}');
          }
        } catch (metadataError) {
          debugPrint('元数据提取失败，继续使用原始数据: $metadataError');
          // 元数据提取失败不应阻止播放
        }
      }
      
      // 使用VideoPlayerState的initializePlayer方法初始化
      debugPrint('正在初始化播放器...');
      await initializePlayer(streamUrl, historyItem: playableHistoryItem);
      
      // 开始播放
      debugPrint('开始播放.');
      play();
    } catch (e) {
      debugPrint('播放流媒体URL失败: $e');
      rethrow;
    }
  }
}
