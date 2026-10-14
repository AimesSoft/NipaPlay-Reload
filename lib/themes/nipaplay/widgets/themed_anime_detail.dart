import 'package:flutter/material.dart' as material;
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay_core/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart';

/// 番剧详情页面的主题适配器
class ThemedAnimeDetail {
  /// 显示番剧详情页面，自动适配当前UI主题
  static Future<WatchHistoryItem?> show(
    material.BuildContext context,
    int animeId, {
    SharedRemoteAnimeSummary? sharedSummary,
    Future<List<SharedRemoteEpisode>> Function()? sharedEpisodeLoader,
    PlayableItem Function(SharedRemoteEpisode episode)? sharedEpisodeBuilder,
    String? sharedSourceLabel,
    PlaybackDetailContext? playbackDetailContext,
  }) {
    // 路由转场期间预热详情缓存（服务层有 in-flight 去重，媒体库卡片
    // 已经请求过时这里不会再发一发）。转场动画约 300ms，缓存命中时
    // 详情页首帧就能拿到数据；冷缓存则相当于把网络等待藏进动画里。
    // 失败静默吞掉——详情页自己还会再取一次并展示错误。
    BangumiService.instance
        .getAnimeDetails(animeId)
        .then((_) {}, onError: (_) {});
    return AnimeDetailPage.show(
      context,
      animeId,
      sharedSummary: sharedSummary,
      sharedEpisodeLoader: sharedEpisodeLoader,
      sharedEpisodeBuilder: sharedEpisodeBuilder,
      sharedSourceLabel: sharedSourceLabel,
      playbackDetailContext: playbackDetailContext,
    );
  }
}
