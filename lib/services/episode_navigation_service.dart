import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';
import 'package:nipaplay/services/emby_episode_mapping_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';

/// 剧集导航结果
class EpisodeNavigationResult {
  final String? filePath;
  final WatchHistoryItem? historyItem;
  final String message;
  final bool success;

  EpisodeNavigationResult({
    this.filePath,
    this.historyItem,
    required this.message,
    required this.success,
  });

  EpisodeNavigationResult.success({
    this.filePath,
    this.historyItem,
    String? message,
  }) : message = message ?? '找到了可播放的剧集',
       success = true;

  EpisodeNavigationResult.failure(this.message)
      : filePath = null,
        historyItem = null,
        success = false;
}

/// 剧集导航服务
/// 支持两种导航模式，按优先级排序：
/// 1. 文件系统模式：基于文件路径排序（优先）
/// 2. 数据库模式：基于观看历史中的剧集列表（回退）
/// 
/// 使用示例：
/// ```dart
/// final navigationService = EpisodeNavigationService.instance;
/// 
/// // 获取上一话（优先从文件系统查找，如果失败则从数据库查找）
/// final result = await navigationService.getPreviousEpisode(
///   currentFilePath: '/path/to/current/video.mp4',
///   animeId: 123,      // 可选：如果有剧集信息
///   episodeId: 5,      // 可选：如果有剧集信息
/// );
/// 
/// if (result.success) {
///   if (result.historyItem != null) {
///     // 从数据库找到的剧集（包含完整历史信息）
///     print('找到上一话：${result.historyItem!.episodeTitle}');
///     // 使用 result.historyItem!.filePath 播放
///   } else if (result.filePath != null) {
///     // 从文件系统找到的文件（仅文件路径）
///     print('找到上一个文件：${result.filePath}');
///     // 使用 result.filePath 播放
///   }
/// } else {
///   print('未找到上一话：${result.message}');
/// }
/// ```
class EpisodeNavigationService {
  static final EpisodeNavigationService _instance = EpisodeNavigationService._internal();
  factory EpisodeNavigationService() => _instance;
  EpisodeNavigationService._internal();

  static EpisodeNavigationService get instance => _instance;

  /// 获取上一话
  Future<EpisodeNavigationResult> getPreviousEpisode({
    required String currentFilePath,
    int? animeId,
    int? episodeId,
  }) async {
    debugPrint('[剧集导航] 开始获取上一话：$currentFilePath, animeId=$animeId, episodeId=$episodeId');

    // 检查是否为Jellyfin流媒体，如果是则使用Jellyfin专用导航
    if (_isJellyfinUrl(currentFilePath)) {
      final jellyfinResult = await _getPreviousEpisodeFromJellyfin(currentFilePath, animeId, episodeId);
      if (jellyfinResult.success) {
        debugPrint('[剧集导航] Jellyfin模式成功找到上一话');
        return jellyfinResult;
      }
      debugPrint('[剧集导航] Jellyfin模式未找到上一话，原因：${jellyfinResult.message}');
    }

    // 检查是否为Emby流媒体，如果是则使用Emby专用导航
    if (_isEmbyUrl(currentFilePath)) {
      final embyResult = await _getPreviousEpisodeFromEmby(currentFilePath, animeId, episodeId);
      if (embyResult.success) {
        debugPrint('[剧集导航] Emby模式成功找到上一话');
        return embyResult;
      }
      debugPrint('[剧集导航] Emby模式未找到上一话，原因：${embyResult.message}');
    }

    // 模式1：优先尝试基于文件系统的导航
    final fileSystemResult = await _getPreviousEpisodeFromFileSystem(currentFilePath);
    if (fileSystemResult.success) {
      debugPrint('[剧集导航] 文件系统模式成功找到上一话');
      return fileSystemResult;
    }
    debugPrint('[剧集导航] 文件系统模式未找到上一话，原因：${fileSystemResult.message}');

    // 模式2：回退到基于数据库的剧集列表导航
    if (animeId != null && episodeId != null) {
      final databaseResult = await _getPreviousEpisodeFromDatabase(animeId, episodeId);
      if (databaseResult.success) {
        debugPrint('[剧集导航] 数据库模式成功找到上一话');
        return databaseResult;
      }
      debugPrint('[剧集导航] 数据库模式也未找到上一话');
    }

    debugPrint('[剧集导航] 所有模式都未找到上一话');
    return EpisodeNavigationResult.failure('没有找到可播放的上一话');
  }

  /// 获取下一话
  Future<EpisodeNavigationResult> getNextEpisode({
    required String currentFilePath,
    int? animeId,
    int? episodeId,
  }) async {
    debugPrint('[剧集导航] 开始获取下一话：$currentFilePath, animeId=$animeId, episodeId=$episodeId');

    // 检查是否为Jellyfin流媒体，如果是则使用Jellyfin专用导航
    if (_isJellyfinUrl(currentFilePath)) {
      final jellyfinResult = await _getNextEpisodeFromJellyfin(currentFilePath, animeId, episodeId);
      if (jellyfinResult.success) {
        debugPrint('[剧集导航] Jellyfin模式成功找到下一话');
        return jellyfinResult;
      }
      debugPrint('[剧集导航] Jellyfin模式未找到下一话，原因：${jellyfinResult.message}');
    }

    // 检查是否为Emby流媒体，如果是则使用Emby专用导航
    if (_isEmbyUrl(currentFilePath)) {
      final embyResult = await _getNextEpisodeFromEmby(currentFilePath, animeId, episodeId);
      if (embyResult.success) {
        debugPrint('[剧集导航] Emby模式成功找到下一话');
        return embyResult;
      }
      debugPrint('[剧集导航] Emby模式未找到下一话，原因：${embyResult.message}');
    }

    // 模式1：优先尝试基于文件系统的导航
    final fileSystemResult = await _getNextEpisodeFromFileSystem(currentFilePath);
    if (fileSystemResult.success) {
      debugPrint('[剧集导航] 文件系统模式成功找到下一话');
      return fileSystemResult;
    }
    debugPrint('[剧集导航] 文件系统模式未找到下一话，原因：${fileSystemResult.message}');

    // 模式2：回退到基于数据库的剧集列表导航
    if (animeId != null && episodeId != null) {
      final databaseResult = await _getNextEpisodeFromDatabase(animeId, episodeId);
      if (databaseResult.success) {
        debugPrint('[剧集导航] 数据库模式成功找到下一话');
        return databaseResult;
      }
      debugPrint('[剧集导航] 数据库模式也未找到下一话');
    }

    debugPrint('[剧集导航] 所有模式都未找到下一话');
    return EpisodeNavigationResult.failure('没有找到可播放的下一话');
  }

  /// 模式2：从数据库获取上一话（回退模式）
  Future<EpisodeNavigationResult> _getPreviousEpisodeFromDatabase(int animeId, int episodeId) async {
    try {
      // 首先尝试使用映射服务查找上一集
      // 检查是否为Emby映射
      final embyMapping = await EmbyEpisodeMappingService.instance.getPreviousEpisodeMappingByDanmakuIds(
        currentAnimeId: animeId,
        currentEpisodeId: episodeId,
      );

      if (embyMapping != null) {
        final previousEmbyIndexNumber = embyMapping['emby_index_number'] as int?;
        final previousDandanplayEpisodeId = embyMapping['dandanplay_episode_id'] as int?;
        final previousDandanplayAnimeId = embyMapping['dandanplay_anime_id'] as int?;
        final seriesId = embyMapping['emby_series_id'] as String?;
        final seasonId = embyMapping['emby_season_id'] as String?;

        if (previousEmbyIndexNumber != null && previousDandanplayEpisodeId != null && seriesId != null && seasonId != null) {
          debugPrint('[数据库导航] 通过Emby映射服务找到上一集: 第$previousEmbyIndexNumber集，弹幕ID=$previousDandanplayEpisodeId，动画ID=$previousDandanplayAnimeId');
          
          // 通过Emby API获取上一集的详细信息
          try {
            final episodes = await EmbyService.instance.getSeasonEpisodes(seriesId, seasonId);
            final matchingEpisodes = episodes.where((ep) => ep.indexNumber == previousEmbyIndexNumber).toList();
            final previousEpisode = matchingEpisodes.isNotEmpty ? matchingEpisodes.first : null;
            
            if (previousEpisode != null) {
              // 使用上一集的正确动画ID和剧集ID创建历史项
              final historyItem = await _createEmbyHistoryItem(previousEpisode, previousDandanplayAnimeId ?? animeId, previousDandanplayEpisodeId);
              
              debugPrint('[数据库导航] 成功创建上一集历史项: ${previousEpisode.name}，使用弹幕ID: animeId=${previousDandanplayAnimeId ?? animeId}, episodeId=$previousDandanplayEpisodeId');
              return EpisodeNavigationResult.success(
                historyItem: historyItem,
                message: '从Emby映射服务找到上一话：${previousEpisode.name}',
              );
            }
          } catch (e) {
            debugPrint('[数据库导航] 获取Emby剧集详情失败: $e');
          }
        }
      }

      // 尝试Jellyfin映射服务
      final jellyfinMapping = await JellyfinEpisodeMappingService.instance.getPreviousEpisodeMappingByDanmakuIds(
        currentAnimeId: animeId,
        currentEpisodeId: episodeId,
      );

      if (jellyfinMapping != null) {
        final previousJellyfinIndexNumber = jellyfinMapping['jellyfin_index_number'] as int?;
        final previousDandanplayEpisodeId = jellyfinMapping['dandanplay_episode_id'] as int?;
        final previousDandanplayAnimeId = jellyfinMapping['dandanplay_anime_id'] as int?;
        final seriesId = jellyfinMapping['jellyfin_series_id'] as String?;
        final seasonId = jellyfinMapping['jellyfin_season_id'] as String?;

        if (previousJellyfinIndexNumber != null && previousDandanplayEpisodeId != null && seriesId != null && seasonId != null) {
          debugPrint('[数据库导航] 通过Jellyfin映射服务找到上一集: 第$previousJellyfinIndexNumber集，弹幕ID=$previousDandanplayEpisodeId，动画ID=$previousDandanplayAnimeId');
          
          // 通过Jellyfin API获取上一集的详细信息
          try {
            final episodes = await JellyfinService.instance.getSeasonEpisodes(seriesId, seasonId);
            final matchingEpisodes = episodes.where((ep) => ep.indexNumber == previousJellyfinIndexNumber).toList();
            final previousEpisode = matchingEpisodes.isNotEmpty ? matchingEpisodes.first : null;
            
            if (previousEpisode != null) {
              // 使用上一集的正确动画ID和剧集ID创建历史项
              final historyItem = await _createJellyfinHistoryItem(previousEpisode, previousDandanplayAnimeId ?? animeId, previousDandanplayEpisodeId);
              
              debugPrint('[数据库导航] 成功创建上一集历史项: ${previousEpisode.name}，使用弹幕ID: animeId=${previousDandanplayAnimeId ?? animeId}, episodeId=$previousDandanplayEpisodeId');
              return EpisodeNavigationResult.success(
                historyItem: historyItem,
                message: '从Jellyfin映射服务找到上一话：${previousEpisode.name}',
              );
            }
          } catch (e) {
            debugPrint('[数据库导航] 获取Jellyfin剧集详情失败: $e');
          }
        }
      }

      // 回退到原有的数据库导航逻辑
      final database = WatchHistoryDatabase.instance;
      
      // 获取该动画的所有剧集列表，按episode_id排序
      final allEpisodes = await database.getHistoryByAnimeId(animeId);
      
      if (allEpisodes.isEmpty) {
        return EpisodeNavigationResult.failure('数据库中没有该动画的剧集记录');
      }
      
      // 找到当前剧集在列表中的位置
      int currentIndex = -1;
      for (int i = 0; i < allEpisodes.length; i++) {
        if (allEpisodes[i].episodeId == episodeId) {
          currentIndex = i;
          break;
        }
      }
      
      if (currentIndex == -1) {
        debugPrint('[数据库导航] 当前剧集不在列表中：episodeId=$episodeId');
        return EpisodeNavigationResult.failure('当前剧集不在数据库列表中');
      }
      
      // 从当前位置向前查找可播放的剧集
      for (int i = currentIndex - 1; i >= 0; i--) {
        final episode = allEpisodes[i];
        if (await _checkFileExists(episode.filePath)) {
          debugPrint('[数据库导航] 找到上一话：${episode.episodeTitle} (索引位置: $i)');
          return EpisodeNavigationResult.success(
            historyItem: episode,
            message: '从剧集列表找到上一话：${episode.episodeTitle}',
          );
        } else {
          debugPrint('[数据库导航] 文件不存在，跳过：${episode.filePath}');
        }
      }

      return EpisodeNavigationResult.failure('数据库中没有找到可播放的上一话');
    } catch (e) {
      debugPrint('[数据库导航] 获取上一话时出错：$e');
      return EpisodeNavigationResult.failure('数据库查询出错：$e');
    }
  }

  /// 模式2：从数据库获取下一话（回退模式）
  Future<EpisodeNavigationResult> _getNextEpisodeFromDatabase(int animeId, int episodeId) async {
    try {
      // 首先尝试使用映射服务查找下一集
      // 检查是否为Emby映射
      final embyMapping = await EmbyEpisodeMappingService.instance.getNextEpisodeMappingByDanmakuIds(
        currentAnimeId: animeId,
        currentEpisodeId: episodeId,
      );

      if (embyMapping != null) {
        final nextEmbyIndexNumber = embyMapping['emby_index_number'] as int?;
        final nextDandanplayEpisodeId = embyMapping['dandanplay_episode_id'] as int?;
        final nextDandanplayAnimeId = embyMapping['dandanplay_anime_id'] as int?;
        final seriesId = embyMapping['emby_series_id'] as String?;
        final seasonId = embyMapping['emby_season_id'] as String?;

        if (nextEmbyIndexNumber != null && nextDandanplayEpisodeId != null && seriesId != null && seasonId != null) {
          debugPrint('[数据库导航] 通过Emby映射服务找到下一集: 第$nextEmbyIndexNumber集，弹幕ID=$nextDandanplayEpisodeId，动画ID=$nextDandanplayAnimeId');
          
          // 通过Emby API获取下一集的详细信息
          try {
            final episodes = await EmbyService.instance.getSeasonEpisodes(seriesId, seasonId);
            final matchingEpisodes = episodes.where((ep) => ep.indexNumber == nextEmbyIndexNumber).toList();
            final nextEpisode = matchingEpisodes.isNotEmpty ? matchingEpisodes.first : null;
            
            if (nextEpisode != null) {
              // 使用下一集的正确动画ID和剧集ID创建历史项
              final historyItem = await _createEmbyHistoryItem(nextEpisode, nextDandanplayAnimeId ?? animeId, nextDandanplayEpisodeId);
              
              debugPrint('[数据库导航] 成功创建下一集历史项: ${nextEpisode.name}，使用弹幕ID: animeId=${nextDandanplayAnimeId ?? animeId}, episodeId=$nextDandanplayEpisodeId');
              return EpisodeNavigationResult.success(
                historyItem: historyItem,
                message: '从Emby映射服务找到下一话：${nextEpisode.name}',
              );
            }
          } catch (e) {
            debugPrint('[数据库导航] 获取Emby剧集详情失败: $e');
          }
        }
      }

      // 尝试Jellyfin映射服务
      final jellyfinMapping = await JellyfinEpisodeMappingService.instance.getNextEpisodeMappingByDanmakuIds(
        currentAnimeId: animeId,
        currentEpisodeId: episodeId,
      );

      if (jellyfinMapping != null) {
        final nextJellyfinIndexNumber = jellyfinMapping['jellyfin_index_number'] as int?;
        final nextDandanplayEpisodeId = jellyfinMapping['dandanplay_episode_id'] as int?;
        final nextDandanplayAnimeId = jellyfinMapping['dandanplay_anime_id'] as int?;
        final seriesId = jellyfinMapping['jellyfin_series_id'] as String?;
        final seasonId = jellyfinMapping['jellyfin_season_id'] as String?;

        if (nextJellyfinIndexNumber != null && nextDandanplayEpisodeId != null && seriesId != null && seasonId != null) {
          debugPrint('[数据库导航] 通过Jellyfin映射服务找到下一集: 第$nextJellyfinIndexNumber集，弹幕ID=$nextDandanplayEpisodeId，动画ID=$nextDandanplayAnimeId');
          
          // 通过Jellyfin API获取下一集的详细信息
          try {
            final episodes = await JellyfinService.instance.getSeasonEpisodes(seriesId, seasonId);
            final matchingEpisodes = episodes.where((ep) => ep.indexNumber == nextJellyfinIndexNumber).toList();
            final nextEpisode = matchingEpisodes.isNotEmpty ? matchingEpisodes.first : null;
            
            if (nextEpisode != null) {
              // 使用下一集的正确动画ID和剧集ID创建历史项
              final historyItem = await _createJellyfinHistoryItem(nextEpisode, nextDandanplayAnimeId ?? animeId, nextDandanplayEpisodeId);
              
              debugPrint('[数据库导航] 成功创建下一集历史项: ${nextEpisode.name}，使用弹幕ID: animeId=${nextDandanplayAnimeId ?? animeId}, episodeId=$nextDandanplayEpisodeId');
              return EpisodeNavigationResult.success(
                historyItem: historyItem,
                message: '从Jellyfin映射服务找到下一话：${nextEpisode.name}',
              );
            }
          } catch (e) {
            debugPrint('[数据库导航] 获取Jellyfin剧集详情失败: $e');
          }
        }
      }

      // 回退到原有的数据库导航逻辑
      final database = WatchHistoryDatabase.instance;
      
      // 获取该动画的所有剧集列表，按episode_id排序
      final allEpisodes = await database.getHistoryByAnimeId(animeId);
      
      if (allEpisodes.isEmpty) {
        return EpisodeNavigationResult.failure('数据库中没有该动画的剧集记录');
      }
      
      // 找到当前剧集在列表中的位置
      int currentIndex = -1;
      for (int i = 0; i < allEpisodes.length; i++) {
        if (allEpisodes[i].episodeId == episodeId) {
          currentIndex = i;
          break;
        }
      }
      
      if (currentIndex == -1) {
        debugPrint('[数据库导航] 当前剧集不在列表中：episodeId=$episodeId');
        return EpisodeNavigationResult.failure('当前剧集不在数据库列表中');
      }
      
      // 从当前位置向后查找可播放的剧集
      for (int i = currentIndex + 1; i < allEpisodes.length; i++) {
        final episode = allEpisodes[i];
        if (await _checkFileExists(episode.filePath)) {
          debugPrint('[数据库导航] 找到下一话：${episode.episodeTitle} (索引位置: $i)');
          return EpisodeNavigationResult.success(
            historyItem: episode,
            message: '从剧集列表找到下一话：${episode.episodeTitle}',
          );
        } else {
          debugPrint('[数据库导航] 文件不存在，跳过：${episode.filePath}');
        }
      }

      return EpisodeNavigationResult.failure('数据库中没有找到可播放的下一话');
    } catch (e) {
      debugPrint('[数据库导航] 获取下一话时出错：$e');
      return EpisodeNavigationResult.failure('数据库查询出错：$e');
    }
  }

  /// 模式1：从文件系统获取上一话（优先模式）
  Future<EpisodeNavigationResult> _getPreviousEpisodeFromFileSystem(String currentFilePath) async {
    try {
      // 如果是流媒体URL，无法使用文件系统导航
      if (_isStreamingUrl(currentFilePath)) {
        return EpisodeNavigationResult.failure('流媒体无法使用文件系统导航');
      }

      final currentFile = File(currentFilePath);
      final directory = currentFile.parent;

      if (!await directory.exists()) {
        return EpisodeNavigationResult.failure('目录不存在');
      }

      // 获取目录中的所有视频文件
      final videoFiles = await _getVideoFilesInDirectory(directory);
      if (videoFiles.length <= 1) {
        return EpisodeNavigationResult.failure('目录中没有其他视频文件');
      }

      // 按文件名排序
      videoFiles.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

      // 找到当前文件的位置
      final currentIndex = videoFiles.indexWhere((file) => file.path == currentFilePath);
      if (currentIndex == -1) {
        return EpisodeNavigationResult.failure('在目录中找不到当前文件');
      }

      // 查找上一个可播放的文件
      for (int i = currentIndex - 1; i >= 0; i--) {
        final previousFile = videoFiles[i];
        if (await previousFile.exists()) {
          return EpisodeNavigationResult.success(
            filePath: previousFile.path,
            message: '从文件列表找到上一个视频：${path.basename(previousFile.path)}',
          );
        }
      }

      return EpisodeNavigationResult.failure('没有找到可播放的上一个视频文件');
    } catch (e) {
      debugPrint('[文件系统导航] 获取上一话时出错：$e');
      return EpisodeNavigationResult.failure('文件系统导航出错：$e');
    }
  }

  /// 模式1：从文件系统获取下一话（优先模式）
  Future<EpisodeNavigationResult> _getNextEpisodeFromFileSystem(String currentFilePath) async {
    try {
      // 如果是流媒体URL，无法使用文件系统导航
      if (_isStreamingUrl(currentFilePath)) {
        return EpisodeNavigationResult.failure('流媒体无法使用文件系统导航');
      }

      final currentFile = File(currentFilePath);
      final directory = currentFile.parent;

      if (!await directory.exists()) {
        return EpisodeNavigationResult.failure('目录不存在');
      }

      // 获取目录中的所有视频文件
      final videoFiles = await _getVideoFilesInDirectory(directory);
      if (videoFiles.length <= 1) {
        return EpisodeNavigationResult.failure('目录中没有其他视频文件');
      }

      // 按文件名排序
      videoFiles.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

      // 找到当前文件的位置
      final currentIndex = videoFiles.indexWhere((file) => file.path == currentFilePath);
      if (currentIndex == -1) {
        return EpisodeNavigationResult.failure('在目录中找不到当前文件');
      }

      // 查找下一个可播放的文件
      for (int i = currentIndex + 1; i < videoFiles.length; i++) {
        final nextFile = videoFiles[i];
        if (await nextFile.exists()) {
          return EpisodeNavigationResult.success(
            filePath: nextFile.path,
            message: '从文件列表找到下一个视频：${path.basename(nextFile.path)}',
          );
        }
      }

      return EpisodeNavigationResult.failure('没有找到可播放的下一个视频文件');
    } catch (e) {
      debugPrint('[文件系统导航] 获取下一话时出错：$e');
      return EpisodeNavigationResult.failure('文件系统导航出错：$e');
    }
  }

  /// 获取目录中的所有视频文件
  Future<List<File>> _getVideoFilesInDirectory(Directory directory) async {
    final videoExtensions = {'.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.ts', '.m2ts'};
    final files = <File>[];

    await for (final entity in directory.list()) {
      if (entity is File) {
        final extension = path.extension(entity.path).toLowerCase();
        if (videoExtensions.contains(extension)) {
          files.add(entity);
        }
      }
    }

    return files;
  }

  /// 检查文件是否存在
  Future<bool> _checkFileExists(String filePath) async {
    try {
      // 如果是URL（流媒体），直接返回true
      if (_isStreamingUrl(filePath)) {
        return true;
      }

      // 检查本地文件
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      debugPrint('[文件检查] 检查文件是否存在时出错：$e');
      return false;
    }
  }

  /// 检查是否为流媒体URL
  bool _isStreamingUrl(String filePath) {
    return filePath.startsWith('http') || 
           filePath.startsWith('jellyfin://') || 
           filePath.startsWith('emby://');
  }

  /// 检查是否为Jellyfin URL
  bool _isJellyfinUrl(String filePath) {
    return filePath.startsWith('jellyfin://');
  }

  /// 检查是否为Emby URL
  bool _isEmbyUrl(String filePath) {
    return filePath.startsWith('emby://');
  }

  /// Jellyfin模式：获取上一话
  Future<EpisodeNavigationResult> _getPreviousEpisodeFromJellyfin(String currentFilePath, int? animeId, int? episodeId) async {
    try {
      if (!JellyfinService.instance.isConnected) {
        return EpisodeNavigationResult.failure('Jellyfin服务器未连接');
      }

      // 在导航前先更新当前集的历史记录，确保历史记录卡片显示正确的动画名称
      await _updateCurrentEpisodeHistory(currentFilePath, animeId, episodeId);

      // 从jellyfin://协议URL中提取episodeId等信息
      final urlParts = _parseJellyfinUrl(currentFilePath);
      if (urlParts == null) {
        return EpisodeNavigationResult.failure('无法解析Jellyfin URL');
      }

      final currentEpisodeId = urlParts['episodeId'];
      if (currentEpisodeId == null) {
        return EpisodeNavigationResult.failure('Jellyfin URL缺少episodeId');
      }

      String? seriesId = urlParts['seriesId'];
      String? seasonId = urlParts['seasonId'];

      // 如果URL中没有seriesId和seasonId，需要通过API获取
      if (seriesId == null || seasonId == null) {
        try {
          final episodeInfo = await JellyfinService.instance.getEpisodeDetails(currentEpisodeId);
          if (episodeInfo != null) {
            seriesId = episodeInfo.seriesId;
            seasonId = episodeInfo.seasonId;
            debugPrint('[Jellyfin导航] 通过API获取到系列信息: seriesId=$seriesId, seasonId=$seasonId');
          } else {
            return EpisodeNavigationResult.failure('无法获取当前剧集的系列信息');
          }
        } catch (e) {
          debugPrint('[Jellyfin导航] 获取剧集信息失败: $e');
          return EpisodeNavigationResult.failure('获取剧集信息失败: $e');
        }
      }

      if (seriesId == null || seasonId == null) {
        return EpisodeNavigationResult.failure('无法确定系列和季节信息');
      }

      // 获取该季的所有剧集
      final episodes = await JellyfinService.instance.getSeasonEpisodes(seriesId, seasonId);
      if (episodes.isEmpty) {
        return EpisodeNavigationResult.failure('该季没有剧集');
      }

      // 按集数排序
      episodes.sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));

      // 找到当前剧集的位置
      final currentIndex = episodes.indexWhere((ep) => ep.id == currentEpisodeId);
      if (currentIndex == -1) {
        return EpisodeNavigationResult.failure('找不到当前剧集');
      }

      // 查找上一集
      if (currentIndex > 0) {
        final previousEpisode = episodes[currentIndex - 1];
        
        // 通过映射服务获取上一集的正确弹幕ID
        int? previousAnimeId;
        int? previousEpisodeId;
        
        try {
          // 如果有当前剧集的弹幕ID，使用它们来预测上一集的映射
          if (animeId != null && episodeId != null) {
            final previousMapping = await JellyfinEpisodeMappingService.instance.getPreviousEpisodeMappingByDanmakuIds(
              currentAnimeId: animeId,
              currentEpisodeId: episodeId,
            );
            
            if (previousMapping != null) {
              previousAnimeId = previousMapping['dandanplay_anime_id'] as int?;
              previousEpisodeId = previousMapping['dandanplay_episode_id'] as int?;
              debugPrint('[Jellyfin导航] 通过映射服务预测到上一集: animeId=$previousAnimeId, episodeId=$previousEpisodeId');
              
              // 立即保存预测的映射到数据库中
              try {
                final mappingId = previousMapping['mapping_id'] as int;
                await JellyfinEpisodeMappingService.instance.recordEpisodeMapping(
                  jellyfinEpisodeId: previousEpisode.id,
                  jellyfinIndexNumber: previousEpisode.indexNumber ?? 0,
                  dandanplayEpisodeId: previousEpisodeId!,
                  mappingId: mappingId,
                  confirmed: false, // 标记为预测映射
                );
                debugPrint('[Jellyfin导航] 已保存上一集的预测映射到数据库');
              } catch (e) {
                debugPrint('[Jellyfin导航] 保存预测映射失败: $e');
              }
            } else {
              debugPrint('[Jellyfin导航] 映射服务无法预测上一集，将进行自动匹配');
            }
          } else {
            // 如果没有当前剧集的弹幕ID，尝试直接查找上一集的映射
            final mapping = await JellyfinEpisodeMappingService.instance.getEpisodeMapping(previousEpisode.id);
            if (mapping != null) {
              previousAnimeId = mapping['dandanplay_anime_id'] as int?;
              previousEpisodeId = mapping['dandanplay_episode_id'] as int?;
              debugPrint('[Jellyfin导航] 找到上一集的直接映射: animeId=$previousAnimeId, episodeId=$previousEpisodeId');
            } else {
              debugPrint('[Jellyfin导航] 没有弹幕ID且无直接映射，将进行自动匹配');
            }
          }
        } catch (e) {
          debugPrint('[Jellyfin导航] 获取上一集弹幕映射失败: $e');
          // 出错时不使用任何弹幕ID，让系统进行自动匹配
          previousAnimeId = null;
          previousEpisodeId = null;
        }
        
        // 创建播放历史项
        final historyItem = await _createJellyfinHistoryItem(previousEpisode, previousAnimeId, previousEpisodeId);
        
        return EpisodeNavigationResult.success(
          historyItem: historyItem,
          message: '找到上一话：${previousEpisode.name}',
        );
      }

      return EpisodeNavigationResult.failure('已经是第一集');
    } catch (e) {
      debugPrint('[Jellyfin导航] 传统导航方式失败: $e，尝试使用简单API导航');
      
      // 回退到简单的API导航：使用adjacentTo参数
      try {
        final currentEpisodeId = _parseJellyfinUrl(currentFilePath)?['episodeId'];
        if (currentEpisodeId != null) {
          final previousEpisode = await JellyfinService.instance.getPreviousEpisode(currentEpisodeId);
          if (previousEpisode != null) {
            // 创建不带弹幕映射的历史项（会进行自动匹配）
            final historyItem = await _createJellyfinHistoryItem(previousEpisode, null, null);
            
            return EpisodeNavigationResult.success(
              historyItem: historyItem,
              message: '找到上一话：${previousEpisode.name}（简单导航）',
            );
          }
        }
      } catch (simpleApiError) {
        debugPrint('[Jellyfin导航] 简单API导航也失败: $simpleApiError');
      }
      
      return EpisodeNavigationResult.failure('Jellyfin导航出错：$e');
    }
  }

  /// Jellyfin模式：获取下一话
  Future<EpisodeNavigationResult> _getNextEpisodeFromJellyfin(String currentFilePath, int? animeId, int? episodeId) async {
    try {
      if (!JellyfinService.instance.isConnected) {
        return EpisodeNavigationResult.failure('Jellyfin服务器未连接');
      }

      // 在导航前先更新当前集的历史记录，确保历史记录卡片显示正确的动画名称
      await _updateCurrentEpisodeHistory(currentFilePath, animeId, episodeId);

      // 从jellyfin://协议URL中提取episodeId等信息
      final urlParts = _parseJellyfinUrl(currentFilePath);
      if (urlParts == null) {
        return EpisodeNavigationResult.failure('无法解析Jellyfin URL');
      }

      final currentEpisodeId = urlParts['episodeId'];
      if (currentEpisodeId == null) {
        return EpisodeNavigationResult.failure('Jellyfin URL缺少episodeId');
      }

      String? seriesId = urlParts['seriesId'];
      String? seasonId = urlParts['seasonId'];

      // 如果URL中没有seriesId和seasonId，需要通过API获取
      if (seriesId == null || seasonId == null) {
        try {
          final episodeInfo = await JellyfinService.instance.getEpisodeDetails(currentEpisodeId);
          if (episodeInfo != null) {
            seriesId = episodeInfo.seriesId;
            seasonId = episodeInfo.seasonId;
            debugPrint('[Jellyfin导航] 通过API获取到系列信息: seriesId=$seriesId, seasonId=$seasonId');
          } else {
            return EpisodeNavigationResult.failure('无法获取当前剧集的系列信息');
          }
        } catch (e) {
          debugPrint('[Jellyfin导航] 获取剧集信息失败: $e');
          return EpisodeNavigationResult.failure('获取剧集信息失败: $e');
        }
      }

      if (seriesId == null || seasonId == null) {
        return EpisodeNavigationResult.failure('无法确定系列和季节信息');
      }

      // 获取该季的所有剧集
      final episodes = await JellyfinService.instance.getSeasonEpisodes(seriesId, seasonId);
      if (episodes.isEmpty) {
        return EpisodeNavigationResult.failure('该季没有剧集');
      }

      // 按集数排序，将特别篇（indexNumber 为 null 或 0）排在最后
      episodes.sort((a, b) {
        final aIndex = (a.indexNumber == null || a.indexNumber == 0) ? 999999 : a.indexNumber!;
        final bIndex = (b.indexNumber == null || b.indexNumber == 0) ? 999999 : b.indexNumber!;
        return aIndex.compareTo(bIndex);
      });

      // 找到当前剧集的位置
      final currentIndex = episodes.indexWhere((ep) => ep.id == currentEpisodeId);
      if (currentIndex == -1) {
        return EpisodeNavigationResult.failure('找不到当前剧集');
      }

      // 查找下一集
      if (currentIndex < episodes.length - 1) {
        final nextEpisode = episodes[currentIndex + 1];
        
        // 通过映射服务获取下一集的正确弹幕ID
        int? nextAnimeId;
        int? nextEpisodeId;
        
        try {
          // 如果有当前剧集的弹幕ID，使用它们来预测下一集的映射
          if (animeId != null && episodeId != null) {
            final nextMapping = await JellyfinEpisodeMappingService.instance.getNextEpisodeMappingByDanmakuIds(
              currentAnimeId: animeId,
              currentEpisodeId: episodeId,
            );
            
            if (nextMapping != null) {
              nextAnimeId = nextMapping['dandanplay_anime_id'] as int?;
              nextEpisodeId = nextMapping['dandanplay_episode_id'] as int?;
              debugPrint('[Jellyfin导航] 通过映射服务预测到下一集: animeId=$nextAnimeId, episodeId=$nextEpisodeId');
              
              // 立即保存预测的映射到数据库中
              try {
                final mappingId = nextMapping['mapping_id'] as int;
                await JellyfinEpisodeMappingService.instance.recordEpisodeMapping(
                  jellyfinEpisodeId: nextEpisode.id,
                  jellyfinIndexNumber: nextEpisode.indexNumber ?? 0,
                  dandanplayEpisodeId: nextEpisodeId!,
                  mappingId: mappingId,
                  confirmed: false, // 标记为预测映射
                );
                debugPrint('[Jellyfin导航] 已保存下一集的预测映射到数据库');
              } catch (e) {
                debugPrint('[Jellyfin导航] 保存预测映射失败: $e');
              }
            } else {
              debugPrint('[Jellyfin导航] 映射服务无法预测下一集，将进行自动匹配');
            }
          } else {
            // 如果没有当前剧集的弹幕ID，尝试直接查找下一集的映射
            final mapping = await JellyfinEpisodeMappingService.instance.getEpisodeMapping(nextEpisode.id);
            if (mapping != null) {
              final mappingId = mapping['mapping_id'] as int?;
              if (mappingId != null) {
                final animeMapping = await JellyfinEpisodeMappingService.instance.getAnimeMapping(
                  jellyfinSeriesId: seriesId,
                  jellyfinSeasonId: seasonId,
                );
                if (animeMapping != null) {
                  nextAnimeId = animeMapping['dandanplay_anime_id'] as int?;
                }
              }
              nextEpisodeId = mapping['dandanplay_episode_id'] as int?;
              debugPrint('[Jellyfin导航] 找到下一集的直接映射: animeId=$nextAnimeId, episodeId=$nextEpisodeId');
            } else {
              debugPrint('[Jellyfin导航] 没有弹幕ID且无直接映射，将进行自动匹配');
            }
          }
        } catch (e) {
          debugPrint('[Jellyfin导航] 获取下一集弹幕映射失败: $e');
          // 出错时不使用任何弹幕ID，让系统进行自动匹配
          nextAnimeId = null;
          nextEpisodeId = null;
        }
        
        // 创建播放历史项
        final historyItem = await _createJellyfinHistoryItem(nextEpisode, nextAnimeId, nextEpisodeId);
        
        return EpisodeNavigationResult.success(
          historyItem: historyItem,
          message: '找到下一话：${nextEpisode.name}',
        );
      }

      return EpisodeNavigationResult.failure('已经是最后一集');
    } catch (e) {
      debugPrint('[Jellyfin导航] 传统导航方式失败: $e，尝试使用简单API导航');
      
      // 回退到简单的API导航：使用adjacentTo参数
      try {
        final currentEpisodeId = _parseJellyfinUrl(currentFilePath)?['episodeId'];
        if (currentEpisodeId != null) {
          final nextEpisode = await JellyfinService.instance.getNextEpisode(currentEpisodeId);
          if (nextEpisode != null) {
            // 创建不带弹幕映射的历史项（会进行自动匹配）
            final historyItem = await _createJellyfinHistoryItem(nextEpisode, null, null);
            
            return EpisodeNavigationResult.success(
              historyItem: historyItem,
              message: '找到下一话：${nextEpisode.name}（简单导航）',
            );
          }
        }
      } catch (simpleApiError) {
        debugPrint('[Jellyfin导航] 简单API导航也失败: $simpleApiError');
      }
      
      return EpisodeNavigationResult.failure('Jellyfin导航出错：$e');
    }
  }

  /// 解析Jellyfin URL，提取episodeId
  Map<String, String>? _parseJellyfinUrl(String url) {
    if (!url.startsWith('jellyfin://')) {
      return null;
    }

    final path = url.substring('jellyfin://'.length);
    final parts = path.split('/');
    
    // 主要支持简化格式：jellyfin://episodeId
    if (parts.length == 1 && parts[0].isNotEmpty) {
      return {
        'episodeId': parts[0],
      };
    } 
    // 兼容完整格式：jellyfin://seriesId/seasonId/episodeId（如果存在）
    else if (parts.length >= 3) {
      return {
        'seriesId': parts[0],
        'seasonId': parts[1], 
        'episodeId': parts[2],
      };
    }

    return null;
  }

  /// 创建Jellyfin剧集的历史记录项
  Future<WatchHistoryItem> _createJellyfinHistoryItem(JellyfinEpisodeInfo episode, int? animeId, int? episodeId) async {
    try {
      // 如果有映射的弹幕ID，使用DanDanPlay API获取正确的剧集信息
      if (animeId != null && episodeId != null) {
        try {
          // 使用DanDanPlay API获取准确的剧集标题，保持标题一致性
          debugPrint('[Jellyfin导航] 使用映射的弹幕ID查询剧集信息: animeId=$animeId, episodeId=$episodeId');
          
          // 获取动画详情以获取准确的标题
          final bangumiDetails = await DandanplayService.getBangumiDetails(animeId);
          
          String? animeTitle;
          String? episodeTitle;
          
          if (bangumiDetails['success'] == true && bangumiDetails['bangumi'] != null) {
            final bangumi = bangumiDetails['bangumi'];
            animeTitle = bangumi['animeTitle'] as String?;
            
            // 查找对应的剧集标题
            if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
              final episodes = bangumi['episodes'] as List;
              final targetEpisode = episodes.firstWhere(
                (ep) => ep['episodeId'] == episodeId,
                orElse: () => null,
              );
              
              if (targetEpisode != null) {
                episodeTitle = targetEpisode['episodeTitle'] as String?;
                debugPrint('[Jellyfin导航] 从DanDanPlay API获取到剧集标题: $episodeTitle');
              }
            }
          }
          
          // 创建包含正确弹幕信息和标题的历史项
          return WatchHistoryItem(
            filePath: 'jellyfin://${episode.id}',
            animeName: animeTitle ?? episode.seriesName ?? 'Unknown',
            episodeTitle: episodeTitle ?? episode.name,
            animeId: animeId,
            episodeId: episodeId,
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
            thumbnailPath: null,
            isFromScan: false,
          );
        } catch (e) {
          debugPrint('[Jellyfin导航] 获取DanDanPlay剧集信息失败: $e，使用基础信息');
        }
      }
      
      // 如果没有映射的弹幕ID或获取失败，使用基础信息创建历史项
      debugPrint('[Jellyfin导航] 没有映射的弹幕ID，使用基础信息创建历史项');
      return episode.toWatchHistoryItem();
    } catch (e) {
      debugPrint('[Jellyfin导航] 创建历史项时出错：$e，使用基础历史项');
      return episode.toWatchHistoryItem();
    }
  }

  /// 检查是否可以使用数据库导航
  bool canUseDatabaseNavigation(int? animeId, int? episodeId) {
    return animeId != null && episodeId != null;
  }

  /// 检查是否可以使用文件系统导航
  bool canUseFileSystemNavigation(String filePath) {
    return !_isStreamingUrl(filePath);
  }

  /// 检查是否可以使用流媒体简单导航（Jellyfin/Emby的adjacentTo API）
  bool canUseStreamingNavigation(String filePath) {
    return _isJellyfinUrl(filePath) || _isEmbyUrl(filePath);
  }

  /// Emby模式：获取上一话
  Future<EpisodeNavigationResult> _getPreviousEpisodeFromEmby(String currentFilePath, int? animeId, int? episodeId) async {
    try {
      if (!EmbyService.instance.isConnected) {
        return EpisodeNavigationResult.failure('Emby服务器未连接');
      }

      // 在导航前先更新当前集的历史记录，确保历史记录卡片显示正确的动画名称
      await _updateCurrentEpisodeHistory(currentFilePath, animeId, episodeId);

      // 从emby://协议URL中提取episodeId等信息
      final urlParts = _parseEmbyUrl(currentFilePath);
      if (urlParts == null) {
        return EpisodeNavigationResult.failure('无法解析Emby URL');
      }

      final currentEpisodeId = urlParts['episodeId'];
      if (currentEpisodeId == null) {
        return EpisodeNavigationResult.failure('Emby URL缺少episodeId');
      }

      String? seriesId = urlParts['seriesId'];
      String? seasonId = urlParts['seasonId'];

      // 如果URL中没有seriesId和seasonId，需要通过API获取
      if (seriesId == null || seasonId == null) {
        try {
          final episodeInfo = await EmbyService.instance.getEpisodeDetails(currentEpisodeId);
          if (episodeInfo != null) {
            seriesId = episodeInfo.seriesId;
            seasonId = episodeInfo.seasonId;
            debugPrint('[Emby导航] 通过API获取到系列信息: seriesId=$seriesId, seasonId=$seasonId');
          } else {
            return EpisodeNavigationResult.failure('无法获取当前剧集的系列信息');
          }
        } catch (e) {
          debugPrint('[Emby导航] 获取剧集信息失败: $e');
          return EpisodeNavigationResult.failure('获取剧集信息失败: $e');
        }
      }

      if (seriesId == null || seasonId == null) {
        return EpisodeNavigationResult.failure('无法确定系列和季节信息');
      }

      // 获取该季的所有剧集
      final episodes = await EmbyService.instance.getSeasonEpisodes(seriesId, seasonId);
      if (episodes.isEmpty) {
        return EpisodeNavigationResult.failure('该季没有剧集');
      }

      // 按集数排序，将特别篇（indexNumber 为 null 或 0）排在最后
      episodes.sort((a, b) {
        final aIndex = (a.indexNumber == null || a.indexNumber == 0) ? 999999 : a.indexNumber!;
        final bIndex = (b.indexNumber == null || b.indexNumber == 0) ? 999999 : b.indexNumber!;
        return aIndex.compareTo(bIndex);
      });

      // 找到当前剧集的位置
      final currentIndex = episodes.indexWhere((ep) => ep.id == currentEpisodeId);
      if (currentIndex == -1) {
        return EpisodeNavigationResult.failure('找不到当前剧集');
      }

      // 查找上一集
      if (currentIndex > 0) {
        final previousEpisode = episodes[currentIndex - 1];
        
        // 通过映射服务获取上一集的正确弹幕ID
        int? previousAnimeId;
        int? previousEpisodeId;
        
        try {
          // 如果有当前剧集的弹幕ID，使用它们来预测上一集的映射
          if (animeId != null && episodeId != null) {
            final previousMapping = await EmbyEpisodeMappingService.instance.getPreviousEpisodeMappingByDanmakuIds(
              currentAnimeId: animeId,
              currentEpisodeId: episodeId,
            );
            
            if (previousMapping != null) {
              previousAnimeId = previousMapping['dandanplay_anime_id'] as int?;
              previousEpisodeId = previousMapping['dandanplay_episode_id'] as int?;
              debugPrint('[Emby导航] 通过映射服务预测到上一集: animeId=$previousAnimeId, episodeId=$previousEpisodeId');
              
              // 立即保存预测的映射到数据库中
              try {
                final mappingId = previousMapping['mapping_id'] as int;
                await EmbyEpisodeMappingService.instance.recordEpisodeMapping(
                  embyEpisodeId: previousEpisode.id,
                  embyIndexNumber: previousEpisode.indexNumber ?? 0,
                  dandanplayEpisodeId: previousEpisodeId!,
                  mappingId: mappingId,
                  confirmed: false, // 标记为预测映射
                );
                debugPrint('[Emby导航] 已保存上一集的预测映射到数据库');
              } catch (e) {
                debugPrint('[Emby导航] 保存预测映射失败: $e');
              }
            } else {
              debugPrint('[Emby导航] 映射服务无法预测上一集，将进行自动匹配');
            }
          } else {
            // 如果没有当前剧集的弹幕ID，尝试直接查找上一集的映射
            final mapping = await EmbyEpisodeMappingService.instance.getEpisodeMapping(previousEpisode.id);
            if (mapping != null) {
              final mappingId = mapping['mapping_id'] as int?;
              if (mappingId != null) {
                final animeMapping = await EmbyEpisodeMappingService.instance.getAnimeMapping(
                  embySeriesId: seriesId,
                  embySeasonId: seasonId,
                );
                if (animeMapping != null) {
                  previousAnimeId = animeMapping['dandanplay_anime_id'] as int?;
                }
              }
              previousEpisodeId = mapping['dandanplay_episode_id'] as int?;
              debugPrint('[Emby导航] 找到上一集的直接映射: animeId=$previousAnimeId, episodeId=$previousEpisodeId');
            } else {
              debugPrint('[Emby导航] 没有弹幕ID且无直接映射，将进行自动匹配');
            }
          }
        } catch (e) {
          debugPrint('[Emby导航] 获取上一集弹幕映射失败: $e');
          // 出错时不使用任何弹幕ID，让系统进行自动匹配
          previousAnimeId = null;
          previousEpisodeId = null;
        }
        
        // 创建播放历史项
        final historyItem = await _createEmbyHistoryItem(previousEpisode, previousAnimeId, previousEpisodeId);
        
        return EpisodeNavigationResult.success(
          historyItem: historyItem,
          message: '找到上一话：${previousEpisode.name}',
        );
      }

      return EpisodeNavigationResult.failure('已经是第一集');
    } catch (e) {
      debugPrint('[Emby导航] 传统导航方式失败: $e，尝试使用简单API导航');
      
      // 回退到简单的API导航：使用AdjacentTo参数
      try {
        final currentEpisodeId = _parseEmbyUrl(currentFilePath)?['episodeId'];
        if (currentEpisodeId != null) {
          final previousEpisode = await EmbyService.instance.getPreviousEpisode(currentEpisodeId);
          if (previousEpisode != null) {
            // 创建不带弹幕映射的历史项（会进行自动匹配）
            final historyItem = await _createEmbyHistoryItem(previousEpisode, null, null);
            
            return EpisodeNavigationResult.success(
              historyItem: historyItem,
              message: '找到上一话：${previousEpisode.name}（简单导航）',
            );
          }
        }
      } catch (simpleApiError) {
        debugPrint('[Emby导航] 简单API导航也失败: $simpleApiError');
      }
      
      return EpisodeNavigationResult.failure('Emby导航出错：$e');
    }
  }

  /// Emby模式：获取下一话
  Future<EpisodeNavigationResult> _getNextEpisodeFromEmby(String currentFilePath, int? animeId, int? episodeId) async {
    try {
      if (!EmbyService.instance.isConnected) {
        return EpisodeNavigationResult.failure('Emby服务器未连接');
      }

      // 在导航前先更新当前集的历史记录，确保历史记录卡片显示正确的动画名称
      await _updateCurrentEpisodeHistory(currentFilePath, animeId, episodeId);

      // 从emby://协议URL中提取episodeId等信息
      final urlParts = _parseEmbyUrl(currentFilePath);
      if (urlParts == null) {
        return EpisodeNavigationResult.failure('无法解析Emby URL');
      }

      final currentEpisodeId = urlParts['episodeId'];
      if (currentEpisodeId == null) {
        return EpisodeNavigationResult.failure('Emby URL缺少episodeId');
      }

      String? seriesId = urlParts['seriesId'];
      String? seasonId = urlParts['seasonId'];

      // 如果URL中没有seriesId和seasonId，需要通过API获取
      if (seriesId == null || seasonId == null) {
        try {
          final episodeInfo = await EmbyService.instance.getEpisodeDetails(currentEpisodeId);
          if (episodeInfo != null) {
            seriesId = episodeInfo.seriesId;
            seasonId = episodeInfo.seasonId;
            debugPrint('[Emby导航] 通过API获取到系列信息: seriesId=$seriesId, seasonId=$seasonId');
          } else {
            return EpisodeNavigationResult.failure('无法获取当前剧集的系列信息');
          }
        } catch (e) {
          debugPrint('[Emby导航] 获取剧集信息失败: $e');
          return EpisodeNavigationResult.failure('获取剧集信息失败: $e');
        }
      }

      if (seriesId == null || seasonId == null) {
        return EpisodeNavigationResult.failure('无法确定系列和季节信息');
      }

      // 获取该季的所有剧集
      final episodes = await EmbyService.instance.getSeasonEpisodes(seriesId, seasonId);
      if (episodes.isEmpty) {
        return EpisodeNavigationResult.failure('该季没有剧集');
      }

      // 按集数排序，将特别篇（indexNumber 为 null 或 0）排在最后
      episodes.sort((a, b) {
        final aIndex = (a.indexNumber == null || a.indexNumber == 0) ? 999999 : a.indexNumber!;
        final bIndex = (b.indexNumber == null || b.indexNumber == 0) ? 999999 : b.indexNumber!;
        return aIndex.compareTo(bIndex);
      });

      // 找到当前剧集的位置
      final currentIndex = episodes.indexWhere((ep) => ep.id == currentEpisodeId);
      if (currentIndex == -1) {
        return EpisodeNavigationResult.failure('找不到当前剧集');
      }

      // 查找下一集
      if (currentIndex < episodes.length - 1) {
        final nextEpisode = episodes[currentIndex + 1];
        
        // 通过映射服务获取下一集的正确弹幕ID
        int? nextAnimeId;
        int? nextEpisodeId;
        
        try {
          // 如果有当前剧集的弹幕ID，使用它们来预测下一集的映射
          if (animeId != null && episodeId != null) {
            final nextMapping = await EmbyEpisodeMappingService.instance.getNextEpisodeMappingByDanmakuIds(
              currentAnimeId: animeId,
              currentEpisodeId: episodeId,
            );
            
            if (nextMapping != null) {
              nextAnimeId = nextMapping['dandanplay_anime_id'] as int?;
              nextEpisodeId = nextMapping['dandanplay_episode_id'] as int?;
              debugPrint('[Emby导航] 通过映射服务预测到下一集: animeId=$nextAnimeId, episodeId=$nextEpisodeId');
              
              // 立即保存预测的映射到数据库中
              try {
                final mappingId = nextMapping['mapping_id'] as int;
                await EmbyEpisodeMappingService.instance.recordEpisodeMapping(
                  embyEpisodeId: nextEpisode.id,
                  embyIndexNumber: nextEpisode.indexNumber ?? 0,
                  dandanplayEpisodeId: nextEpisodeId!,
                  mappingId: mappingId,
                  confirmed: false, // 标记为预测映射
                );
                debugPrint('[Emby导航] 已保存下一集的预测映射到数据库');
              } catch (e) {
                debugPrint('[Emby导航] 保存预测映射失败: $e');
              }
            } else {
              debugPrint('[Emby导航] 映射服务无法预测下一集，将进行自动匹配');
            }
          } else {
            // 如果没有当前剧集的弹幕ID，尝试直接查找下一集的映射
            final mapping = await EmbyEpisodeMappingService.instance.getEpisodeMapping(nextEpisode.id);
            if (mapping != null) {
              final mappingId = mapping['mapping_id'] as int?;
              if (mappingId != null) {
                final animeMapping = await EmbyEpisodeMappingService.instance.getAnimeMapping(
                  embySeriesId: seriesId,
                  embySeasonId: seasonId,
                );
                if (animeMapping != null) {
                  nextAnimeId = animeMapping['dandanplay_anime_id'] as int?;
                }
              }
              nextEpisodeId = mapping['dandanplay_episode_id'] as int?;
              debugPrint('[Emby导航] 找到下一集的直接映射: animeId=$nextAnimeId, episodeId=$nextEpisodeId');
            } else {
              debugPrint('[Emby导航] 没有弹幕ID且无直接映射，将进行自动匹配');
            }
          }
        } catch (e) {
          debugPrint('[Emby导航] 获取下一集弹幕映射失败: $e');
          // 出错时不使用任何弹幕ID，让系统进行自动匹配
          nextAnimeId = null;
          nextEpisodeId = null;
        }
        
        // 创建播放历史项
        final historyItem = await _createEmbyHistoryItem(nextEpisode, nextAnimeId, nextEpisodeId);
        
        return EpisodeNavigationResult.success(
          historyItem: historyItem,
          message: '找到下一话：${nextEpisode.name}',
        );
      }

      return EpisodeNavigationResult.failure('已经是最后一集');
    } catch (e) {
      debugPrint('[Emby导航] 传统导航方式失败: $e，尝试使用简单API导航');
      
      // 回退到简单的API导航：使用AdjacentTo参数
      try {
        final currentEpisodeId = _parseEmbyUrl(currentFilePath)?['episodeId'];
        if (currentEpisodeId != null) {
          final nextEpisode = await EmbyService.instance.getNextEpisode(currentEpisodeId);
          if (nextEpisode != null) {
            // 创建不带弹幕映射的历史项（会进行自动匹配）
            final historyItem = await _createEmbyHistoryItem(nextEpisode, null, null);
            
            return EpisodeNavigationResult.success(
              historyItem: historyItem,
              message: '找到下一话：${nextEpisode.name}（简单导航）',
            );
          }
        }
      } catch (simpleApiError) {
        debugPrint('[Emby导航] 简单API导航也失败: $simpleApiError');
      }
      
      return EpisodeNavigationResult.failure('Emby导航出错：$e');
    }
  }

  /// 解析Emby URL，提取episodeId
  Map<String, String>? _parseEmbyUrl(String url) {
    if (!url.startsWith('emby://')) {
      return null;
    }

    final path = url.substring('emby://'.length);
    final parts = path.split('/');
    
    // 主要支持简化格式：emby://episodeId
    if (parts.length == 1 && parts[0].isNotEmpty) {
      return {
        'episodeId': parts[0],
      };
    } 
    // 兼容完整格式：emby://seriesId/seasonId/episodeId（如果存在）
    else if (parts.length >= 3) {
      return {
        'seriesId': parts[0],
        'seasonId': parts[1], 
        'episodeId': parts[2],
      };
    }

    return null;
  }

  /// 创建Emby剧集的历史记录项
  Future<WatchHistoryItem> _createEmbyHistoryItem(EmbyEpisodeInfo episode, int? animeId, int? episodeId) async {
    try {
      // 如果有映射的弹幕ID，使用DanDanPlay API获取正确的剧集信息
      if (animeId != null && episodeId != null) {
        try {
          // 使用DanDanPlay API获取准确的剧集标题，保持标题一致性
          debugPrint('[Emby导航] 使用映射的弹幕ID查询剧集信息: animeId=$animeId, episodeId=$episodeId');
          
          // 获取动画详情以获取准确的标题
          final bangumiDetails = await DandanplayService.getBangumiDetails(animeId);
          
          String? animeTitle;
          String? episodeTitle;
          
          if (bangumiDetails['success'] == true && bangumiDetails['bangumi'] != null) {
            final bangumi = bangumiDetails['bangumi'];
            animeTitle = bangumi['animeTitle'] as String?;
            
            // 查找对应的剧集标题
            if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
              final episodes = bangumi['episodes'] as List;
              final targetEpisode = episodes.firstWhere(
                (ep) => ep['episodeId'] == episodeId,
                orElse: () => null,
              );
              
              if (targetEpisode != null) {
                episodeTitle = targetEpisode['episodeTitle'] as String?;
                debugPrint('[Emby导航] 从DanDanPlay API获取到剧集标题: $episodeTitle');
              }
            }
          }
          
          // 创建包含正确弹幕信息和标题的历史项
          return WatchHistoryItem(
            filePath: 'emby://${episode.id}',
            animeName: animeTitle ?? episode.seriesName ?? 'Unknown',
            episodeTitle: episodeTitle ?? episode.name,
            animeId: animeId,
            episodeId: episodeId,
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
            thumbnailPath: null,
            isFromScan: false,
          );
        } catch (e) {
          debugPrint('[Emby导航] 获取DanDanPlay剧集信息失败: $e，使用基础信息');
        }
      }
      
      // 如果没有映射的弹幕ID或获取失败，使用基础信息创建历史项
      // 但确保使用正确的动画名称，而不是 episode.id
      debugPrint('[Emby导航] 没有映射的弹幕ID，使用基础信息创建历史项');
      
      // 使用 episode.seriesName 作为动画名称，如果为空则使用默认值
      String safeAnimeName = episode.seriesName ?? '';
      if (safeAnimeName.isEmpty) {
        safeAnimeName = "未知剧集";
      }
      
      return WatchHistoryItem(
        filePath: 'emby://${episode.id}',
        animeName: safeAnimeName,
        episodeTitle: episode.name.isNotEmpty ? episode.name : '未知',
        watchProgress: 0.0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
        animeId: animeId, // 保持传入的 animeId，即使为 null
        episodeId: episodeId, // 保持传入的 episodeId，即使为 null
        isFromScan: false,
        videoHash: null,
      );
    } catch (e) {
      debugPrint('[Emby导航] 创建历史项时出错：$e，使用基础历史项');
      return episode.toWatchHistoryItem();
    }
  }

  /// 更新当前集的历史记录
  Future<void> _updateCurrentEpisodeHistory(String currentFilePath, int? animeId, int? episodeId) async {
    try {
      // 如果没有弹幕ID，无法更新历史记录
      if (animeId == null || episodeId == null) {
        debugPrint('[导航服务] 没有弹幕ID，跳过更新当前集历史记录');
        return;
      }

      debugPrint('[导航服务] 开始更新当前集历史记录: animeId=$animeId, episodeId=$episodeId');

      // 获取现有历史记录
      final existingHistory = await WatchHistoryDatabase.instance.getHistoryByFilePath(currentFilePath);
      if (existingHistory == null) {
        debugPrint('[导航服务] 未找到当前集的历史记录，跳过更新');
        return;
      }

      // 使用DanDanPlay API获取正确的动画和剧集信息
      try {
        final bangumiDetails = await DandanplayService.getBangumiDetails(animeId);
        
        String? animeTitle;
        String? episodeTitle;
        
        if (bangumiDetails['success'] == true && bangumiDetails['bangumi'] != null) {
          final bangumi = bangumiDetails['bangumi'];
          animeTitle = bangumi['animeTitle'] as String?;
          
          // 查找对应的剧集标题
          if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
            final episodes = bangumi['episodes'] as List;
            final targetEpisode = episodes.firstWhere(
              (ep) => ep['episodeId'] == episodeId,
              orElse: () => null,
            );
            
            if (targetEpisode != null) {
              episodeTitle = targetEpisode['episodeTitle'] as String?;
              debugPrint('[导航服务] 从DanDanPlay API获取到剧集标题: $episodeTitle');
            }
          }
        }

        // 创建更新后的历史记录
        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: animeTitle ?? existingHistory.animeName,
          episodeTitle: episodeTitle ?? existingHistory.episodeTitle,
          episodeId: episodeId,
          animeId: animeId,
          watchProgress: existingHistory.watchProgress,
          lastPosition: existingHistory.lastPosition,
          duration: existingHistory.duration,
          lastWatchTime: DateTime.now(),
          thumbnailPath: existingHistory.thumbnailPath,
          isFromScan: existingHistory.isFromScan,
        );

        // 保存更新后的记录
        await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(updatedHistory);
        
        debugPrint('[导航服务] 成功更新当前集历史记录: ${updatedHistory.animeName} - ${updatedHistory.episodeTitle}');
        
        // 通知UI刷新历史记录
        // 注意：这里我们不能直接访问Provider，所以只能通过数据库更新
        // UI会在下次刷新时看到更新后的数据
        
      } catch (e) {
        debugPrint('[导航服务] 获取DanDanPlay信息失败: $e，使用现有信息更新');
        
        // 即使获取DanDanPlay信息失败，也要更新弹幕ID
        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: existingHistory.animeName,
          episodeTitle: existingHistory.episodeTitle,
          episodeId: episodeId,
          animeId: animeId,
          watchProgress: existingHistory.watchProgress,
          lastPosition: existingHistory.lastPosition,
          duration: existingHistory.duration,
          lastWatchTime: DateTime.now(),
          thumbnailPath: existingHistory.thumbnailPath,
          isFromScan: existingHistory.isFromScan,
        );

        await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(updatedHistory);
        debugPrint('[导航服务] 使用现有信息更新当前集历史记录');
      }
      
    } catch (e) {
      debugPrint('[导航服务] 更新当前集历史记录时出错: $e');
      // 错误不应阻止导航
    }
  }
} 