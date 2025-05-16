import 'package:flutter/material.dart';
import '../models/watch_history_model.dart';
import 'dart:io';
import '../services/file_picker_service.dart';

class WatchHistoryProvider extends ChangeNotifier {
  List<WatchHistoryItem> _history = [];
  bool _isLoading = false;
  bool _isLoaded = false;
  final FilePickerService _filePickerService = FilePickerService();
  
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
      final rawHistory = await WatchHistoryManager.getAllHistory();
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
    
    for (var item in items) {
      bool fileExists = false;
      String originalPath = item.filePath;
      
      // 检查是否为已知无效文件路径，如果是则跳过验证
      if (_knownInvalidPaths.contains(originalPath)) {
        continue;  // 直接跳过已知无效的路径，不输出重复日志
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
        // 只在第一次发现无效路径时打印日志
        debugPrint('跳过无效文件: ${item.filePath}');
      }
    }
    
    return validItems;
  }

  // 清除无效文件路径缓存
  void clearInvalidPathCache() {
    _knownInvalidPaths.clear();
  }

  Future<void> refresh() async {
    await loadHistory();
  }
} 