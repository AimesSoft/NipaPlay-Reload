import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/watch_history_model.dart';
import '../models/watch_history_database.dart';
import '../providers/watch_history_provider.dart';

/// 弹幕历史记录同步工具
/// 
/// 专门处理手动匹配弹幕后同步更新观看历史记录的工具类
class DanmakuHistorySync {
  static final DanmakuHistorySync instance = DanmakuHistorySync._internal();
  
  DanmakuHistorySync._internal();

  /// 更新历史记录中的弹幕信息
  /// 
  /// 当用户手动匹配弹幕后，需要同步更新历史记录中的相关信息
  /// [context] - BuildContext，用于访问Provider
  /// [videoPath] - 视频文件路径
  /// [animeId] - 新的动画ID
  /// [episodeId] - 新的剧集ID
  /// [animeTitle] - 新的动画标题（可选）
  /// [episodeTitle] - 新的剧集标题（可选）
  Future<bool> updateHistoryWithDanmakuInfo(
    BuildContext context,
    String videoPath, {
    required int animeId,
    required int episodeId,
    String? animeTitle,
    String? episodeTitle,
  }) async {
    try {
      debugPrint('开始更新历史记录中的弹幕信息: videoPath=$videoPath, animeId=$animeId, episodeId=$episodeId');
      debugPrint('新的动画信息: animeTitle="$animeTitle", episodeTitle="$episodeTitle"');
      
      // 获取现有的历史记录
      WatchHistoryItem? existingHistory;
      
      if (context.mounted) {
        final watchHistoryProvider = context.read<WatchHistoryProvider>();
        existingHistory = await watchHistoryProvider.getHistoryItem(videoPath);
      } else {
        existingHistory = await WatchHistoryDatabase.instance.getHistoryByFilePath(videoPath);
      }
      
      if (existingHistory == null) {
        debugPrint('未找到现有历史记录: $videoPath');
        return false;
      }

      debugPrint('找到现有历史记录: ${existingHistory.animeName} - ${existingHistory.episodeTitle}');
      debugPrint('原有弹幕ID: animeId=${existingHistory.animeId}, episodeId=${existingHistory.episodeId}');

      // 创建更新后的历史记录
      // 优先使用手动匹配的信息，如果没有提供则保留原有信息
      final updatedHistory = WatchHistoryItem(
        filePath: existingHistory.filePath,
        animeName: animeTitle?.isNotEmpty == true ? animeTitle! : existingHistory.animeName,
        episodeTitle: episodeTitle?.isNotEmpty == true ? episodeTitle : existingHistory.episodeTitle,
        episodeId: episodeId, // 更新为新的弹幕ID
        animeId: animeId, // 更新为新的弹幕ID
        watchProgress: existingHistory.watchProgress,
        lastPosition: existingHistory.lastPosition,
        duration: existingHistory.duration,
        lastWatchTime: DateTime.now(), // 更新最后修改时间，表示记录已被更新
        thumbnailPath: existingHistory.thumbnailPath,
        isFromScan: existingHistory.isFromScan,
        videoHash: existingHistory.videoHash,
      );

      // 保存更新后的记录
      if (context.mounted) {
        await context.read<WatchHistoryProvider>().addOrUpdateHistory(updatedHistory);
        debugPrint('通过Provider成功更新历史记录中的弹幕信息');
      } else {
        await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(updatedHistory);
        debugPrint('通过数据库直接更新历史记录中的弹幕信息');
      }
      
      debugPrint('成功更新历史记录:');
      debugPrint('  动画名称: ${existingHistory.animeName} -> ${updatedHistory.animeName}');
      debugPrint('  剧集标题: ${existingHistory.episodeTitle} -> ${updatedHistory.episodeTitle}');
      debugPrint('  动画ID: ${existingHistory.animeId} -> ${updatedHistory.animeId}');
      debugPrint('  剧集ID: ${existingHistory.episodeId} -> ${updatedHistory.episodeId}');
      
      return true;
    } catch (e, stackTrace) {
      debugPrint('更新历史记录中的弹幕信息时出错: $e');
      debugPrint('错误堆栈: $stackTrace');
      return false;
    }
  }

  /// 更新历史记录中的弹幕信息（无Context版本）
  /// 
  /// 当无法访问BuildContext时的备用方法
  /// [videoPath] - 视频文件路径
  /// [animeId] - 新的动画ID
  /// [episodeId] - 新的剧集ID
  /// [animeTitle] - 新的动画标题（可选）
  /// [episodeTitle] - 新的剧集标题（可选）
  Future<bool> updateHistoryWithDanmakuInfoDirect(
    String videoPath, {
    required int animeId,
    required int episodeId,
    String? animeTitle,
    String? episodeTitle,
  }) async {
    try {
      debugPrint('直接更新历史记录中的弹幕信息: videoPath=$videoPath, animeId=$animeId, episodeId=$episodeId');
      
      // 直接从数据库获取现有记录
      final existingHistory = await WatchHistoryDatabase.instance.getHistoryByFilePath(videoPath);
      
      if (existingHistory == null) {
        debugPrint('未找到现有历史记录: $videoPath');
        return false;
      }

      debugPrint('找到现有历史记录: ${existingHistory.animeName} - ${existingHistory.episodeTitle}');

      // 创建更新后的历史记录
      final updatedHistory = WatchHistoryItem(
        filePath: existingHistory.filePath,
        animeName: animeTitle?.isNotEmpty == true ? animeTitle! : existingHistory.animeName,
        episodeTitle: episodeTitle?.isNotEmpty == true ? episodeTitle : existingHistory.episodeTitle,
        episodeId: episodeId,
        animeId: animeId,
        watchProgress: existingHistory.watchProgress,
        lastPosition: existingHistory.lastPosition,
        duration: existingHistory.duration,
        lastWatchTime: DateTime.now(),
        thumbnailPath: existingHistory.thumbnailPath,
        isFromScan: existingHistory.isFromScan,
        videoHash: existingHistory.videoHash,
      );

      // 直接保存到数据库
      await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(updatedHistory);
      
      debugPrint('直接通过数据库成功更新历史记录中的弹幕信息');
      debugPrint('  动画名称: ${existingHistory.animeName} -> ${updatedHistory.animeName}');
      debugPrint('  剧集标题: ${existingHistory.episodeTitle} -> ${updatedHistory.episodeTitle}');
      debugPrint('  动画ID: ${existingHistory.animeId} -> ${updatedHistory.animeId}');
      debugPrint('  剧集ID: ${existingHistory.episodeId} -> ${updatedHistory.episodeId}');
      
      return true;
    } catch (e, stackTrace) {
      debugPrint('直接更新历史记录中的弹幕信息时出错: $e');
      debugPrint('错误堆栈: $stackTrace');
      return false;
    }
  }

  /// 批量更新多个视频的弹幕信息
  /// 
  /// 用于批量处理多个视频的弹幕匹配更新
  /// [updates] - 更新信息列表，每个包含videoPath和弹幕信息
  Future<List<bool>> batchUpdateHistoryWithDanmakuInfo(
    BuildContext context,
    List<Map<String, dynamic>> updates,
  ) async {
    final results = <bool>[];
    
    for (final update in updates) {
      final videoPath = update['videoPath'] as String?;
      final animeId = update['animeId'] as int?;
      final episodeId = update['episodeId'] as int?;
      final animeTitle = update['animeTitle'] as String?;
      final episodeTitle = update['episodeTitle'] as String?;
      
      if (videoPath == null || animeId == null || episodeId == null) {
        debugPrint('批量更新：跳过无效的更新项: $update');
        results.add(false);
        continue;
      }
      
      final success = await updateHistoryWithDanmakuInfo(
        context,
        videoPath,
        animeId: animeId,
        episodeId: episodeId,
        animeTitle: animeTitle,
        episodeTitle: episodeTitle,
      );
      
      results.add(success);
    }
    
    final successCount = results.where((r) => r).length;
    debugPrint('批量更新完成: $successCount/${results.length} 个项目更新成功');
    
    return results;
  }

  /// 检查视频的弹幕信息是否需要更新
  /// 
  /// 用于判断历史记录中的弹幕信息是否与当前实际使用的弹幕信息不一致
  /// [videoPath] - 视频文件路径
  /// [currentAnimeId] - 当前使用的动画ID
  /// [currentEpisodeId] - 当前使用的剧集ID
  Future<bool> isDanmakuInfoOutOfSync(
    String videoPath,
    int? currentAnimeId,
    int? currentEpisodeId,
  ) async {
    try {
      final existingHistory = await WatchHistoryDatabase.instance.getHistoryByFilePath(videoPath);
      
      if (existingHistory == null) {
        debugPrint('检查同步状态：未找到历史记录: $videoPath');
        return false;
      }
      
      final isOutOfSync = existingHistory.animeId != currentAnimeId || 
                         existingHistory.episodeId != currentEpisodeId;
      
      if (isOutOfSync) {
        debugPrint('检测到弹幕信息不同步:');
        debugPrint('  历史记录: animeId=${existingHistory.animeId}, episodeId=${existingHistory.episodeId}');
        debugPrint('  当前使用: animeId=$currentAnimeId, episodeId=$currentEpisodeId');
      }
      
      return isOutOfSync;
    } catch (e) {
      debugPrint('检查弹幕信息同步状态时出错: $e');
      return false;
    }
  }

  /// 修复所有不同步的历史记录
  /// 
  /// 扫描所有历史记录，找出弹幕信息不同步的项目并尝试修复
  /// [context] - BuildContext，用于访问Provider
  Future<int> fixAllOutOfSyncHistories(BuildContext context) async {
    try {
      debugPrint('开始扫描并修复不同步的历史记录...');
      
      List<WatchHistoryItem> allHistories;
      if (context.mounted) {
        final provider = context.read<WatchHistoryProvider>();
        allHistories = provider.history;
      } else {
        allHistories = await WatchHistoryDatabase.instance.getAllWatchHistory();
      }
      
      int fixedCount = 0;
      
      for (final history in allHistories) {
        // 这里可以添加具体的修复逻辑
        // 例如重新匹配弹幕信息或清理无效的ID
        
        // 简单的验证：如果animeId和episodeId都为空或无效，可能需要重新匹配
        if ((history.animeId == null || history.animeId == 0) && 
            (history.episodeId == null || history.episodeId == 0)) {
          debugPrint('发现可能需要重新匹配弹幕的历史记录: ${history.animeName}');
          // 这里可以触发重新匹配逻辑
        }
      }
      
      debugPrint('历史记录同步检查完成，修复了 $fixedCount 个项目');
      return fixedCount;
    } catch (e) {
      debugPrint('修复历史记录同步时出错: $e');
      return 0;
    }
  }
}
