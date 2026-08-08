import 'package:flutter/material.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/services/external_player_service.dart';
import 'package:nipaplay/services/playback_source_service.dart';

class PlaybackService {
  static final PlaybackService _instance = PlaybackService._internal();

  factory PlaybackService() {
    return _instance;
  }

  PlaybackService._internal();

  /// 尝试使用外部播放器播放 [item], 如果成功则返回 true, 否则返回 false.
  Future<bool> tryPlayExternally(BuildContext context, PlayableItem item) async {

    // 检查设置是否允许使用外部播放器
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (!settings.useExternalPlayer) return false;

    await ExternalPlayerService.play(context, item);
    return true;
  }

  /// 播放 [item], 如果设置了使用外部播放器则尝试使用外部播放器播放, 否则使用内置播放器播放.
  Future<void> play(PlayableItem item) async {
    // 关闭可能存在的番剧详情页
    AnimeDetailPage.popIfOpen();

    final context = globals.navigatorKey.currentContext;
    if (context == null) {
      debugPrint("PlaybackService: Navigator context is null, cannot play.");
      return;
    }

    if (await tryPlayExternally(context, item)) {
      return;
    }
    if (!context.mounted) return;

    Provider.of<TabChangeNotifier>(context, listen: false)
        .changePage(AppPageIds.video);

    // 等待一小段时间以确保页面切换完成
    await Future.delayed(const Duration(milliseconds: 100));
    if (!context.mounted) return;

    final detailContext = await PlaybackSourceService.resolve(context, item);
    if (!context.mounted) return;

    // 2. 显示加载中并准备视频播放
    final videoPlayerState =
        Provider.of<VideoPlayerState>(context, listen: false);
    await videoPlayerState.initializePlayer(
      item.videoPath,
      historyItem: item.historyItem,
      actualPlayUrl: item.actualPlayUrl,
      playbackSession: item.playbackSession,
      playbackDetailContext: detailContext,
    );
  }
}
