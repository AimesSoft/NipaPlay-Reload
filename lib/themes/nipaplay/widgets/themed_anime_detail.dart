import 'package:flutter/material.dart' as material;
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';

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
  }) {
    return AnimeDetailPage.show(
      context,
      animeId,
      sharedSummary: sharedSummary,
      sharedEpisodeLoader: sharedEpisodeLoader,
      sharedEpisodeBuilder: sharedEpisodeBuilder,
      sharedSourceLabel: sharedSourceLabel,
    );
  }
}
