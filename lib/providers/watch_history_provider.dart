import 'package:flutter/material.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'dart:io';
import 'package:nipaplay/services/file_picker_service.dart';

class WatchHistoryProvider extends ChangeNotifier {
  List<WatchHistoryItem> _history = [];
  bool _isLoading = false;
  bool _isLoaded = false;
  final FilePickerService _filePickerService = FilePickerService();
  final WatchHistoryDatabase _database = WatchHistoryDatabase.instance;
  
  // 缓存已知无效的文件路径，避免重复检查
  final Set<String> _knownInvalidPaths = {};

  List<WatchHistoryItem> get history => _history;
  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;

  Future<void> loadHistory() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    
    try {
      // 迁移JSON数据到SQLite (如果需要)
      await _database.migrateFromJson();
      
      // 从数据库获取历史记录
      final rawHistory = await _database.getAllWatchHistory();
      
      // 过滤掉不存在的文件，并修复iOS路径问题
      _history = await _validateFilePaths(rawHistory);
      _isLoaded = true;
    } catch (e) {
      debugPrint('加载观看历史出错: $e');
      _history = [];
      _isLoaded = false;
    }
    
    _isLoading = false;
    notifyListeners();
  }

  // 验证文件路径并修复iOS路径问题
  Future<List<WatchHistoryItem>> _validateFilePaths(List<WatchHistoryItem> items) async {
    List<WatchHistoryItem> validItems = [];
    List<String> invalidPaths = [];
    
    for (var item in items) {
      bool fileExists = false;
      String originalPath = item.filePath;
      
      // 检查是否为已知无效文件路径，如果是则跳过验证
      if (_knownInvalidPaths.contains(originalPath)) {
        continue;  // 直接跳过已知无效的路径，不输出重复日志
      }
      
      // 跳过Jellyfin和Emby协议URL的文件存在性验证
      if (originalPath.startsWith('jellyfin://') || originalPath.startsWith('emby://')) {
        debugPrint('跳过流媒体协议URL的文件验证: $originalPath');
        validItems.add(item);
        continue;
      }
      
      // 跳过HTTP/HTTPS流媒体URL的文件存在性验证
      if (originalPath.startsWith('http://') || originalPath.startsWith('https://')) {
        debugPrint('跳过流媒体URL的文件验证: $originalPath');
        validItems.add(item);
        continue;
      }
      
      // 1. 直接检查文件是否存在
      fileExists = File(originalPath).existsSync();
      
      // 2. 如果不存在，使用FilePickerService检查并修复路径
      if (!fileExists && Platform.isIOS) {
        // 检查/private前缀问题
        fileExists = _filePickerService.checkFileExists(originalPath);
        
        // 如果仍不存在，尝试获取有效路径
        if (!fileExists) {
          final validPath = await _filePickerService.getValidFilePath(originalPath);
          if (validPath != null) {
            item.filePath = validPath;
            // 更新数据库中的文件路径
            final updatedItem = WatchHistoryItem(
              filePath: validPath,
              animeName: item.animeName,
              episodeTitle: item.episodeTitle,
              episodeId: item.episodeId,
              animeId: item.animeId,
              watchProgress: item.watchProgress,
              lastPosition: item.lastPosition,
              duration: item.duration,
              lastWatchTime: item.lastWatchTime,
              thumbnailPath: item.thumbnailPath,
              isFromScan: item.isFromScan,
            );
            
            await _database.insertOrUpdateWatchHistory(updatedItem);
            // 删除原始路径记录
            await _database.deleteHistory(originalPath);
            fileExists = true;
          }
        }
      }
      
      // 只添加有效的文件
      if (fileExists) {
        validItems.add(item);
      } else {
        // 将无效路径添加到缓存集合
        _knownInvalidPaths.add(originalPath);
        invalidPaths.add(originalPath);
        // 只在第一次发现无效路径时打印日志
        debugPrint('跳过无效文件: ${item.filePath}');
      }
    }
    
    // 从数据库中删除无效的记录
    for (var path in invalidPaths) {
      await _database.deleteHistory(path);
    }
    
    return validItems;
  }

  // 清除无效文件路径缓存
  void clearInvalidPathCache() {
    _knownInvalidPaths.clear();
  }

  // 刷新历史记录
  Future<void> refresh() async {
    await loadHistory();
  }
  
  // 添加或更新历史记录
  Future<void> addOrUpdateHistory(WatchHistoryItem item) async {
    // 添加到数据库
    await _database.insertOrUpdateWatchHistory(item);
    
    // 更新内存中的列表
    final index = _history.indexWhere((element) => element.filePath == item.filePath);
    if (index != -1) {
      _history[index] = item;
    } else {
      _history.add(item);
    }
    
    // 重新排序
    _history.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    
    notifyListeners();
  }
  
  // 根据文件路径获取历史记录
  Future<WatchHistoryItem?> getHistoryItem(String filePath) async {
    return await _database.getHistoryByFilePath(filePath);
  }
  
  // 删除单个历史记录
  Future<void> removeHistory(String filePath) async {
    await _database.deleteHistory(filePath);
    _history.removeWhere((item) => item.filePath == filePath);
    notifyListeners();
  }
  
  // 删除指定前缀的历史记录
  Future<void> removeHistoryByPathPrefix(String pathPrefix) async {
    final count = await _database.deleteHistoryByPathPrefix(pathPrefix);
    if (count > 0) {
      _history.removeWhere((item) => item.filePath.startsWith(pathPrefix));
      notifyListeners();
    }
  }
  
  // 清空所有历史记录
  Future<void> clearAllHistory() async {
    await _database.clearAllHistory();
    _history.clear();
    notifyListeners();
  }
} 