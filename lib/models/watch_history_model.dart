import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

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

  // 初始化历史记录管理器
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final appDir = Directory(path.join(docsDir.path, 'nipaplay'));
      
      // 确保应用目录存在
      if (!appDir.existsSync()) {
        appDir.createSync(recursive: true);
      }

      // 设置历史文件路径
      _historyFilePath = path.join(appDir.path, _historyFileName);
      
      // 检查文件大小与备份大小，如果当前文件异常小于备份，可能是被清空了
      await _checkAndRecoverFromBackup();
      
      // 初始加载到内存缓存
      await _loadCacheFromFile();
      
      _initialized = true;
    } catch (e) {
      //debugPrint('初始化观看历史管理器失败: $e');
      rethrow;
    }
  }
  
  // 检查文件大小并从备份恢复
  static Future<void> _checkAndRecoverFromBackup() async {
    final file = File(_historyFilePath);
    if (!file.existsSync()) {
      // 文件不存在，尝试从备份恢复
      await _tryRecoverFromBackup(true);
      return;
    }
    
    // 获取当前文件大小
    final int currentSize = await file.length();
    //debugPrint('当前历史文件大小: $currentSize 字节');
    
    // 检查自动备份文件
    final autoBackupFile = File('$_historyFilePath.bak.auto');
    if (autoBackupFile.existsSync()) {
      final int backupSize = await autoBackupFile.length();
      //debugPrint('自动备份文件大小: $backupSize 字节');
      
      // 如果当前文件比备份小很多(小于70%)，可能是数据丢失
      if (currentSize < backupSize * 0.7 && backupSize > 50) {
        //debugPrint('警告: 当前历史文件($currentSize字节)比备份文件($backupSize字节)小很多，可能已被清空');
        await _recoverFromSpecificBackup(autoBackupFile.path);
        return;
      }
    }
    
    // 检查时间戳备份文件（从最新的开始）
    final directory = file.parent;
    final List<FileSystemEntity> entities = await directory.list().toList();
    final List<File> backupFiles = [];
    
    for (var entity in entities) {
      if (entity is File && 
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
      //debugPrint('最新时间戳备份文件大小: $backupSize 字节');
      
      // 如果当前文件比备份小很多(小于70%)，可能是数据丢失
      if (currentSize < backupSize * 0.7 && backupSize > 50) {
        //debugPrint('警告: 当前历史文件($currentSize字节)比时间戳备份($backupSize字节)小很多，可能已被清空');
        await _recoverFromSpecificBackup(latestBackup.path);
        return;
      }
    }
  }
  
  // 尝试从备份恢复
  static Future<void> _tryRecoverFromBackup(bool fileNotExists) async {
    // 首先检查自动备份
    final autoBackupFile = File('$_historyFilePath.bak.auto');
    if (autoBackupFile.existsSync()) {
      await _recoverFromSpecificBackup(autoBackupFile.path);
      return;
    }
    
    // 然后检查普通备份
    final backupFile = File('$_historyFilePath.bak');
    if (backupFile.existsSync()) {
      await _recoverFromSpecificBackup(backupFile.path);
      return;
    }
    
    // 最后检查时间戳备份
    final directory = Directory(path.dirname(_historyFilePath));
    if (!directory.existsSync()) return;
    
    final List<FileSystemEntity> entities = await directory.list().toList();
    final List<File> backupFiles = [];
    
    for (var entity in entities) {
      if (entity is File && entity.path.startsWith('$_historyFilePath.bak.')) {
        backupFiles.add(entity);
      }
    }
    
    // 按修改时间从新到旧排序
    backupFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    
    if (backupFiles.isNotEmpty) {
      await _recoverFromSpecificBackup(backupFiles.first.path);
    } else if (fileNotExists) {
      // 如果没有找到任何备份，并且主文件不存在，创建一个空文件
      final file = File(_historyFilePath);
      await file.writeAsString('[]');
      //debugPrint('未找到备份，已创建空历史记录文件');
    }
  }
  
  // 从指定备份文件恢复
  static Future<void> _recoverFromSpecificBackup(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      if (!backupFile.existsSync()) {
        //debugPrint('备份文件不存在: $backupPath');
        return;
      }
      
      // 读取备份文件内容
      final content = await backupFile.readAsString();
      
      // 验证备份的JSON是否有效
      try {
        json.decode(content);
        
        // 备份有效，恢复到主文件
        final file = File(_historyFilePath);
        await file.writeAsString(content);
        //debugPrint('成功从备份恢复: $backupPath');
        
        // 创建额外的恢复记录
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final recoveryLog = File('$_historyFilePath.recovered.$timestamp');
        await recoveryLog.writeAsString('Recovered from: $backupPath\nTime: ${DateTime.now().toIso8601String()}\nSize: ${content.length} bytes');
      } catch (e) {
        //debugPrint('备份文件JSON无效: $e');
        // 尝试修复备份
        String fixedContent = content;
        
        // 修复常见的JSON错误
        fixedContent = _fixJsonContent(fixedContent);
        
        try {
          json.decode(fixedContent);
          // 修复成功，恢复修复后的内容
          final file = File(_historyFilePath);
          await file.writeAsString(fixedContent);
          //debugPrint('成功修复并恢复备份');
        } catch (e) {
          //debugPrint('修复备份失败: $e');
        }
      }
    } catch (e) {
      //debugPrint('从备份恢复失败: $e');
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
    try {
      final file = File(_historyFilePath);
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
            //debugPrint('解析历史记录条目时出错: $e, 条目: $item');
            continue;
          }
        }

        // 按照最后观看时间排序，最近的在前面
        _cachedItems.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      } catch (e) {
        //debugPrint('JSON解析错误: $e');
        //debugPrint('尝试修复历史记录文件...');
        // 尝试修复历史记录文件
        await _fixHistoryFile();
        // 重试加载
        await _retryLoadCache();
      }
    } catch (e) {
      //debugPrint('加载缓存失败: $e');
      _cachedItems.clear();
    }
  }
  
  // 重试加载缓存
  static Future<void> _retryLoadCache() async {
    try {
      final file = File(_historyFilePath);
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
          //debugPrint('修复后仍无法解析条目: $e');
          continue;
        }
      }

      _cachedItems.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    } catch (e) {
      //debugPrint('修复后获取历史记录失败: $e');
      // 如果修复后仍然失败，则返回空列表并备份原文件
      await _backupAndClearHistory();
      _cachedItems.clear();
    }
  }

  // 获取所有历史记录
  static Future<List<WatchHistoryItem>> getAllHistory() async {
    if (!_initialized) await initialize();
    
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
    await _retryLoadCache();
    return List.from(_cachedItems);
  }

  // 尝试修复历史记录文件
  static Future<void> _fixHistoryFile() async {
    try {
      final file = File(_historyFilePath);
      if (!file.existsSync()) return;

      // 备份原始文件
      final backupPath = '$_historyFilePath.bak';
      await file.copy(backupPath);
      //debugPrint('已备份原始历史记录文件至 $backupPath');

      final content = await file.readAsString();
      if (content.isEmpty) return;

      // 尝试修复常见的JSON格式错误
      String fixedContent = _fixJsonContent(content);

      // 验证修复后的JSON是否有效
      try {
        json.decode(fixedContent);
        // 写入修复后的内容
        await file.writeAsString(fixedContent);
        //debugPrint('成功修复历史记录文件');
      } catch (e) {
        //debugPrint('无法修复JSON格式: $e');
        // 如果无法修复，则创建空的历史记录
        await file.writeAsString('[]');
        //debugPrint('已重置为空历史记录');
      }
    } catch (e) {
      //debugPrint('修复历史记录文件失败: $e');
    }
  }

  // 备份并清空历史记录
  static Future<void> _backupAndClearHistory() async {
    try {
      final file = File(_historyFilePath);
      if (!file.existsSync()) return;

      // 创建带时间戳的备份
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final backupPath = '$_historyFilePath.bak.$timestamp';
      await file.copy(backupPath);
      //debugPrint('已创建带时间戳的备份: $backupPath');

      // 清空历史记录
      await file.writeAsString('[]');
      _cachedItems.clear();
      //debugPrint('已清空历史记录文件');
    } catch (e) {
      //debugPrint('备份并清空历史记录失败: $e');
    }
  }

  // 添加或更新历史记录
  static Future<void> addOrUpdateHistory(WatchHistoryItem item) async {
    if (!_initialized) await initialize();
    
    // 如果正在写入，等待短暂时间后再试
    if (_isWriting) {
      //debugPrint('文件正在写入中，等待1秒后重试...');
      await Future.delayed(const Duration(seconds: 1));
      return addOrUpdateHistory(item);
    }
    
    try {
      _isWriting = true;
      
      // 首先备份当前文件
      final file = File(_historyFilePath);
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
        // 更新前输出调试信息
        //debugPrint('更新前的记录: 动画=${_cachedItems[existingIndex].animeName}, 集数=${_cachedItems[existingIndex].episodeTitle}');
        // 更新已存在的记录
        _cachedItems[existingIndex] = item;
        // 更新后输出调试信息
        //debugPrint('更新后的记录: 动画=${item.animeName}, 集数=${item.episodeTitle}');
      } else {
        // 添加新记录
        _cachedItems.add(item);
        //debugPrint('添加新记录: 动画=${item.animeName}, 集数=${item.episodeTitle}');
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
      //debugPrint('保存后的文件大小: $newFileSize 字节，缓存项数量: ${_cachedItems.length}');
      
      // 如果大小异常小，可能是保存失败
      if (newFileSize < 50 && _cachedItems.length > 1) {
        //debugPrint('警告: 保存后文件大小异常小($newFileSize字节)，但缓存项数量为${_cachedItems.length}，可能保存失败');
        // 尝试重新保存
        await file.writeAsString(jsonString);
        final retrySize = await file.length();
        //debugPrint('重试保存后文件大小: $retrySize 字节');
      }
      
      // 验证保存是否成功，重新读取文件
      try {
        final savedContent = await file.readAsString();
        final savedList = json.decode(savedContent) as List;
        
        // 检查保存的记录数量
        if (savedList.length != _cachedItems.length) {
          //debugPrint('警告: 保存的记录数量(${savedList.length})与缓存数量(${_cachedItems.length})不匹配');
        }
        
        // 查找刚刚更新的项目
        Map<String, dynamic>? savedItem;
        try {
          savedItem = savedList.firstWhere(
            (element) => element['filePath'] == item.filePath,
          ) as Map<String, dynamic>;
        } catch (e) {
          savedItem = null;
        }
        
        if (savedItem != null) {
          //debugPrint('保存到文件的记录: 动画=${savedItem['animeName']}, 集数=${savedItem['episodeTitle']}');
        } else {
          //debugPrint('警告: 在保存后的文件中未找到更新的记录');
        }
      } catch (e) {
        //debugPrint('验证保存时出错: $e');
      }
    } catch (e) {
      //debugPrint('添加/更新观看历史失败: $e');
      // 如果更新过程中出错，可能是历史记录文件损坏
      // 尝试修复然后重试
      try {
        await _fixHistoryFile();
        
        // 重新获取历史记录
        await _retryLoadCache();
        
        // 再次尝试更新，但直接修改内存缓存
        final existingIndex = _cachedItems.indexWhere(
          (element) => element.filePath == item.filePath,
        );

        if (existingIndex != -1) {
          _cachedItems[existingIndex] = item;
        } else {
          _cachedItems.add(item);
        }
        
        // 重新排序
        _cachedItems.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
        
        // 保存到文件
        final jsonList = _cachedItems.map((item) => item.toJson()).toList();
        final jsonString = json.encode(jsonList);
        final file = File(_historyFilePath);
        await file.writeAsString(jsonString);
        _lastWriteTime = DateTime.now();
        
        //debugPrint('修复后成功更新历史记录');
      } catch (retryError) {
        //debugPrint('修复后仍无法更新历史记录: $retryError');
      }
    } finally {
      _isWriting = false;
    }
  }

  // 获取单个历史记录项
  static Future<WatchHistoryItem?> getHistoryItem(String filePath) async {
    try {
      // 优先从内存缓存获取
      try {
        return _cachedItems.firstWhere((item) => item.filePath == filePath);
      } catch (e) {
        // 缓存中未找到
      }
      
      // 如果内存缓存中没有，尝试重新加载
      final historyItems = await getAllHistory();
      try {
        return historyItems.firstWhere((item) => item.filePath == filePath);
      } catch (e) {
        return null;
      }
    } catch (e) {
      //debugPrint('获取历史项目失败: $e');
      return null;
    }
  }

  // 删除历史记录
  static Future<void> removeHistory(String filePath) async {
    if (!_initialized) await initialize();
    
    // 如果正在写入，等待短暂时间后再试
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

      final file = File(_historyFilePath);
      await file.writeAsString(jsonString);
      _lastWriteTime = DateTime.now();
    } catch (e) {
      //debugPrint('删除观看历史失败: $e');
    } finally {
      _isWriting = false;
    }
  }

  // 清空所有历史记录
  static Future<void> clearAllHistory() async {
    if (!_initialized) await initialize();
    _cachedItems.clear();
    final file = File(_historyFilePath);
    if (await file.exists()) {
      await file.delete();
      // Recreate an empty file
      await file.writeAsString('[]'); 
    }
    _lastWriteTime = DateTime.now(); 
    //debugPrint('所有观看历史已清除');
  }

  // New method to get history item by animeId and episodeId
  static Future<WatchHistoryItem?> getHistoryItemByEpisode(int animeId, int episodeId) async {
    if (!_initialized) {
      //debugPrint('WatchHistoryManager not initialized. Initializing now...');
      await initialize();
    }

    // Try to find in the memory cache first for performance
    try {
      return _cachedItems.firstWhere(
        (item) => item.animeId == animeId && item.episodeId == episodeId,
      );
    } catch (e) {
      // Not found in cache.
      // Assuming _cachedItems is the single source of truth after initialization.
      ////debugPrint('Item with animeId: $animeId, episodeId: $episodeId not found in memory cache (_cachedItems length: ${_cachedItems.length}).');
      return null;
    }
  }

  // 获取缓存中的所有历史记录项 (同步方法)
  static List<WatchHistoryItem> getAllCachedHistory() {
    return List.from(_cachedItems);
  }

  // NEW: Get items by file path prefix
  static Future<List<WatchHistoryItem>> getItemsByPathPrefix(String pathPrefix) async {
    if (!_initialized) await initialize(); // Ensure initialized
    return _cachedItems.where((item) => item.filePath.startsWith(pathPrefix)).toList();
  }

  // NEW: Remove items by file path prefix
  static Future<void> removeItemsByPathPrefix(String pathPrefix) async {
    if (!_initialized) await initialize();
    if (_isWriting) {
      //debugPrint('WatchHistoryManager: File is being written, retrying removeItemsByPathPrefix in 1s for $pathPrefix');
      await Future.delayed(const Duration(seconds: 1));
      return removeItemsByPathPrefix(pathPrefix); // Retry
    }
    try {
      _isWriting = true;
      int initialCount = _cachedItems.length;
      _cachedItems.removeWhere((item) => item.filePath.startsWith(pathPrefix));
      if (_cachedItems.length < initialCount) {
        final jsonList = _cachedItems.map((item) => item.toJson()).toList();
        final jsonString = json.encode(jsonList);
        final file = File(_historyFilePath);
        await file.writeAsString(jsonString);
        _lastWriteTime = DateTime.now();
        //debugPrint('WatchHistoryManager: Removed ${_initialCount - _cachedItems.length} items with prefix: $pathPrefix and saved.');
      }
    } catch (e) {
      //debugPrint('WatchHistoryManager: Error removing items by prefix $pathPrefix: $e');
      // Optionally, rethrow or handle error (e.g., try to restore from backup or _fixHistoryFile)
    } finally {
      _isWriting = false;
    }
  }

  // NEW: Get all items for a specific animeId
  static Future<List<WatchHistoryItem>> getAllItemsForAnime(int animeId) async {
    if (!_initialized) await initialize();
    return _cachedItems.where((item) => item.animeId == animeId).toList();
  }
  
  // NEW: Remove a single history item by its exact file path (if needed, otherwise removeHistory can be used)
  // This version mirrors the removeItemsByPathPrefix structure for consistency if specific logic is needed.
  // If removeHistory is sufficient, this might be redundant.
  static Future<void> removeHistoryItemByPath(String filePath) async {
    if (!_initialized) await initialize();
    if (_isWriting) {
      //debugPrint('WatchHistoryManager: File is being written, retrying removeHistoryItemByPath in 1s for $filePath');
      await Future.delayed(const Duration(seconds: 1));
      return removeHistoryItemByPath(filePath); // Retry
    }
    try {
      _isWriting = true;
      int initialCount = _cachedItems.length;
      _cachedItems.removeWhere((item) => item.filePath == filePath);
      if (_cachedItems.length < initialCount) {
        final jsonList = _cachedItems.map((item) => item.toJson()).toList();
        final jsonString = json.encode(jsonList);
        final file = File(_historyFilePath);
        await file.writeAsString(jsonString);
        _lastWriteTime = DateTime.now();
        //debugPrint('WatchHistoryManager: Removed item with path: $filePath and saved.');
      }
    } catch (e) {
      //debugPrint('WatchHistoryManager: Error removing item by path $filePath: $e');
    } finally {
      _isWriting = false;
    }
  }
} 