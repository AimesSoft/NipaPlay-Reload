import 'package:flutter/material.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'dart:io';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/utils/storage_service.dart' show StorageService;
import 'package:nipaplay/utils/ios_container_path_fixer.dart';

class WatchHistoryProvider extends ChangeNotifier {
  List<WatchHistoryItem> _history = [];
  bool _isLoading = false;
  bool _isLoaded = false;
  final FilePickerService _filePickerService = FilePickerService();
  final WatchHistoryDatabase _database = WatchHistoryDatabase.instance;
  
  // 缓存已知无效的文件路径，避免重复检查
  final Set<String> _knownInvalidPaths = {};
  
  // ScanService实例，用于监听扫描完成事件
  ScanService? _scanService;

  List<WatchHistoryItem> get history => _history;
  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;
  
  // 设置ScanService监听器
  void setScanService(ScanService scanService) {
    debugPrint('WatchHistoryProvider: setScanService 被调用');
    
    // 移除旧的监听器
    if (_scanService != null) {
      debugPrint('WatchHistoryProvider: 移除旧的ScanService监听器');
      _scanService!.removeListener(_onScanServiceStateChanged);
    }
    
    // 设置新的监听器
    _scanService = scanService;
    _scanService!.addListener(_onScanServiceStateChanged);
    debugPrint('WatchHistoryProvider: 已添加ScanService监听器');
  }
  
  // 扫描状态变化监听器
  void _onScanServiceStateChanged() {
    if (_scanService == null) return;
    
    debugPrint('WatchHistoryProvider: ScanService状态变化 - scanJustCompleted: ${_scanService!.scanJustCompleted}');
    
    if (_scanService!.scanJustCompleted) {
      debugPrint('WatchHistoryProvider: 检测到扫描完成，自动刷新历史记录');
      
      // 延迟刷新，确保扫描结果已保存到数据库
      Future.delayed(const Duration(milliseconds: 100), () {
        refresh();
        // 确认扫描完成事件已处理
        _scanService!.acknowledgeScanCompleted();
      });
    }
  }
  
  @override
  void dispose() {
    // 移除监听器
    if (_scanService != null) {
      _scanService!.removeListener(_onScanServiceStateChanged);
    }
    super.dispose();
  }

  Future<void> loadHistory() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    
    try {
      // 迁移JSON数据到SQLite (如果需要)
      await _database.migrateFromJson();
      
      // 调试：打印数据库全部内容
      await _database.debugPrintAllData();
      
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
        validItems.add(item);
        continue;
      }
      
      // 跳过HTTP/HTTPS流媒体URL的文件存在性验证
      if (originalPath.startsWith('http://') || originalPath.startsWith('https://')) {
        validItems.add(item);
        continue;
      }
      
      // 1. 使用iOS路径修复工具验证并修复路径
      final validPath = await iOSContainerPathFixer.validateAndFixFilePath(originalPath);
      if (validPath != null) {
        fileExists = true;
        
        // 如果路径被修复了，更新记录
        if (validPath != originalPath) {
          // 同时修复缩略图路径
          String? fixedThumbnailPath = item.thumbnailPath;
          if (Platform.isIOS && item.thumbnailPath != null) {
            final fixedThumbnailPathResult = await iOSContainerPathFixer.validateAndFixFilePath(item.thumbnailPath!);
            if (fixedThumbnailPathResult != null) {
              fixedThumbnailPath = fixedThumbnailPathResult;
            }
          }
          
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
            thumbnailPath: fixedThumbnailPath,
            isFromScan: item.isFromScan,
          );
          
          await _database.insertOrUpdateWatchHistory(updatedItem);
          await _database.deleteHistory(originalPath);
          
          debugPrint('iOS路径修复成功: ${item.animeName}');
          validItems.add(updatedItem);
          continue;
        }
      }
      
      // 2. iOS平台的FilePickerService回退处理
      if (!fileExists && Platform.isIOS) {
        fileExists = _filePickerService.checkFileExists(originalPath);
        
        if (!fileExists) {
          final validPath = await _filePickerService.getValidFilePath(originalPath);
          if (validPath != null) {
            item.filePath = validPath;
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