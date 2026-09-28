import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/plugins/url_resolver.dart';
import 'package:nipaplay/services/manual_danmaku_matcher.dart';
import 'package:nipaplay/services/plugin_media_proxy.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/plugin_url_selection_content.dart';

class PluginPlaybackService {
  static Future<PlayableItem?> prepare(
    BuildContext context,
    String input, {
    bool interactive = true,
    WatchHistoryItem? historyItem,
    bool Function()? isCancelled,
  }) async {
    if (kIsWeb) return null;
    bool cancelled() => !context.mounted || (isCancelled?.call() ?? false);
    final result = await context.read<PluginService>().resolveUrl(
      input,
      isCancelled: cancelled,
      select: (title, items, preferredId) async {
        if (!context.mounted || cancelled()) {
          throw const PluginResolutionCancelled();
        }
        if (items.length == 1) return items.single.id;
        if (!interactive &&
            preferredId != null &&
            items.any((item) => item.id == preferredId)) {
          return preferredId;
        }
        return BlurDialog.show<String>(
          context: context,
          title: '选择分集',
          contentWidget: PluginUrlSelectionContent(
            title: title,
            items: items,
            preferredId: preferredId,
          ),
        );
      },
    );
    if (result == null) return null;
    if (!context.mounted || cancelled() || !result.isActive()) {
      throw const PluginResolutionCancelled();
    }
    Map<String, dynamic>? match;
    if (interactive &&
        !context.read<SettingsProvider>().skipDanmakuMatching &&
        result.searchTitle?.trim().isNotEmpty == true) {
      match = await ManualDanmakuMatcher.showMatchDialog(
        context,
        initialVideoTitle: result.searchTitle,
        searchOnOpen: true,
      );
    }
    if (!context.mounted || cancelled() || !result.isActive()) {
      throw const PluginResolutionCancelled();
    }
    final resolvedHistory = WatchHistoryItem(
      filePath: result.sourceUrl,
      animeName: match?['animeTitle']?.toString() ??
          historyItem?.animeName ??
          result.title,
      episodeTitle:
          match?['episodeTitle']?.toString() ?? historyItem?.episodeTitle,
      animeId: int.tryParse(match?['animeId']?.toString() ?? '') ??
          historyItem?.animeId,
      episodeId: int.tryParse(match?['episodeId']?.toString() ?? '') ??
          historyItem?.episodeId,
      watchProgress: historyItem?.watchProgress ?? 0,
      lastPosition: historyItem?.lastPosition ?? 0,
      duration: historyItem?.duration ?? 0,
      lastWatchTime: DateTime.now(),
      thumbnailPath: historyItem?.thumbnailPath,
    );
    final playUrl =
        await PluginMediaProxy.instance.register(result.url, result.headers);
    if (!context.mounted || cancelled() || !result.isActive()) {
      throw const PluginResolutionCancelled();
    }
    return PlayableItem(
      videoPath: result.sourceUrl,
      actualPlayUrl: playUrl,
      title: resolvedHistory.animeName,
      subtitle: resolvedHistory.episodeTitle,
      animeId: resolvedHistory.animeId,
      episodeId: resolvedHistory.episodeId,
      historyItem: resolvedHistory,
    );
  }
}
