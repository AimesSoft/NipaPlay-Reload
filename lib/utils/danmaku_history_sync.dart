import 'package:nipaplay/models/watch_history_model.dart';

/// 同步弹幕信息到观看历史记录
///
/// 用于在匹配弹幕成功后更新本地观看历史记录，确保历史记录包含准确的弹幕信息
class DanmakuHistorySync {
  static final DanmakuHistorySync instance = DanmakuHistorySync._internal();
  
  DanmakuHistorySync._internal();

  /// 更新历史记录中的弹幕信息
  /// 
  /// [videoPath] 视频文件路径
  /// [animeId] 动画ID
  /// [episodeId] 剧集ID
  /// [animeTitle] 动画标题（可选）
  /// [episodeTitle] 剧集标题（可选）
  static Future<void> updateHistoryWithDanmakuInfo({
    required String videoPath,
    required String animeId,
    required String episodeId,
    String? animeTitle,
    String? episodeTitle,
  }) async {
    try {
      final animeIdInt = int.tryParse(animeId);
      final episodeIdInt = int.tryParse(episodeId);
      
      if (animeIdInt == null || episodeIdInt == null) {
        throw Exception('Invalid anime or episode ID');
      }

      // 获取现有历史记录
      final existingHistory = await WatchHistoryManager.getHistoryItem(videoPath);

      WatchHistoryItem updatedHistory;
      if (existingHistory == null) {
        // 创建新历史记录
        updatedHistory = WatchHistoryItem(
          filePath: videoPath,
          animeName: animeTitle ?? 'Unknown',
          episodeTitle: episodeTitle ?? 'Unknown',
          lastPosition: 0,
          duration: 0,
          lastWatchTime: DateTime.now(),
          animeId: animeIdInt,
          episodeId: episodeIdInt,
          watchProgress: 0.0,
          thumbnailPath: null,
        );
      } else {
        // 更新现有记录
        updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: animeTitle ?? existingHistory.animeName,
          episodeTitle: episodeTitle ?? existingHistory.episodeTitle,
          lastPosition: existingHistory.lastPosition,
          duration: existingHistory.duration,
          lastWatchTime: existingHistory.lastWatchTime,
          animeId: animeIdInt,
          episodeId: episodeIdInt,
          watchProgress: existingHistory.watchProgress,
          thumbnailPath: existingHistory.thumbnailPath,
        );
      }

      // 直接通过WatchHistoryManager更新
      await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
    } catch (e) {
      // 静默处理错误，不影响主流程
    }
  }
}
