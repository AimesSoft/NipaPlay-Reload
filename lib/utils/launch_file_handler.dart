import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:path/path.dart' as path;

class LaunchFileHandler {
  static Future<void> handle(
    String filePath, {
    void Function(String message)? onError,
  }) async {
    try {
      debugPrint('[FileAssociation] 处理启动文件: $filePath');

      WatchHistoryItem? historyItem =
          await WatchHistoryManager.getHistoryItem(filePath);

      historyItem ??= WatchHistoryItem(
        filePath: filePath,
        animeName: path.basenameWithoutExtension(filePath),
        watchProgress: 0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
      );

      final playableItem = PlayableItem(
        videoPath: filePath,
        title: historyItem.animeName,
        historyItem: historyItem,
      );

      await PlaybackService().play(playableItem);
      debugPrint('[FileAssociation] 启动文件已提交给PlaybackService');
    } catch (e) {
      debugPrint('[FileAssociation] 启动文件播放失败: $e');
      onError?.call('无法播放启动文件: $e');
    }
  }
}
