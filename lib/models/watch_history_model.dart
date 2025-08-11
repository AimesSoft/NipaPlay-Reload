import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'watch_history_database.dart'; // 添加引入数据库类
import 'package:nipaplay/utils/storage_service.dart';

class WatchHistoryItem {
  String filePath;
  String animeName;
  String? episodeTitle;
  int? episodeId;
  int? animeId;
  double watchProgress;
  int lastPosition;
  int duration;
  DateTime lastWatchTime;
  String? thumbnailPath;
  bool isFromScan;
  String? videoHash; // 添加视频哈希值字段，用于弹幕匹配

  WatchHistoryItem({
    required this.filePath,
    required this.animeName,
    this.episodeTitle,
    this.episodeId,
    this.animeId,
    required this.watchProgress,
    required this.lastPosition,
    required this.duration,
    required this.lastWatchTime,
    this.thumbnailPath,
    this.isFromScan = false,
    this.videoHash,  // 添加哈希值参数
  });

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'animeName': animeName,
      'episodeTitle': episodeTitle,
      'episodeId': episodeId,
      'animeId': animeId,
      'watchProgress': watchProgress,
      'lastPosition': lastPosition,
      'duration': duration,
      'lastWatchTime': lastWatchTime.toIso8601String(),
      'thumbnailPath': thumbnailPath,
      'isFromScan': isFromScan,
      'videoHash': videoHash, // 添加视频哈希值
    };
  }

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) {
    return WatchHistoryItem(
      filePath: json['filePath'],
      animeName: json['animeName'] ?? path.basename(json['filePath']),
      episodeTitle: json['episodeTitle'],
      episodeId: json['episodeId'],
      animeId: json['animeId'],
      watchProgress: json['watchProgress'] ?? 0.0,
      lastPosition: json['lastPosition'] ?? 0,
      duration: json['duration'] ?? 0,
      lastWatchTime: json['lastWatchTime'] != null
          ? DateTime.parse(json['lastWatchTime'])
          : DateTime.now(),
      thumbnailPath: json['thumbnailPath'],
      isFromScan: json['isFromScan'] ?? false,
      videoHash: json['videoHash'], // 添加视频哈希值
    );
  }

  WatchHistoryItem copyWith({
    String? filePath,
    String? animeName,
    String? episodeTitle,
    int? episodeId,
    int? animeId,
    double? watchProgress,
    int? lastPosition,
    int? duration,
    DateTime? lastWatchTime,
    String? thumbnailPath,
    bool? isFromScan,
    String? videoHash,
  }) {
    return WatchHistoryItem(
      filePath: filePath ?? this.filePath,
      animeName: animeName ?? this.animeName,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      episodeId: episodeId ?? this.episodeId,
      animeId: animeId ?? this.animeId,
      watchProgress: watchProgress ?? this.watchProgress,
      lastPosition: lastPosition ?? this.lastPosition,
      duration: duration ?? this.duration,
      lastWatchTime: lastWatchTime ?? this.lastWatchTime,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isFromScan: isFromScan ?? this.isFromScan,
      videoHash: videoHash ?? this.videoHash,
    );
  }
}

class WatchHistoryManager {
  static const String _historyFileName = 'watch_history.json';
  static late String _historyFilePath;
  static bool _initialized = false;
  static bool _isWriting = false; // 添加写入锁标志
  static final List<WatchHistoryItem> _cachedItems = []; // 添加内存缓存
  static DateTime _lastWriteTime = DateTime.now(); // 记录最后写入时间
  static bool _migratedToDatabase = false; // 标记是否已迁移到数据库
  // 控制是否需要重绘的标志
  static bool _shouldnotifyListeners = true;

  // 设置是否需要重绘的方法
  static void setShouldnotifyListeners(bool value) {
    _shouldnotifyListeners = value;
  }

  // 初始化历史记录管理器
  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    try {
      // 使用StorageService获取正确的存储目录
      final io.Directory appDir = await StorageService.getAppStorageDirectory();

      // 设置历史文件路径
      _historyFilePath = path.join(appDir.path, _historyFileName);
      
      // 检查是否已迁移到数据库
      final dbFile = io.File(path.join(appDir.path, 'watch_history.db'));
      _migratedToDatabase = dbFile.existsSync();
      
      // 如果已迁移到数据库，则只从数据库加载
      if (_migratedToDatabase) {
        debugPrint('检测到已迁移到数据库，WatchHistoryManager将只从数据库加载数据');
        // 从数据库预加载缓存
        await _preloadCacheFromDatabase();
      } else {
        // 否则使用旧的JSON文件逻辑
        await _checkAndRecoverFromBackup();
        await _loadCacheFromFile();
      }
      
      _initialized = true;
    } catch (e) {
      debugPrint('初始化观看历史管理器失败: $e');
      rethrow;
    }
  }
  
  // 从数据库预加载缓存
  static Future<void> _preloadCacheFromDatabase() async {
    if (kIsWeb) return;
    try {
      final db = WatchHistoryDatabase.instance;
      final historyItems = await db.getAllWatchHistory();
      _cachedItems.clear();
      _cachedItems.addAll(historyItems);
      debugPrint('从数据库预加载了 ${_cachedItems.length} 条历史记录到缓存');
    } catch (e) {
      debugPrint('从数据库预加载缓存失败: $e');
      _cachedItems.clear();
    }
  }
  
  // 检查文件大小并从备份恢复
  static Future<void> _checkAndRecoverFromBackup() async {
    if (kIsWeb) return;
    // 如果已迁移到数据库，则跳过此步骤
    if (_migratedToDatabase) return;
    
    final file = io.File(_historyFilePath);
    if (!file.existsSync()) {
      // 文件不存在，尝试从备份恢复
      await _tryRecoverFromBackup(true);
      return;
    }
    
    // 获取当前文件大小
    final int currentSize = await file.length();
    
    // 检查自动备份文件
    final autoBackupFile = io.File('$_historyFilePath.bak.auto');
    if (autoBackupFile.existsSync()) {
      final int backupSize = await autoBackupFile.length();
      
      // 如果当前文件比备份小很多(小于70%)，可能是数据丢失
      if (currentSize < backupSize * 0.7 && backupSize > 50) {
        await _recoverFromSpecificBackup(autoBackupFile.path);
        return;
      }
    }
    
    // 检查时间戳备份文件（从最新的开始）
    final directory = file.parent;
    final List<io.FileSystemEntity> entities = await directory.list().toList();
    final List<io.File> backupFiles = [];
    
    for (var entity in entities) {
      if (entity is io.File && 
          entity.path.startsWith('$_historyFilePath.bak.') && 
          !entity.path.endsWith('.auto')) {
        backupFiles.add(entity);
      }
    }
    
    // 按修改时间从新到旧排序
    backupFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    
    // 检查最新的备份
    if (backupFiles.isNotEmpty) {
      final latestBackup = backupFiles.first;
      final int backupSize = await latestBackup.length();
      
      // 如果当前文件比备份小很多(小于70%)，可能是数据丢失
      if (currentSize < backupSize * 0.7 && backupSize > 50) {
        await _recoverFromSpecificBackup(latestBackup.path);
        return;
      }
    }
  }
  
  // 尝试从备份恢复
  static Future<void> _tryRecoverFromBackup(bool fileNotExists) async {
    if (kIsWeb) return;
    // 首先检查自动备份
    final autoBackupFile = io.File('$_historyFilePath.bak.auto');
    if (autoBackupFile.existsSync()) {
      await _recoverFromSpecificBackup(autoBackupFile.path);
      return;
    }
    
    // 然后检查普通备份
    final backupFile = io.File('$_historyFilePath.bak');
    if (backupFile.existsSync()) {
      await _recoverFromSpecificBackup(backupFile.path);
      return;
    }
    
    // 最后检查时间戳备份
    final directory = io.Directory(path.dirname(_historyFilePath));
    if (!directory.existsSync()) return;
    
    final List<io.FileSystemEntity> entities = await directory.list().toList();
    final List<io.File> backupFiles = [];
    
    for (var entity in entities) {
      if (entity is io.File && entity.path.startsWith('$_historyFilePath.bak.')) {
        backupFiles.add(entity);
      }
    }
    
    // 按修改时间从新到旧排序
    backupFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    
    if (backupFiles.isNotEmpty) {
      await _recoverFromSpecificBackup(backupFiles.first.path);
    } else if (fileNotExists) {
      // 如果没有找到任何备份，并且主文件不存在，创建一个空文件
      final file = io.File(_historyFilePath);
      await file.writeAsString('[]');
    }
  }
  
  // 从指定备份文件恢复
  static Future<void> _recoverFromSpecificBackup(String backupPath) async {
    if (kIsWeb) return;
    try {
      final backupFile = io.File(backupPath);
      if (!backupFile.existsSync()) {
        return;
      }
      
      // 读取备份文件内容
      final content = await backupFile.readAsString();
      
      // 验证备份的JSON是否有效
      try {
        json.decode(content);
        
        // 备份有效，恢复到主文件
        final file = io.File(_historyFilePath);
        await file.writeAsString(content);
      } catch (e) {
        // 尝试修复备份
        String fixedContent = content;
        
        // 修复常见的JSON错误
        fixedContent = _fixJsonContent(fixedContent);
        
        try {
          json.decode(fixedContent);
          // 修复成功，恢复修复后的内容
          final file = io.File(_historyFilePath);
          await file.writeAsString(fixedContent);
        } catch (e) {
        }
      }
    } catch (e) {
    }
  }
  
  // 修复JSON内容
  static String _fixJsonContent(String content) {
    // 修复常见的JSON格式错误
    String fixedContent = content;
    
    // 修复意外的额外结束括号
    if (fixedContent.contains('}]":null}]')) {
      fixedContent = fixedContent.replaceAll('}]":null}]', '}]');
    }
    
    // 修复其他可能的格式错误
    fixedContent = fixedContent.replaceAll(',,', ',');
    fixedContent = fixedContent.replaceAll(',]', ']');
    fixedContent = fixedContent.replaceAll('[,', '[');
    
    // 确保是有效的JSON数组
    if (!fixedContent.startsWith('[')) fixedContent = '[$fixedContent';
    if (!fixedContent.endsWith(']')) fixedContent = '$fixedContent]';
    
    return fixedContent;
  }

  // 将文件加载到内存缓存
  static Future<void> _loadCacheFromFile() async {
    if (kIsWeb) return;
    // 如果已迁移到数据库，则跳过此步骤
    if (_migratedToDatabase) return;
    
    try {
      final file = io.File(_historyFilePath);
      if (!file.existsSync()) {
        _cachedItems.clear();
        return;
      }

      final content = await file.readAsString();
      if (content.isEmpty) {
        _cachedItems.clear();
        return;
      }

      try {
        final List<dynamic> jsonList = json.decode(content);
        _cachedItems.clear();
        
        // 安全地解析每个条目，跳过无效的条目
        for (var item in jsonList) {
          try {
            _cachedItems.add(WatchHistoryItem.fromJson(item));
          } catch (e) {
            continue;
          }
        }

        // 按照最后观看时间排序，最近的在前面
        _cachedItems.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      } catch (e) {
        // 尝试修复历史记录文件
        await _fixHistoryFile();
        // 重试加载
        await _retryLoadCache();
      }
    } catch (e) {
      _cachedItems.clear();
    }
  }
  
  // 重试加载缓存
  static Future<void> _retryLoadCache() async {
    if (kIsWeb) return;
    try {
      final file = io.File(_historyFilePath);
      if (!file.existsSync()) {
        _cachedItems.clear();
        return;
      }

      final content = await file.readAsString();
      if (content.isEmpty) {
        _cachedItems.clear();
        return;
      }

      final List<dynamic> jsonList = json.decode(content);
      _cachedItems.clear();
      
      for (var item in jsonList) {
        try {
          _cachedItems.add(WatchHistoryItem.fromJson(item));
        } catch (e) {
          continue;
        }
      }

      _cachedItems.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    } catch (e) {
      // 如果修复后仍然失败，则返回空列表并备份原文件
      await _backupAndClearHistory();
      _cachedItems.clear();
    }
  }

  // 获取所有历史记录
  static Future<List<WatchHistoryItem>> getAllHistory() async {
    if (kIsWeb) return [];
    if (!_initialized) await initialize();
    
    // 如果已迁移到数据库，则直接从数据库获取
    if (_migratedToDatabase) {
      try {
        // 从数据库刷新缓存并返回
        final db = WatchHistoryDatabase.instance;
        final historyItems = await db.getAllWatchHistory();
        _cachedItems.clear();
        _cachedItems.addAll(historyItems);
        return List.from(_cachedItems);
      } catch (e) {
        debugPrint('从数据库获取历史记录失败: $e');
        return List.from(_cachedItems); // 返回现有缓存
      }
    }
    
    // 距上次写入时间超过2秒，刷新缓存
    final now = DateTime.now();
    if (now.difference(_lastWriteTime).inSeconds > 2) {
      await _loadCacheFromFile();
    }
    
    // 返回缓存的副本
    return List.from(_cachedItems);
  }

  // 在修复历史记录文件后重试获取历史记录
  static Future<List<WatchHistoryItem>> _getHistoryAfterFix() async {
    if (kIsWeb) return [];
    await _retryLoadCache();
    return List.from(_cachedItems);
  }

  // 尝试修复历史记录文件
  static Future<void> _fixHistoryFile() async {
    if (kIsWeb) return;
    try {
      final file = io.File(_historyFilePath);
      if (!file.existsSync()) return;

      // 备份原始文件
      final backupPath = '$_historyFilePath.bak';
      await file.copy(backupPath);

      final content = await file.readAsString();
      if (content.isEmpty) return;

      // 尝试修复常见的JSON格式错误
      String fixedContent = _fixJsonContent(content);

      // 验证修复后的JSON是否有效
      try {
        json.decode(fixedContent);
        // 写入修复后的内容
        await file.writeAsString(fixedContent);
      } catch (e) {
        // 如果无法修复，则创建空的历史记录
        await file.writeAsString('[]');
      }
    } catch (e) {
    }
  }

  // 备份并清空历史记录
  static Future<void> _backupAndClearHistory() async {
    if (kIsWeb) return;
    try {
      final file = io.File(_historyFilePath);
      if (!file.existsSync()) return;

      // 创建带时间戳的备份
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final backupPath = '$_historyFilePath.bak.$timestamp';
      await file.copy(backupPath);

      // 清空历史记录
      await file.writeAsString('[]');
      _cachedItems.clear();
    } catch (e) {
    }
  }

  // 添加或更新历史记录
  static Future<void> addOrUpdateHistory(WatchHistoryItem item) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();
    
    // 如果已迁移到数据库，则直接使用数据库API
    if (_migratedToDatabase) {
      try {
        final db = WatchHistoryDatabase.instance;
        await db.insertOrUpdateWatchHistory(item);
        
        // 更新内存缓存，保持同步
        final existingIndex = _cachedItems.indexWhere(
          (element) => element.filePath == item.filePath,
        );
        
        if (existingIndex != -1) {
          _cachedItems[existingIndex] = item;
        } else {
          _cachedItems.add(item);
        }
        
        _cachedItems.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
        _lastWriteTime = DateTime.now();
        return;
      } catch (e) {
        debugPrint('使用数据库更新历史记录失败: $e');
        return;
      }
    }
    
    // 以下代码只在未迁移到数据库时执行（保留原始JSON逻辑）
    
    // 如果正在写入，等待短暂时间后再试
    if (_isWriting) {
      await Future.delayed(const Duration(seconds: 1));
      return addOrUpdateHistory(item);
    }
    
    try {
      _isWriting = true;
      
      // 首先备份当前文件
      final file = io.File(_historyFilePath);
      if (file.existsSync()) {
        final fileLength = await file.length();
        // 只有当文件不为空时才备份，避免备份空文件
        if (fileLength > 5) {
          final backupPath = '$_historyFilePath.bak.auto';
          await file.copy(backupPath);
        }
      }
      
      // 从内存缓存更新
      final existingIndex = _cachedItems.indexWhere(
        (element) => element.filePath == item.filePath,
      );

      if (existingIndex != -1) {
        // 更新已存在的记录
        _cachedItems[existingIndex] = item;
      } else {
        // 添加新记录
        _cachedItems.add(item);
      }
      
      // 重新排序
      _cachedItems.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));

      // 转换为JSON并保存
      final jsonList = _cachedItems.map((item) => item.toJson()).toList();
      final jsonString = json.encode(jsonList);

      await file.writeAsString(jsonString);
      _lastWriteTime = DateTime.now();
      
      // 验证保存后新文件的大小
      final newFileSize = await file.length();
      
      // 如果大小异常小，可能是保存失败
      if (newFileSize < 50 && _cachedItems.length > 1) {
        // 尝试重新保存
        await file.writeAsString(jsonString);
      }
    } catch (e) {
      // 如果更新过程中出错，可能是历史记录文件损坏
      debugPrint('更新观看历史失败: $e');
    } finally {
      _isWriting = false;
    }
  }

  // 获取单个历史记录项
  static Future<WatchHistoryItem?> getHistoryItem(String filePath) async {
    if (kIsWeb) return null;
    try {
      // 如果已迁移到数据库，则直接使用数据库API
      if (_migratedToDatabase) {
        try {
          final db = WatchHistoryDatabase.instance;
          return await db.getHistoryByFilePath(filePath);
        } catch (e) {
          debugPrint('从数据库获取单个历史记录失败: $e');
          // 如果数据库查询失败，尝试从内存缓存查找
        }
      }
      
      // 从内存缓存获取
      for (var item in _cachedItems) {
        if (item.filePath == filePath) {
          return item;
        }
      }
      
      // iOS路径前缀处理
      if (io.Platform.isIOS) {
        String alternativePath;
        if (filePath.startsWith('/private')) {
          // 尝试移除/private前缀
          alternativePath = filePath.replaceFirst('/private', '');
        } else {
          // 尝试添加/private前缀
          alternativePath = '/private$filePath';
        }
        
        for (var item in _cachedItems) {
          if (item.filePath == alternativePath) {
            return item;
          }
        }
      }
      
      // 如果内存缓存中没有，尝试重新加载
      if (!_migratedToDatabase) {
        final historyItems = await getAllHistory();
        
        // 首先尝试精确匹配
        for (var item in historyItems) {
          if (item.filePath == filePath) {
            return item;
          }
        }
        
        // iOS路径前缀处理
        if (io.Platform.isIOS) {
          String alternativePath;
          if (filePath.startsWith('/private')) {
            // 尝试移除/private前缀
            alternativePath = filePath.replaceFirst('/private', '');
          } else {
            // 尝试添加/private前缀
            alternativePath = '/private$filePath';
          }
          
          for (var item in historyItems) {
            if (item.filePath == alternativePath) {
              return item;
            }
          }
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  // 删除历史记录
  static Future<void> removeHistory(String filePath) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();
    
    // 如果已迁移到数据库，则直接使用数据库API
    if (_migratedToDatabase) {
      try {
        final db = WatchHistoryDatabase.instance;
        await db.deleteHistory(filePath);
        
        // 更新内存缓存，保持同步
        _cachedItems.removeWhere((item) => item.filePath == filePath);
        return;
      } catch (e) {
        debugPrint('使用数据库删除历史记录失败: $e');
        return;
      }
    }
    
    // 原始JSON逻辑
    if (_isWriting) {
      await Future.delayed(const Duration(seconds: 1));
      return removeHistory(filePath);
    }

    try {
      _isWriting = true;
      
      // 从内存缓存中移除
      _cachedItems.removeWhere((item) => item.filePath == filePath);

      // 转换为JSON并保存
      final jsonList = _cachedItems.map((item) => item.toJson()).toList();
      final jsonString = json.encode(jsonList);

      final file = io.File(_historyFilePath);
      await file.writeAsString(jsonString);
      _lastWriteTime = DateTime.now();
    } finally {
      _isWriting = false;
    }
  }

  // 清空所有历史记录
  static Future<void> clearAllHistory() async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();
    
    // 如果已迁移到数据库，则直接使用数据库API
    if (_migratedToDatabase) {
      try {
        final db = WatchHistoryDatabase.instance;
        await db.clearAllHistory();
        
        // 清空内存缓存，保持同步
        _cachedItems.clear();
        return;
      } catch (e) {
        debugPrint('使用数据库清空历史记录失败: $e');
        return;
      }
    }
    
    // 原始JSON逻辑
    _cachedItems.clear();
    final file = io.File(_historyFilePath);
    if (await file.exists()) {
      await file.delete();
      // Recreate an empty file
      await file.writeAsString('[]'); 
    }
    _lastWriteTime = DateTime.now();
  }

  // New method to get history item by animeId and episodeId
  static Future<WatchHistoryItem?> getHistoryItemByEpisode(int animeId, int episodeId) async {
    if (kIsWeb) return null;
    if (!_initialized) {
      await initialize();
    }
    
    // 如果已迁移到数据库，则直接使用数据库API
    if (_migratedToDatabase) {
      try {
        final db = WatchHistoryDatabase.instance;
        return await db.getHistoryByEpisode(animeId, episodeId);
      } catch (e) {
        debugPrint('从数据库获取剧集历史记录失败: $e');
        // 从内存缓存查找（仅作为备选方案）
      }
    }

    // 从内存缓存查找
    try {
      return _cachedItems.firstWhere(
        (item) => item.animeId == animeId && item.episodeId == episodeId,
      );
    } catch (e) {
      return null;
    }
  }

  // 获取缓存中的所有历史记录项 (同步方法)
  static List<WatchHistoryItem> getAllCachedHistory() {
    return List.from(_cachedItems);
  }

  // Get items by file path prefix
  static Future<List<WatchHistoryItem>> getItemsByPathPrefix(String pathPrefix) async {
    if (kIsWeb) return [];
    if (!_initialized) await initialize();
    
    // 如果已迁移到数据库，则优先使用数据库API
    if (_migratedToDatabase) {
      try {
        // 假设数据库提供此功能
        // 若数据库未提供此功能，可以考虑从所有记录中筛选
        final allItems = await WatchHistoryDatabase.instance.getAllWatchHistory();
        return allItems.where((item) => item.filePath.startsWith(pathPrefix)).toList();
      } catch (e) {
        debugPrint('从数据库获取前缀历史记录失败: $e');
        // 从内存缓存查找（仅作为备选方案）
      }
    }
    
    return _cachedItems.where((item) => item.filePath.startsWith(pathPrefix)).toList();
  }

  // Remove items by file path prefix
  static Future<void> removeItemsByPathPrefix(String pathPrefix) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();
    
    // 如果已迁移到数据库，则直接使用数据库API
    if (_migratedToDatabase) {
      try {
        final db = WatchHistoryDatabase.instance;
        final count = await db.deleteHistoryByPathPrefix(pathPrefix);
        
        // 更新内存缓存，保持同步
        if (count > 0) {
          _cachedItems.removeWhere((item) => item.filePath.startsWith(pathPrefix));
        }
        return;
      } catch (e) {
        debugPrint('使用数据库删除前缀历史记录失败: $e');
        return;
      }
    }
    
    if (_isWriting) {
      await Future.delayed(const Duration(seconds: 1));
      return removeItemsByPathPrefix(pathPrefix);
    }
    
    try {
      _isWriting = true;
      
      int initialCount = _cachedItems.length;
      _cachedItems.removeWhere((item) => item.filePath.startsWith(pathPrefix));
      
      if (_cachedItems.length < initialCount) {
        final jsonList = _cachedItems.map((item) => item.toJson()).toList();
        final jsonString = json.encode(jsonList);
        
        final file = io.File(_historyFilePath);
        await file.writeAsString(jsonString);
        _lastWriteTime = DateTime.now();
      }
    } finally {
      _isWriting = false;
    }
  }

  // Get all items for a specific animeId
  static Future<List<WatchHistoryItem>> getAllItemsForAnime(int animeId) async {
    if (kIsWeb) return [];
    if (!_initialized) await initialize();
    
    // 如果已迁移到数据库，则优先使用数据库API
    if (_migratedToDatabase) {
      try {
        // 假设数据库提供此功能
        // 若数据库未提供此功能，可以考虑从所有记录中筛选
        final allItems = await WatchHistoryDatabase.instance.getAllWatchHistory();
        return allItems.where((item) => item.animeId == animeId).toList();
      } catch (e) {
        debugPrint('从数据库获取动画历史记录失败: $e');
        // 从内存缓存查找（仅作为备选方案）
      }
    }
    
    return _cachedItems.where((item) => item.animeId == animeId).toList();
  }
  
  // 设置迁移到数据库的标志
  static void setMigratedToDatabase(bool migrated) {
    _migratedToDatabase = migrated;
    debugPrint('WatchHistoryManager 已${migrated ? "标记为" : "取消标记为"}已迁移到数据库');
  }
  
  // 判断是否已迁移到数据库
  static bool isMigratedToDatabase() {
    return _migratedToDatabase;
  }

  // 根据文件路径获取历史记录项
  static Future<WatchHistoryItem?> getHistoryItemByPath(String filePath) async {
    if (kIsWeb) return null;
    await initialize();
    
    if (_migratedToDatabase) {
      // 如果已迁移到数据库，使用数据库查询
      final db = WatchHistoryDatabase.instance;
      return await db.getHistoryByFilePath(filePath);
    } else {
      // 使用原有的JSON逻辑
      final items = await getAllHistory();
      try {
        return items.firstWhere((item) => item.filePath == filePath);
      } catch (e) {
        // 如果在iOS上没找到，尝试使用替代路径
        if (io.Platform.isIOS) {
          String alternativePath;
          if (filePath.startsWith('/private')) {
            alternativePath = filePath.replaceFirst('/private', '');
          } else {
            alternativePath = '/private$filePath';
          }
          
          try {
            return items.firstWhere((item) => item.filePath == alternativePath);
          } catch (e) {
            return null;
          }
        }
        return null;
      }
    }
  }
  
  // 根据动画ID获取该动画的所有剧集历史记录
  static Future<List<WatchHistoryItem>> getHistoryItemsByAnimeId(int animeId) async {
    if (kIsWeb) return [];
    await initialize();
    
    if (_migratedToDatabase) {
      // 如果已迁移到数据库，使用数据库查询
      final db = WatchHistoryDatabase.instance;
      return await db.getHistoryByAnimeId(animeId);
    } else {
      // 使用原有的JSON逻辑
      final items = await getAllHistory();
      return items.where((item) => 
        item.animeId == animeId && item.episodeId != null).toList()
        ..sort((a, b) => (a.episodeId ?? 0).compareTo(b.episodeId ?? 0));
    }
  }
  
  // 获取指定动画的上一集
  static Future<WatchHistoryItem?> getPreviousEpisode(int animeId, int currentEpisodeId) async {
    if (kIsWeb) return null;
    await initialize();
    
    if (_migratedToDatabase) {
      // 如果已迁移到数据库，使用数据库查询
      final db = WatchHistoryDatabase.instance;
      return await db.getPreviousEpisode(animeId, currentEpisodeId);
    } else {
      // 使用原有的JSON逻辑
      final episodes = await getHistoryItemsByAnimeId(animeId);
      final previousEpisodes = episodes
          .where((episode) => episode.episodeId != null && episode.episodeId! < currentEpisodeId)
          .toList();
      
      if (previousEpisodes.isEmpty) return null;
      
      // 按集数降序排列，取第一个（最接近当前集的上一集）
      previousEpisodes.sort((a, b) => (b.episodeId ?? 0).compareTo(a.episodeId ?? 0));
      return previousEpisodes.first;
    }
  }
  
  // 获取指定动画的下一集
  static Future<WatchHistoryItem?> getNextEpisode(int animeId, int currentEpisodeId) async {
    if (kIsWeb) return null;
    await initialize();
    
    if (_migratedToDatabase) {
      // 如果已迁移到数据库，使用数据库查询
      final db = WatchHistoryDatabase.instance;
      return await db.getNextEpisode(animeId, currentEpisodeId);
    } else {
      // 使用原有的JSON逻辑
      final episodes = await getHistoryItemsByAnimeId(animeId);
      final nextEpisodes = episodes
          .where((episode) => episode.episodeId != null && episode.episodeId! > currentEpisodeId)
          .toList();
      
      if (nextEpisodes.isEmpty) return null;
      
      // 按集数升序排列，取第一个（最接近当前集的下一集）
      nextEpisodes.sort((a, b) => (a.episodeId ?? 0).compareTo(b.episodeId ?? 0));
      return nextEpisodes.first;
    }
  }
} 