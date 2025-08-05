import 'package:flutter/material.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import '../main.dart'; // 导入 main.dart 以访问 navigatorKey
import 'package:nipaplay/pages/anime_detail_page.dart';

class PlaybackService {
  static final PlaybackService _instance = PlaybackService._internal();

  factory PlaybackService() {
    return _instance;
  }

  PlaybackService._internal();

  Future<void> play(PlayableItem item) async {
    // 关闭可能存在的番剧详情页
    AnimeDetailPage.popIfOpen();
    
    final context = navigatorKey.currentContext; // 直接使用导入的 navigatorKey
    if (context == null) {
      debugPrint("PlaybackService: Navigator context is null, cannot play.");
      return;
    }

    // 1. 切换回主页面 (Tab 0)
    Provider.of<TabChangeNotifier>(context, listen: false).changeTab(0);

    // 等待一小段时间以确保页面切换完成
    await Future.delayed(const Duration(milliseconds: 100));

    // 2. 显示加载中并准备视频播放
    final videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
    await videoPlayerState.initializePlayer(
      item.videoPath,
      historyItem: item.historyItem,
      actualPlayUrl: item.actualPlayUrl, // <-- 添加这行
    );
  }
}
