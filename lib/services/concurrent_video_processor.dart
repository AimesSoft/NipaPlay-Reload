import 'dart:io' if (dart.library.io) 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/dandanplay_service.dart';

/// 视频处理结果
class VideoProcessResult {
  final String filePath;
  final bool success;
  final String? errorMessage;
  final WatchHistoryItem? historyItem;
  final String? animeTitle;
  
  VideoProcessResult({
    required this.filePath,
    required this.success,
    this.errorMessage,
    this.historyItem,
    this.animeTitle,
  });
}

/// 并发视频处理器，负责并发处理视频文件匹配
class ConcurrentVideoProcessor {
  static const int _maxConcurrency = 4; // 最大并发数
  static const Duration _requestTimeout = Duration(seconds: 20);
  
  /// 并发处理视频文件列表
  static Future<List<VideoProcessResult>> processVideos(
    List<File> videoFiles, {
    bool skipPreviouslyMatchedUnwatched = false,
    Function(int processed, int total, String currentFile)? onProgress,
  }) async {
    if (videoFiles.isEmpty) return [];
    
    // 根据文件数量决定并发数
    final int concurrency = _calculateOptimalConcurrency(videoFiles.length);
    debugPrint('ConcurrentVideoProcessor: 开始处理 ${videoFiles.length} 个视频文件，并发数: $concurrency');
    
    final List<VideoProcessResult> results = [];
    final List<File> filesToProcess = [];
    int skippedCount = 0;
    
    // 第一阶段：过滤需要处理的文件
    if (skipPreviouslyMatchedUnwatched) {
      for (File file in videoFiles) {
        WatchHistoryItem? existingItem = await WatchHistoryManager.getHistoryItem(file.path);
        if (existingItem != null && 
            existingItem.animeId != null && 
            existingItem.episodeId != null && 
            existingItem.watchProgress <= 0.01) {
          skippedCount++;
          onProgress?.call(skippedCount, videoFiles.length, p.basename(file.path));
          continue;
        }
        filesToProcess.add(file);
      }
    } else {
      filesToProcess.addAll(videoFiles);
    }
    
    if (filesToProcess.isEmpty) {
      debugPrint('ConcurrentVideoProcessor: 所有文件都被跳过，无需处理');
      return results;
    }
    
    // 第二阶段：并发处理
    int processedCount = skippedCount;
    final Semaphore semaphore = Semaphore(concurrency);
    final List<Future<VideoProcessResult>> futures = [];
    
    for (File file in filesToProcess) {
      final future = semaphore.acquire().then((_) async {
        try {
          final result = await _processSingleVideo(file);
          processedCount++;
          onProgress?.call(processedCount, videoFiles.length, p.basename(file.path));
          return result;
        } finally {
          semaphore.release();
        }
      });
      futures.add(future);
    }
    
    // 等待所有任务完成
    final processingResults = await Future.wait(futures);
    results.addAll(processingResults);
    
    debugPrint('ConcurrentVideoProcessor: 处理完成。成功: ${results.where((r) => r.success).length}, 失败: ${results.where((r) => !r.success).length}, 跳过: $skippedCount');
    return results;
  }
  
  /// 处理单个视频文件
  static Future<VideoProcessResult> _processSingleVideo(File videoFile) async {
    try {
      final videoInfo = await DandanplayService.getVideoInfo(videoFile.path)
          .timeout(_requestTimeout, onTimeout: () {
        throw TimeoutException('获取视频信息超时 (${p.basename(videoFile.path)})');
      });
      
      if (videoInfo['isMatched'] == true && 
          videoInfo['matches'] != null && 
          (videoInfo['matches'] as List).isNotEmpty) {
        
        final match = videoInfo['matches'][0];
        final animeIdFromMatch = match['animeId'] as int?;
        final episodeIdFromMatch = match['episodeId'] as int?;
        final animeTitleFromMatch = (match['animeTitle'] as String?)?.isNotEmpty == true
            ? match['animeTitle'] as String
            : p.basenameWithoutExtension(videoFile.path);
        final episodeTitleFromMatch = match['episodeTitle'] as String?;
        
        if (animeIdFromMatch != null && episodeIdFromMatch != null) {
          WatchHistoryItem? existingItem = await WatchHistoryManager.getHistoryItem(videoFile.path);
          final int durationFromMatch = (videoInfo['duration'] is int)
              ? videoInfo['duration'] as int
              : (existingItem?.duration ?? 0);
          
          WatchHistoryItem itemToSave;
          if (existingItem != null) {
            if (existingItem.watchProgress > 0.01 && !existingItem.isFromScan) {
              // 保留用户的观看进度
              itemToSave = WatchHistoryItem(
                filePath: existingItem.filePath,
                animeName: animeTitleFromMatch,
                episodeTitle: episodeTitleFromMatch,
                episodeId: episodeIdFromMatch,
                animeId: animeIdFromMatch,
                watchProgress: existingItem.watchProgress,
                lastPosition: existingItem.lastPosition,
                duration: durationFromMatch,
                lastWatchTime: DateTime.now(),
                thumbnailPath: existingItem.thumbnailPath,
                isFromScan: false
              );
            } else {
              // 更新扫描项目
              itemToSave = WatchHistoryItem(
                filePath: videoFile.path,
                animeName: animeTitleFromMatch,
                episodeTitle: episodeTitleFromMatch,
                episodeId: episodeIdFromMatch,
                animeId: animeIdFromMatch,
                watchProgress: existingItem.watchProgress,
                lastPosition: existingItem.lastPosition,
                duration: durationFromMatch,
                lastWatchTime: DateTime.now(),
                thumbnailPath: existingItem.thumbnailPath,
                isFromScan: true
              );
            }
          } else {
            // 新扫描项目
            itemToSave = WatchHistoryItem(
              filePath: videoFile.path,
              animeName: animeTitleFromMatch,
              episodeTitle: episodeTitleFromMatch,
              episodeId: episodeIdFromMatch,
              animeId: animeIdFromMatch,
              watchProgress: 0.0,
              lastPosition: 0,
              duration: durationFromMatch,
              lastWatchTime: DateTime.now(),
              thumbnailPath: null,
              isFromScan: true
            );
          }
          
          await WatchHistoryManager.addOrUpdateHistory(itemToSave);
          
          return VideoProcessResult(
            filePath: videoFile.path,
            success: true,
            historyItem: itemToSave,
            animeTitle: animeTitleFromMatch,
          );
        } else {
          return VideoProcessResult(
            filePath: videoFile.path,
            success: false,
            errorMessage: '缺少ID',
          );
        }
      } else {
        return VideoProcessResult(
          filePath: videoFile.path,
          success: false,
          errorMessage: '未匹配',
        );
      }
    } on TimeoutException {
      return VideoProcessResult(
        filePath: videoFile.path,
        success: false,
        errorMessage: '超时',
      );
    } catch (e) {
      return VideoProcessResult(
        filePath: videoFile.path,
        success: false,
        errorMessage: '错误: ${e.toString().substring(0, min(e.toString().length, 30))}',
      );
    }
  }
  
  /// 根据文件数量计算最优并发数
  static int _calculateOptimalConcurrency(int fileCount) {
    if (fileCount <= 2) return fileCount;
    if (fileCount <= 4) return fileCount;
    return _maxConcurrency; // 最多4个并发
  }
}

/// 信号量实现，用于控制并发数量
class Semaphore {
  final int maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();
  
  Semaphore(this.maxCount) : _currentCount = maxCount;
  
  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }
    
    final completer = Completer<void>();
    _waitQueue.addLast(completer);
    return completer.future;
  }
  
  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}