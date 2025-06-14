import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'watch_history_model.dart';

class WatchHistoryDatabase {
  static Database? _database;
  static final WatchHistoryDatabase instance = WatchHistoryDatabase._init();
  static const String _dbName = 'watch_history.db';
  static const int _dbVersion = 1;
  static bool _migrationCompleted = false;
  
  // 私有构造函数
  WatchHistoryDatabase._init();
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    
    _database = await _initDB();
    return _database!;
  }
  
  // 初始化数据库
  Future<Database> _initDB() async {
    // 确保在桌面平台上初始化SQLite FFI
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    final Directory documentsDir = await getApplicationDocumentsDirectory();
    final String dbPath = path.join(documentsDir.path, 'nipaplay', _dbName);
    
    // 确保目录存在
    final dbDir = Directory(path.dirname(dbPath));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    
    return await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }
  
  // 创建数据库表
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE watch_history(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_path TEXT UNIQUE NOT NULL,
      anime_name TEXT NOT NULL,
      episode_title TEXT,
      episode_id INTEGER,
      anime_id INTEGER,
      watch_progress REAL NOT NULL,
      last_position INTEGER NOT NULL,
      duration INTEGER NOT NULL,
      last_watch_time TEXT NOT NULL,
      thumbnail_path TEXT,
      is_from_scan INTEGER NOT NULL
    )
    ''');
    
    // 创建索引以加快查询速度
    await db.execute('CREATE INDEX idx_file_path ON watch_history(file_path)');
    await db.execute('CREATE INDEX idx_anime_id ON watch_history(anime_id)');
    await db.execute('CREATE INDEX idx_last_watch_time ON watch_history(last_watch_time)');
  }
  
  // 数据库升级处理
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _createDB(db, newVersion);
    }
    // 未来版本可以在这里添加更多迁移代码
  }
  
  // 关闭数据库连接
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
  
  // 从JSON迁移数据
  Future<void> migrateFromJson() async {
    // 避免重复迁移
    if (_migrationCompleted) return;
    
    try {
      final db = await database;
      // 检查是否已经有数据
      final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM watch_history'));
      
      // 如果数据库已经有数据，不执行迁移
      if (count != null && count > 0) {
        _migrationCompleted = true;
        return;
      }
      
      // 从JSON获取历史记录
      final jsonItems = await WatchHistoryManager.getAllHistory();
      if (jsonItems.isEmpty) {
        _migrationCompleted = true;
        return;
      }
      
      // 开始事务以提高性能
      await db.transaction((txn) async {
        for (var item in jsonItems) {
          await txn.insert(
            'watch_history',
            {
              'file_path': item.filePath,
              'anime_name': item.animeName,
              'episode_title': item.episodeTitle,
              'episode_id': item.episodeId,
              'anime_id': item.animeId,
              'watch_progress': item.watchProgress,
              'last_position': item.lastPosition,
              'duration': item.duration,
              'last_watch_time': item.lastWatchTime.toIso8601String(),
              'thumbnail_path': item.thumbnailPath,
              'is_from_scan': item.isFromScan ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      
      debugPrint('成功从JSON迁移了 ${jsonItems.length} 条观看记录到SQLite数据库');
      
      // 迁移成功后，获取并移除原JSON文件
      try {
        final jsonFilePath = await _getJsonFilePath();
        if (jsonFilePath != null) {
          final jsonFile = File(jsonFilePath);
          if (jsonFile.existsSync()) {
            // 先创建备份，以防万一
            final backupPath = '$jsonFilePath.bak.migrated';
            await jsonFile.copy(backupPath);
            
            // 移除原始JSON文件
            await jsonFile.delete();
            debugPrint('原JSON文件已备份到$backupPath并移除');
          }
        }
        
        // 移除所有相关的备份和恢复文件
        await _cleanupJsonBackups();
      } catch (e) {
        debugPrint('移除JSON文件失败: $e，但迁移已成功完成');
      }
      
      // 设置WatchHistoryManager的迁移标志
      try {
        WatchHistoryManager.setMigratedToDatabase(true);
      } catch (e) {
        debugPrint('设置WatchHistoryManager迁移标志失败: $e');
      }
      
      _migrationCompleted = true;
    } catch (e) {
      debugPrint('迁移观看记录失败: $e');
      // 迁移失败不应该阻止应用继续运行
    }
  }
  
  // 清理原有的JSON备份文件
  Future<void> _cleanupJsonBackups() async {
    try {
      final jsonFilePath = await _getJsonFilePath();
      if (jsonFilePath == null) return;
      
      final directory = Directory(path.dirname(jsonFilePath));
      if (!directory.existsSync()) return;
      
      final List<FileSystemEntity> entities = await directory.list().toList();
      for (var entity in entities) {
        if (entity is File && 
            (entity.path.endsWith('.bak') || 
             entity.path.contains('.bak.') || 
             entity.path.contains('.recovered.'))) {
          try {
            await entity.delete();
            debugPrint('已删除备份文件: ${entity.path}');
          } catch (e) {
            debugPrint('删除备份文件失败: ${entity.path}, 错误: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('清理JSON备份文件失败: $e');
    }
  }
  
  // 获取JSON文件路径
  Future<String?> _getJsonFilePath() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final appDir = Directory(path.join(docsDir.path, 'nipaplay'));
      
      if (!appDir.existsSync()) {
        return null;
      }
      
      return path.join(appDir.path, 'watch_history.json');
    } catch (e) {
      debugPrint('获取JSON文件路径失败: $e');
      return null;
    }
  }
  
  // 插入或更新一条观看记录
  Future<void> insertOrUpdateWatchHistory(WatchHistoryItem item) async {
    final db = await database;
    
    // 添加调试日志
    debugPrint('数据库保存历史记录: filePath=${item.filePath}, animeName=${item.animeName}, episodeId=${item.episodeId}, animeId=${item.animeId}');
    
    try {
      await db.insert(
        'watch_history',
        {
          'file_path': item.filePath,
          'anime_name': item.animeName,
          'episode_title': item.episodeTitle,
          'episode_id': item.episodeId,
          'anime_id': item.animeId,
          'watch_progress': item.watchProgress,
          'last_position': item.lastPosition,
          'duration': item.duration,
          'last_watch_time': item.lastWatchTime.toIso8601String(),
          'thumbnail_path': item.thumbnailPath,
          'is_from_scan': item.isFromScan ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('插入/更新观看历史失败: $e');
      // 尝试更新而不是插入
      try {
        await db.update(
          'watch_history',
          {
            'anime_name': item.animeName,
            'episode_title': item.episodeTitle,
            'episode_id': item.episodeId,
            'anime_id': item.animeId,
            'watch_progress': item.watchProgress,
            'last_position': item.lastPosition,
            'duration': item.duration,
            'last_watch_time': item.lastWatchTime.toIso8601String(),
            'thumbnail_path': item.thumbnailPath,
            'is_from_scan': item.isFromScan ? 1 : 0,
          },
          where: 'file_path = ?',
          whereArgs: [item.filePath],
        );
      } catch (updateError) {
        debugPrint('更新观看历史也失败: $updateError');
        rethrow;
      }
    }
  }
  
  // 获取所有观看历史，按最后观看时间排序
  Future<List<WatchHistoryItem>> getAllWatchHistory() async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'watch_history',
        orderBy: 'last_watch_time DESC',
      );
      
      return maps.map((map) => _mapToWatchHistoryItem(map)).toList();
    } catch (e) {
      debugPrint('获取所有观看历史失败: $e');
      return [];
    }
  }
  
  // 根据文件路径获取单个历史记录
  Future<WatchHistoryItem?> getHistoryByFilePath(String filePath) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'watch_history',
        where: 'file_path = ?',
        whereArgs: [filePath],
        limit: 1,
      );
      
      if (maps.isEmpty) {
        // 如果在iOS上没找到，尝试使用替代路径
        if (Platform.isIOS) {
          String alternativePath;
          if (filePath.startsWith('/private')) {
            alternativePath = filePath.replaceFirst('/private', '');
          } else {
            alternativePath = '/private$filePath';
          }
          
          final List<Map<String, dynamic>> altMaps = await db.query(
            'watch_history',
            where: 'file_path = ?',
            whereArgs: [alternativePath],
            limit: 1,
          );
          
          if (altMaps.isNotEmpty) {
            return _mapToWatchHistoryItem(altMaps.first);
          }
        }
        return null;
      }
      
      return _mapToWatchHistoryItem(maps.first);
    } catch (e) {
      debugPrint('获取单个观看历史失败: $e');
      return null;
    }
  }
  
  // 根据番剧ID和集数ID获取历史记录
  Future<WatchHistoryItem?> getHistoryByEpisode(int animeId, int episodeId) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'watch_history',
        where: 'anime_id = ? AND episode_id = ?',
        whereArgs: [animeId, episodeId],
        limit: 1,
      );
      
      if (maps.isEmpty) return null;
      
      return _mapToWatchHistoryItem(maps.first);
    } catch (e) {
      debugPrint('按剧集ID获取观看历史失败: $e');
      return null;
    }
  }
  
  // 根据动画ID获取该动画的所有剧集历史记录，按集数排序
  Future<List<WatchHistoryItem>> getHistoryByAnimeId(int animeId) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'watch_history',
        where: 'anime_id = ? AND episode_id IS NOT NULL',
        whereArgs: [animeId],
        orderBy: 'episode_id ASC',
      );
      
      return maps.map((map) => _mapToWatchHistoryItem(map)).toList();
    } catch (e) {
      debugPrint('按动画ID获取剧集历史失败: $e');
      return [];
    }
  }
  
  // 获取指定动画的上一集
  Future<WatchHistoryItem?> getPreviousEpisode(int animeId, int currentEpisodeId) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'watch_history',
        where: 'anime_id = ? AND episode_id < ? AND episode_id IS NOT NULL',
        whereArgs: [animeId, currentEpisodeId],
        orderBy: 'episode_id DESC',
        limit: 1,
      );
      
      if (maps.isEmpty) return null;
      
      return _mapToWatchHistoryItem(maps.first);
    } catch (e) {
      debugPrint('获取上一集失败: $e');
      return null;
    }
  }
  
  // 获取指定动画的下一集
  Future<WatchHistoryItem?> getNextEpisode(int animeId, int currentEpisodeId) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'watch_history',
        where: 'anime_id = ? AND episode_id > ? AND episode_id IS NOT NULL',
        whereArgs: [animeId, currentEpisodeId],
        orderBy: 'episode_id ASC',
        limit: 1,
      );
      
      if (maps.isEmpty) return null;
      
      return _mapToWatchHistoryItem(maps.first);
    } catch (e) {
      debugPrint('获取下一集失败: $e');
      return null;
    }
  }
  
  // 删除单个历史记录
  Future<void> deleteHistory(String filePath) async {
    final db = await database;
    
    try {
      await db.delete(
        'watch_history',
        where: 'file_path = ?',
        whereArgs: [filePath],
      );
    } catch (e) {
      debugPrint('删除观看历史失败: $e');
      rethrow;
    }
  }
  
  // 根据路径前缀删除多个历史记录
  Future<int> deleteHistoryByPathPrefix(String pathPrefix) async {
    final db = await database;
    
    try {
      return await db.delete(
        'watch_history',
        where: 'file_path LIKE ?',
        whereArgs: ['$pathPrefix%'],
      );
    } catch (e) {
      debugPrint('删除多个观看历史失败: $e');
      return 0;
    }
  }
  
  // 清空所有历史记录
  Future<void> clearAllHistory() async {
    final db = await database;
    
    try {
      await db.delete('watch_history');
    } catch (e) {
      debugPrint('清空观看历史失败: $e');
      rethrow;
    }
  }
  
  // 将数据库行映射为WatchHistoryItem对象
  WatchHistoryItem _mapToWatchHistoryItem(Map<String, dynamic> map) {
    final item = WatchHistoryItem(
      filePath: map['file_path'],
      animeName: map['anime_name'],
      episodeTitle: map['episode_title'],
      episodeId: map['episode_id'],
      animeId: map['anime_id'],
      watchProgress: map['watch_progress'],
      lastPosition: map['last_position'],
      duration: map['duration'],
      lastWatchTime: DateTime.parse(map['last_watch_time']),
      thumbnailPath: map['thumbnail_path'],
      isFromScan: map['is_from_scan'] == 1,
    );
    
    // 添加调试日志
    //debugPrint('数据库读取历史记录: filePath=${item.filePath}, animeName=${item.animeName}, episodeId=${item.episodeId}, animeId=${item.animeId}');
    
    return item;
  }
} 