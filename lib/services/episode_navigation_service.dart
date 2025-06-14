import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/watch_history_model.dart';
import '../models/watch_history_database.dart';

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

  /// 检查是否可以使用数据库导航
  bool canUseDatabaseNavigation(int? animeId, int? episodeId) {
    return animeId != null && episodeId != null;
  }

  /// 检查是否可以使用文件系统导航
  bool canUseFileSystemNavigation(String filePath) {
    return !_isStreamingUrl(filePath);
  }
} 