import 'package:flutter/material.dart';
import 'package:nipaplay/services/plugin_playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/services/external_player_console_window_service.dart';
import 'package:nipaplay/services/external_player_service.dart';
import 'package:nipaplay/services/playback_source_service.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';

class PlaybackService {
  static final PlaybackService _instance = PlaybackService._internal();

  factory PlaybackService() {
    return _instance;
  }

  PlaybackService._internal();

  /// Returns true when the request is handled, including chooser cancellation
  /// or internal fallback after an external launch failure.
  Future<bool> tryPlayExternally(BuildContext context, PlayableItem item,
      {bool episodeFileSelectionHandled = false}) async {
    // 检查设置是否允许使用外部播放器
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (!settings.useExternalPlayer) return false;

    if (!episodeFileSelectionHandled) {
      final selected = await EpisodeFileSelectionService.select(context, item);
      if (selected == null || !context.mounted) return true;
      item = selected;
    }

    if (item.actualPlayUrl == null &&
        (item.videoPath.startsWith('https://') ||
            item.videoPath.startsWith('http://'))) {
      item = await PluginPlaybackService.prepare(
            context,
            item.videoPath,
            interactive: false,
            historyItem: item.historyItem,
          ) ??
          item;
      if (!context.mounted) return false;
    }
    final launched = await ExternalPlayerService.play(settings, item);
    if (!launched) {
      // Keep the chosen file when callers would otherwise retry the old item.
      final playbackContext = globals.navigatorKey.currentContext ?? context;
      if (playbackContext.mounted) {
        AnimeDetailPage.popIfOpen();
        await _playInternally(playbackContext, item);
      }
      return true;
    }
    if (settings.externalPlayerConsoleWindowMode) {
      await ExternalPlayerConsoleWindowService.instance.showControlsWindow();
    } else if (settings.externalPlayerAutoSwitchToDanmakuConsole &&
        context.mounted) {
      Provider.of<TabChangeNotifier>(context, listen: false)
          .changePage(AppPageIds.externalPlayerConsole);
    }
    return true;
  }

  /// 播放 [item], 如果设置了使用外部播放器则尝试使用外部播放器播放, 否则使用内置播放器播放.
  Future<bool> play(PlayableItem item,
      {bool episodeFileSelectionHandled = false}) async {
    final context = globals.navigatorKey.currentContext;
    if (context == null) {
      debugPrint("PlaybackService: Navigator context is null, cannot play.");
      return false;
    }

    if (!episodeFileSelectionHandled) {
      final selected = await EpisodeFileSelectionService.select(context, item);
      if (selected == null || !context.mounted) return false;
      item = selected;
    }
    // Cancelling the chooser leaves the detail page and current video intact.
    AnimeDetailPage.popIfOpen();

    if (await tryPlayExternally(context, item,
        episodeFileSelectionHandled: true)) {
      return true;
    }
    if (!context.mounted) return false;
    return _playInternally(context, item);
  }

  Future<bool> _playInternally(BuildContext context, PlayableItem item) async {
    Provider.of<TabChangeNotifier>(context, listen: false)
        .changePage(AppPageIds.video);

    // 等待一小段时间以确保页面切换完成
    await Future.delayed(const Duration(milliseconds: 100));
    if (!context.mounted) return false;

    final detailContext = await PlaybackSourceService.resolve(context, item);
    if (!context.mounted) return false;

    // 2. 显示加载中并准备视频播放
    final videoPlayerState =
        Provider.of<VideoPlayerState>(context, listen: false);
    await videoPlayerState.initializePlayer(
      item.videoPath,
      historyItem: item.historyItem,
      actualPlayUrl: item.actualPlayUrl,
      playbackSession: item.playbackSession,
      playbackDetailContext: detailContext,
      mediaKey: item.mediaKey,
      episodeFileSelectionHandled: true,
    );
    return true;
  }
}
