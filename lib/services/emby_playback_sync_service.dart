import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/watch_history_model.dart';
import 'emby_service.dart';

/// Emby播放记录同步服务
/// 基于Jellyfin同步服务实现，适配Emby API接口差异
class EmbyPlaybackSyncService {
  static final EmbyPlaybackSyncService _instance = EmbyPlaybackSyncService._internal();
  factory EmbyPlaybackSyncService() => _instance;
  EmbyPlaybackSyncService._internal();

  final EmbyService _embyService = EmbyService.instance;
  
  // 当前播放状态
  String? _currentItemId;
  String? _currentPlaySessionId;
  bool _isPlaying = false;
  
  /// 开始播放时调用，拉取服务器记录并与本地记录做冲突处理
  Future<WatchHistoryItem?> syncOnPlayStart(String itemId, WatchHistoryItem localHistory) async {
    try {
      debugPrint('[EmbySync] 开始同步播放记录: $itemId (自动播放检查)');
      
      if (!_embyService.isConnected) {
        debugPrint('[EmbySync] Emby未连接，跳过同步');
        return localHistory;
      }
      
      // 1. 获取服务器播放记录
      final serverProgress = await _getServerPlaybackProgress(itemId);
      
      if (serverProgress == null) {
        debugPrint('[EmbySync] 服务器无播放记录，使用本地记录');
        return localHistory;
      }
      
      // 2. 冲突处理：比较上次播放时间
      final serverLastWatchTime = DateTime.parse(serverProgress['LastPlayedDate'] ?? '').toUtc();
      final localLastWatchTime = localHistory.lastWatchTime.toUtc();
      
      debugPrint('[EmbySync] 服务器最后观看时间(UTC): $serverLastWatchTime');
      debugPrint('[EmbySync] 本地最后观看时间(UTC): $localLastWatchTime');
      
      if (serverLastWatchTime.isAfter(localLastWatchTime)) {
        // 服务器记录更新，使用服务器记录
        debugPrint('[EmbySync] 使用服务器记录（更新）');
        return _createHistoryFromServerProgress(itemId, serverProgress, localHistory);
      } else {
        // 本地记录更新，使用本地记录
        debugPrint('[EmbySync] 使用本地记录（更新）');
        return localHistory;
      }
      
    } catch (e) {
      debugPrint('[EmbySync] 同步播放记录失败: $e');
      return localHistory; // 出错时使用本地记录
    }
  }
  
  /// 开始播放时调用，向服务器报告播放开始
  Future<void> reportPlaybackStart(String itemId, WatchHistoryItem historyItem) async {
    try {
      if (!_embyService.isConnected) return;
      
      debugPrint('[EmbySync] 报告播放开始: $itemId');
      
      // 确保清理之前的状态
      _stopProgressSync();
      _currentItemId = null;
      _currentPlaySessionId = null;
      _isPlaying = false;
      
      final playSessionId = _generatePlaySessionId();
      _currentItemId = itemId;
      _currentPlaySessionId = playSessionId;
      _isPlaying = true;
      debugPrint('[EmbySync] 新播放会话已初始化: $playSessionId');
      
      // 构建播放开始信息 - 使用Emby的PlaybackStartInfo格式
      final startInfo = {
        'ItemId': itemId,
        'PositionTicks': (historyItem.lastPosition * 10000).round(), // 转换为ticks
        'PlaySessionId': playSessionId,
        'CanSeek': true,
        'IsPaused': false,
        'IsMuted': false,
        'PlayMethod': 'DirectPlay', // 假设直接播放
        'VolumeLevel': 100,
        'MediaSourceId': itemId, // Emby需要MediaSourceId
      };
      
      // 发送播放开始请求 - Emby使用/emby前缀
      final response = await _makeAuthenticatedRequest(
        '/emby/Sessions/Playing',
        method: 'POST',
        body: json.encode(startInfo),
      );
      
      if (response.statusCode == 204 || response.statusCode == 200) {
        debugPrint('[EmbySync] 播放开始报告成功');
        // 开始定时上传播放进度
        _startProgressSync();
      } else {
        debugPrint('[EmbySync] 播放开始报告失败: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('[EmbySync] 报告播放开始失败: $e');
    }
  }
  
  /// 播放结束时调用，向服务器报告播放结束
  Future<void> reportPlaybackStopped(String itemId, WatchHistoryItem historyItem, {bool isCompleted = false}) async {
    try {
      if (!_embyService.isConnected) return;
      
      debugPrint('[EmbySync] 报告播放结束: $itemId, 是否完成: $isCompleted');
      
      // 停止定时器
      _stopProgressSync();
      
      // 构建播放结束信息 - 使用Emby的PlaybackStopInfo格式
      final stopInfo = {
        'ItemId': itemId,
        'PositionTicks': (historyItem.lastPosition * 10000).round(), // 转换为ticks
        'PlaySessionId': _currentPlaySessionId,
        'Failed': false,
        'MediaSourceId': itemId, // Emby需要MediaSourceId
      };
      
      // 发送播放结束请求 - Emby使用/emby前缀
      final response = await _makeAuthenticatedRequest(
        '/emby/Sessions/Playing/Stopped',
        method: 'POST',
        body: json.encode(stopInfo),
      );
      
      if (response.statusCode == 204 || response.statusCode == 200) {
        debugPrint('[EmbySync] 播放结束报告成功');
        
        // 如果播放完成，标记为已观看
        if (isCompleted) {
          await _markAsWatched(itemId);
        }
      } else {
        debugPrint('[EmbySync] 播放结束报告失败: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('[EmbySync] 报告播放结束失败: $e');
    } finally {
      // 清理状态
      _currentItemId = null;
      _currentPlaySessionId = null;
      _isPlaying = false;
      debugPrint('[EmbySync] 播放状态已清理，准备下一集播放');
    }
  }
  
  /// 获取服务器播放进度
  Future<Map<String, dynamic>?> _getServerPlaybackProgress(String itemId) async {
    try {
      debugPrint('[EmbySync] 开始获取服务器播放进度: $itemId');
      
      // 使用Emby的用户数据API - 需要添加/emby前缀并使用正确的userId
      final userDataResponse = await _makeAuthenticatedRequest(
        '/emby/Users/${_embyService.userId}/Items/$itemId',
      );
      
      if (userDataResponse.statusCode != 200) {
        debugPrint('[EmbySync] 获取用户数据失败: ${userDataResponse.statusCode}');
        return null;
      }
      
      final itemData = json.decode(userDataResponse.body);
      debugPrint('[EmbySync] 原始项目数据响应: ${userDataResponse.body}');
      
      final userData = itemData['UserData'];
      if (userData == null) {
        debugPrint('[EmbySync] 项目无用户数据');
        return null;
      }
      
      final playbackPositionTicks = userData['PlaybackPositionTicks'] ?? 0;
      final playCount = userData['PlayCount'] ?? 0;
      final lastPlayedDate = userData['LastPlayedDate'];
      final unplayedItemCount = userData['UnplayedItemCount'];
      
      debugPrint('[EmbySync] 用户数据: playbackPositionTicks=$playbackPositionTicks, playCount=$playCount, lastPlayedDate=$lastPlayedDate');
      
      if (playCount == 0 || lastPlayedDate == null) {
        debugPrint('[EmbySync] 项目从未播放过');
        return null;
      }
      
      return {
        'PlayCount': playCount,
        'LastPlayedDate': lastPlayedDate,
        'PlaybackPositionTicks': playbackPositionTicks,
        'UnplayedItemCount': unplayedItemCount,
      };
      
    } catch (e) {
      debugPrint('[EmbySync] 获取服务器播放进度失败: $e');
      return null;
    }
  }
  
  /// 从服务器进度创建历史记录
  WatchHistoryItem _createHistoryFromServerProgress(String itemId, Map<String, dynamic> serverProgress, WatchHistoryItem originalHistory) {
    final positionTicks = serverProgress['PlaybackPositionTicks'] ?? 0;
    // Emby ticks 转换为毫秒：1 tick = 100 nanoseconds = 0.0001 milliseconds
    final positionMs = (positionTicks / 10000).round(); // 转换为毫秒
    
    debugPrint('[EmbySync] 服务器播放位置: ${positionTicks} ticks = ${positionMs} ms (约${(positionMs / 1000 / 60).toStringAsFixed(1)}分钟)');
    
    return WatchHistoryItem(
      filePath: originalHistory.filePath,
      animeName: originalHistory.animeName,
      episodeTitle: originalHistory.episodeTitle,
      episodeId: originalHistory.episodeId,
      animeId: originalHistory.animeId,
      watchProgress: originalHistory.watchProgress, // 保持原有的观看进度
      lastPosition: positionMs, // 使用服务器位置
      duration: originalHistory.duration, // 保持原有的时长
      lastWatchTime: DateTime.parse(serverProgress['LastPlayedDate']),
      thumbnailPath: originalHistory.thumbnailPath, // 保持原有的缩略图
    );
  }
  
  /// 开始定时同步播放进度
  void _startProgressSync() {
    _stopProgressSync(); // 先停止之前的定时器
    
    // 移除ping机制，因为进度同步已经足够保持会话活跃
    // 现在完全依赖VideoPlayerState的进度同步
    debugPrint('[EmbySync] 播放会话同步已启动（无ping机制）');
  }
  
  /// 停止定时同步
  void _stopProgressSync() {
    // 已移除定时器机制，现在只是清理状态
    debugPrint('[EmbySync] 停止播放会话同步');
  }
  
  /// 标记为已观看
  Future<void> _markAsWatched(String itemId) async {
    try {
      // Emby使用不同的API路径标记为已观看
      final response = await _makeAuthenticatedRequest(
        '/emby/Users/${_embyService.userId}/PlayedItems/$itemId',
        method: 'POST',
      );
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[EmbySync] 标记为已观看成功: $itemId');
      } else {
        debugPrint('[EmbySync] 标记为已观看失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[EmbySync] 标记为已观看失败: $e');
    }
  }
  
  /// 生成播放会话ID
  String _generatePlaySessionId() {
    return 'nipaplay_${DateTime.now().millisecondsSinceEpoch}_${_currentItemId}';
  }
  
  /// 发送认证请求
  Future<http.Response> _makeAuthenticatedRequest(
    String endpoint, {
    String method = 'GET',
    String? body,
  }) async {
    if (!_embyService.isConnected || _embyService.accessToken == null) {
      throw Exception('Emby未连接或未认证');
    }
    
    final url = '${_embyService.serverUrl}$endpoint';
    final headers = {
      'Content-Type': 'application/json',
      'X-Emby-Token': _embyService.accessToken!,
    };
    
    final uri = Uri.parse(url);
    
    // 添加超时处理，避免长时间等待
    const timeout = Duration(seconds: 10);
    
    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(uri, headers: headers).timeout(timeout);
      case 'POST':
        return await http.post(uri, headers: headers, body: body).timeout(timeout);
      default:
        throw Exception('不支持的HTTP方法: $method');
    }
  }
  
  /// 手动同步播放进度（供外部调用）
  Future<void> syncCurrentProgress(int positionMs) async {
    if (!_isPlaying || _currentItemId == null) return;
    
    try {
      // 使用Emby的PlaybackProgressInfo格式
      final progressInfo = {
        'ItemId': _currentItemId,
        'PositionTicks': (positionMs * 10000).round(),
        'PlaySessionId': _currentPlaySessionId,
        'CanSeek': true,
        'IsPaused': false,
        'IsMuted': false,
        'PlayMethod': 'DirectPlay',
        'VolumeLevel': 100,
        'MediaSourceId': _currentItemId, // Emby需要MediaSourceId
      };
      
      final response = await _makeAuthenticatedRequest(
        '/emby/Sessions/Playing/Progress',
        method: 'POST',
        body: json.encode(progressInfo),
      );
      
      if (response.statusCode == 204 || response.statusCode == 200) {
        debugPrint('[EmbySync] 手动同步播放进度成功: ${positionMs}ms');
      } else {
        debugPrint('[EmbySync] 手动同步播放进度失败: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('[EmbySync] 手动同步播放进度失败: $e');
    }
  }

  /// 报告播放暂停状态
  Future<void> reportPlaybackPaused(int positionMs) async {
    if (!_isPlaying || _currentItemId == null) return;
    
    try {
      // 使用Emby的PlaybackProgressInfo格式
      final progressInfo = {
        'ItemId': _currentItemId,
        'PositionTicks': (positionMs * 10000).round(),
        'PlaySessionId': _currentPlaySessionId,
        'CanSeek': true,
        'IsPaused': true, // 设置为暂停状态
        'IsMuted': false,
        'PlayMethod': 'DirectPlay',
        'VolumeLevel': 100,
        'MediaSourceId': _currentItemId, // Emby需要MediaSourceId
      };
      
      final response = await _makeAuthenticatedRequest(
        '/emby/Sessions/Playing/Progress',
        method: 'POST',
        body: json.encode(progressInfo),
      );
      
      if (response.statusCode == 204 || response.statusCode == 200) {
        debugPrint('[EmbySync] 播放暂停状态报告成功: ${positionMs}ms');
      } else {
        debugPrint('[EmbySync] 播放暂停状态报告失败: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('[EmbySync] 播放暂停状态报告失败: $e');
    }
  }
  
  /// 清理资源
  void dispose() {
    _stopProgressSync();
    _currentItemId = null;
    _currentPlaySessionId = null;
    _isPlaying = false;
  }
}
