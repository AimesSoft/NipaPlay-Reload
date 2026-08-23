import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'watch_history_model.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'dart:io' as io;

class WatchHistoryBulkMergeResult {
  const WatchHistoryBulkMergeResult({
    required this.restoredCount,
    required this.skippedCount,
    this.restoredPositions = const {},
  });

  final int restoredCount;
  final int skippedCount;
  final Map<String, int> restoredPositions;
}

class EpisodeMatchRestoreItem {
  const EpisodeMatchRestoreItem({
    required this.filePath,
    required this.animeId,
    required this.episodeId,
    this.animeName,
    this.episodeTitle,
    this.videoHash,
  });

  final String filePath;
  final int animeId;
  final int episodeId;
  final String? animeName;
  final String? episodeTitle;
  final String? videoHash;
}

class WatchHistoryDatabase {
  static Database? _database;
  static final WatchHistoryDatabase instance = WatchHistoryDatabase._init();
  static const String _dbName = 'watch_history.db';
  static const int _dbVersion = 2;
  static bool _migrationCompleted = false;
  static bool _ffiInitialized = false;
  static final Map<String, WatchHistoryItem> _webStore = {};
  static const String _webStoreKey = 'watch_history_web_store';
  static const Duration _webPersistDelay = Duration(milliseconds: 500);
  static bool _webStoreLoaded = false;
  static Timer? _webPersistTimer;

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
    ensureInitialized();

    // 使用StorageService获取正确的存储目录
    final io.Directory storageDir =
        await StorageService.getAppStorageDirectory();
    final String dbPath = path.join(storageDir.path, _dbName);

    // 确保目录存在
    final dbDir = io.Directory(path.dirname(dbPath));
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

  static void ensureInitialized() {
    if (_ffiInitialized || kIsWeb) return;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }

  // 创建数据库表
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE watch_history(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_path TEXT UNIQUE NOT NULL,
      media_key TEXT,
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
    await db.execute('CREATE INDEX idx_media_key ON watch_history(media_key)');
    await db.execute('CREATE INDEX idx_anime_id ON watch_history(anime_id)');
    await db.execute(
        'CREATE INDEX idx_last_watch_time ON watch_history(last_watch_time)');
  }

  // 数据库升级处理
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _createDB(db, newVersion);
      return;
    }
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE watch_history ADD COLUMN media_key TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_media_key ON watch_history(media_key)',
      );
    }
    // 未来版本可以在这里添加更多迁移代码
  }

  // 关闭数据库连接
  Future<void> close() async {
    if (kIsWeb) return;
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // 从JSON迁移数据
  Future<void> migrateFromJson() async {
    if (kIsWeb) {
      _migrationCompleted = true;
      return;
    }
    // 避免重复迁移
    if (_migrationCompleted) return;

    try {
      final db = await database;
      // 检查是否已经有数据
      final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM watch_history'));

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
              'media_key': _mediaKeyFor(item),
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
          final jsonFile = io.File(jsonFilePath);
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

      final directory = io.Directory(path.dirname(jsonFilePath));
      if (!directory.existsSync()) return;

      final List<io.FileSystemEntity> entities =
          await directory.list().toList();
      for (var entity in entities) {
        if (entity is io.File &&
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
      // 使用StorageService获取正确的存储目录
      final io.Directory storageDir =
          await StorageService.getAppStorageDirectory();

      return path.join(storageDir.path, 'watch_history.json');
    } catch (e) {
      debugPrint('获取JSON文件路径失败: $e');
      return null;
    }
  }

  static Future<void> _ensureWebStoreLoaded() async {
    if (!kIsWeb || _webStoreLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webStoreKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw);
        bool hasMigrated = false;
        if (decoded is List) {
          for (final entry in decoded) {
            try {
              WatchHistoryItem item;
              if (entry is Map<String, dynamic>) {
                item = WatchHistoryItem.fromJson(entry);
              } else if (entry is Map) {
                item =
                    WatchHistoryItem.fromJson(Map<String, dynamic>.from(entry));
              } else {
                continue;
              }
              // 如果路径不是新格式，尝试迁移
              if (item.filePath.isNotEmpty &&
                  !MediaSourceUtils.isNewWebDavPath(item.filePath) &&
                  !MediaSourceUtils.isNewSmbPath(item.filePath)) {
                final migratedPath =
                    MediaSourceUtils.migratePath(item.filePath);
                if (migratedPath != item.filePath) {
                  item = item.copyWith(filePath: migratedPath);
                  hasMigrated = true;
                }
              }
              _webStore[item.filePath] = item;
            } catch (_) {}
          }
        } else if (decoded is Map) {
          decoded.forEach((key, value) {
            try {
              WatchHistoryItem item;
              if (value is Map<String, dynamic>) {
                item = WatchHistoryItem.fromJson(value);
              } else if (value is Map) {
                item =
                    WatchHistoryItem.fromJson(Map<String, dynamic>.from(value));
              } else {
                return;
              }
              // 如果路径不是新格式，尝试迁移
              if (item.filePath.isNotEmpty &&
                  !MediaSourceUtils.isNewWebDavPath(item.filePath) &&
                  !MediaSourceUtils.isNewSmbPath(item.filePath)) {
                final migratedPath =
                    MediaSourceUtils.migratePath(item.filePath);
                if (migratedPath != item.filePath) {
                  item = item.copyWith(filePath: migratedPath);
                  hasMigrated = true;
                }
              }
              _webStore[item.filePath] = item;
            } catch (_) {}
          });
        }
        if (hasMigrated) {
          _scheduleWebStorePersist();
        }
      }
    } catch (e) {
      debugPrint('加载Web观看记录缓存失败: $e');
    } finally {
      _webStoreLoaded = true;
    }
  }

  static void _scheduleWebStorePersist() {
    if (!kIsWeb) return;
    _webPersistTimer?.cancel();
    _webPersistTimer = Timer(_webPersistDelay, () {
      // ignore: discarded_futures
      _persistWebStore();
    });
  }

  static Future<void> _persistWebStore() async {
    if (!kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = _webStore.values.map((item) => item.toJson()).toList();
      await prefs.setString(_webStoreKey, json.encode(items));
    } catch (e) {
      debugPrint('保存Web观看记录缓存失败: $e');
    }
  }

  // 插入或更新一条观看记录
  Future<void> insertOrUpdateWatchHistory(WatchHistoryItem item) async {
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      _webStore[item.filePath] = item.copyWith(mediaKey: _mediaKeyFor(item));
      _scheduleWebStorePersist();
      return;
    }
    final db = await database;

    // 添加调试日志
    //debugPrint('数据库保存历史记录: filePath=${item.filePath}, animeName=${item.animeName}, episodeId=${item.episodeId}, animeId=${item.animeId}');

    try {
      await db.insert(
        'watch_history',
        {
          'file_path': item.filePath,
          'media_key': _mediaKeyFor(item),
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
            'media_key': _mediaKeyFor(item),
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

  /// Merges a bounded restore batch with one prefetch and one SQLite
  /// transaction. Newer backup records win; older records may still provide a
  /// missing thumbnail. This preserves the full-backup conflict semantics
  /// without one query and one transaction per row.
  Future<WatchHistoryBulkMergeResult> mergeWatchHistoryBatch(
    List<WatchHistoryItem> items,
  ) async {
    if (items.isEmpty) {
      return const WatchHistoryBulkMergeResult(
        restoredCount: 0,
        skippedCount: 0,
      );
    }
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      var restored = 0;
      var skipped = 0;
      final positions = <String, int>{};
      for (final item in items) {
        final existing = _webStore[item.filePath];
        if (existing == null ||
            item.lastWatchTime.isAfter(existing.lastWatchTime)) {
          _webStore[item.filePath] = item.copyWith(
            thumbnailPath: item.thumbnailPath ?? existing?.thumbnailPath,
          );
          positions[item.filePath] = item.lastPosition;
          restored++;
        } else {
          if (item.thumbnailPath != null && existing.thumbnailPath == null) {
            _webStore[item.filePath] =
                existing.copyWith(thumbnailPath: item.thumbnailPath);
          }
          skipped++;
        }
      }
      _scheduleWebStorePersist();
      return WatchHistoryBulkMergeResult(
        restoredCount: restored,
        skippedCount: skipped,
        restoredPositions: positions,
      );
    }

    final db = await database;
    return db.transaction((txn) async {
      final existing =
          await _prefetchByFilePaths(txn, items.map((e) => e.filePath));
      var restored = 0;
      var skipped = 0;
      final positions = <String, int>{};
      final writes = txn.batch();
      for (final item in items) {
        final local = existing[item.filePath] ??
            existing[_iosAlternativePath(item.filePath)];
        if (local == null || item.lastWatchTime.isAfter(local.lastWatchTime)) {
          final merged = item.copyWith(
            thumbnailPath: item.thumbnailPath ?? local?.thumbnailPath,
          );
          writes.insert(
            'watch_history',
            _databaseValues(merged),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          positions[item.filePath] = item.lastPosition;
          existing[item.filePath] = merged;
          restored++;
        } else {
          if (item.thumbnailPath != null && local.thumbnailPath == null) {
            writes.insert(
              'watch_history',
              _databaseValues(
                  local.copyWith(thumbnailPath: item.thumbnailPath)),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            existing[item.filePath] =
                local.copyWith(thumbnailPath: item.thumbnailPath);
          }
          skipped++;
        }
      }
      await writes.commit(noResult: true);
      return WatchHistoryBulkMergeResult(
        restoredCount: restored,
        skippedCount: skipped,
        restoredPositions: positions,
      );
    });
  }

  /// Applies episode matching metadata in a bounded transaction.
  Future<WatchHistoryBulkMergeResult> mergeEpisodeMatchBatch(
    List<EpisodeMatchRestoreItem> matches,
  ) async {
    if (matches.isEmpty) {
      return const WatchHistoryBulkMergeResult(
        restoredCount: 0,
        skippedCount: 0,
      );
    }
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      var restored = 0;
      var skipped = 0;
      for (final match in matches) {
        final existing = _webStore[match.filePath];
        if (existing != null &&
            existing.animeId == match.animeId &&
            existing.episodeId == match.episodeId) {
          skipped++;
          continue;
        }
        _webStore[match.filePath] = existing == null
            ? WatchHistoryItem(
                filePath: match.filePath,
                animeName: match.animeName ?? '未知',
                episodeTitle: match.episodeTitle,
                episodeId: match.episodeId,
                animeId: match.animeId,
                watchProgress: 0,
                lastPosition: 0,
                duration: 0,
                lastWatchTime: DateTime.now(),
                isFromScan: true,
                videoHash: match.videoHash,
              )
            : existing.copyWith(
                animeId: match.animeId,
                episodeId: match.episodeId,
                animeName: match.animeName ?? existing.animeName,
                episodeTitle: match.episodeTitle,
                videoHash: match.videoHash,
              );
        restored++;
      }
      _scheduleWebStorePersist();
      return WatchHistoryBulkMergeResult(
        restoredCount: restored,
        skippedCount: skipped,
      );
    }

    final db = await database;
    return db.transaction((txn) async {
      final existing =
          await _prefetchByFilePaths(txn, matches.map((e) => e.filePath));
      var restored = 0;
      var skipped = 0;
      final writes = txn.batch();
      for (final match in matches) {
        final local = existing[match.filePath] ??
            existing[_iosAlternativePath(match.filePath)];
        if (local != null &&
            local.animeId == match.animeId &&
            local.episodeId == match.episodeId) {
          skipped++;
          continue;
        }
        final merged = local == null
            ? WatchHistoryItem(
                filePath: match.filePath,
                animeName: match.animeName ?? '未知',
                episodeTitle: match.episodeTitle,
                episodeId: match.episodeId,
                animeId: match.animeId,
                watchProgress: 0,
                lastPosition: 0,
                duration: 0,
                lastWatchTime: DateTime.now(),
                isFromScan: true,
                videoHash: match.videoHash,
              )
            : local.copyWith(
                animeId: match.animeId,
                episodeId: match.episodeId,
                animeName: match.animeName ?? local.animeName,
                episodeTitle: match.episodeTitle,
                videoHash: match.videoHash,
              );
        writes.insert(
          'watch_history',
          _databaseValues(merged),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        existing[match.filePath] = merged;
        restored++;
      }
      await writes.commit(noResult: true);
      return WatchHistoryBulkMergeResult(
        restoredCount: restored,
        skippedCount: skipped,
      );
    });
  }

  Future<Map<String, WatchHistoryItem>> _prefetchByFilePaths(
    DatabaseExecutor executor,
    Iterable<String> sourcePaths,
  ) async {
    final paths = <String>{};
    for (final filePath in sourcePaths) {
      paths.add(filePath);
      final alternative = _iosAlternativePath(filePath);
      if (alternative != null) paths.add(alternative);
    }
    final result = <String, WatchHistoryItem>{};
    final pathList = paths.toList();
    const queryChunkSize = 400;
    for (var offset = 0; offset < pathList.length; offset += queryChunkSize) {
      final end = (offset + queryChunkSize).clamp(0, pathList.length);
      final chunk = pathList.sublist(offset, end);
      final rows = await executor.query(
        'watch_history',
        where: 'file_path IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final item = _mapToWatchHistoryItem(row, migratePath: false);
        result[row['file_path'] as String] = item;
      }
    }
    return result;
  }

  String? _iosAlternativePath(String filePath) {
    if (!Platform.isIOS) return null;
    return filePath.startsWith('/private')
        ? filePath.replaceFirst('/private', '')
        : '/private$filePath';
  }

  Map<String, Object?> _databaseValues(WatchHistoryItem item) => {
        'file_path': item.filePath,
        'media_key': _mediaKeyFor(item),
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
      };

  // 获取所有观看历史，按最后观看时间排序
  Future<List<WatchHistoryItem>> getAllWatchHistory() async {
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      final items = _webStore.values.toList();
      items.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      return items;
    }
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
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      final exact = _webStore[filePath];
      if (exact != null) return exact;
      final mediaKey = MediaIdentityResolver.forPath(filePath);
      for (final item in _webStore.values) {
        if ((item.mediaKey ?? MediaIdentityResolver.forPath(item.filePath)) ==
            mediaKey) {
          return item;
        }
      }
      return null;
    }
    final db = await database;

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'watch_history',
        where: 'file_path = ?',
        whereArgs: [filePath],
        limit: 1,
      );

      if (maps.isEmpty) {
        final mediaKey = MediaIdentityResolver.forPath(filePath);
        final mediaKeyMaps = await db.query(
          'watch_history',
          where: 'media_key = ?',
          whereArgs: [mediaKey],
          limit: 1,
        );
        if (mediaKeyMaps.isNotEmpty) {
          return _mapToWatchHistoryItem(mediaKeyMaps.first);
        }

        final legacyAlias = _legacyConnectionNameAlias(filePath);
        if (legacyAlias != null && legacyAlias != filePath) {
          final aliasMaps = await db.query(
            'watch_history',
            where: 'file_path = ?',
            whereArgs: [legacyAlias],
            limit: 1,
          );
          if (aliasMaps.isNotEmpty) {
            return _mapToWatchHistoryItem(aliasMaps.first);
          }
        }

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

  // 根据共享媒体的 episode shareId 获取历史记录列表
  Future<List<WatchHistoryItem>> getHistoriesBySharedEpisodeId(
      String shareEpisodeId) async {
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      final items = _webStore.values
          .where((item) => item.filePath.contains(shareEpisodeId))
          .toList();
      items.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      return items;
    }
    final db = await database;

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'watch_history',
        where: 'file_path LIKE ?',
        whereArgs: ['%$shareEpisodeId%'],
        orderBy: 'last_watch_time DESC',
      );

      return maps.map((map) => _mapToWatchHistoryItem(map)).toList();
    } catch (e) {
      debugPrint('通过共享媒体EpisodeId获取历史记录失败: $e');
      return [];
    }
  }

  // 根据番剧ID和集数ID获取历史记录
  Future<WatchHistoryItem?> getHistoryByEpisode(
      int animeId, int episodeId) async {
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      for (final item in _webStore.values) {
        if (item.animeId == animeId && item.episodeId == episodeId) {
          return item;
        }
      }
      return null;
    }
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
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      final items = _webStore.values
          .where((item) => item.animeId == animeId && item.episodeId != null)
          .toList();
      items.sort((a, b) => (a.episodeId ?? 0).compareTo(b.episodeId ?? 0));
      return items;
    }
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
  Future<WatchHistoryItem?> getPreviousEpisode(
      int animeId, int currentEpisodeId) async {
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      final items = _webStore.values
          .where((item) =>
              item.animeId == animeId &&
              item.episodeId != null &&
              item.episodeId! < currentEpisodeId)
          .toList();
      items.sort((a, b) => (b.episodeId ?? 0).compareTo(a.episodeId ?? 0));
      return items.isEmpty ? null : items.first;
    }
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
  Future<WatchHistoryItem?> getNextEpisode(
      int animeId, int currentEpisodeId) async {
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      final items = _webStore.values
          .where((item) =>
              item.animeId == animeId &&
              item.episodeId != null &&
              item.episodeId! > currentEpisodeId)
          .toList();
      items.sort((a, b) => (a.episodeId ?? 0).compareTo(b.episodeId ?? 0));
      return items.isEmpty ? null : items.first;
    }
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
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      _webStore.remove(filePath);
      _scheduleWebStorePersist();
      return;
    }
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
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      final keysToRemove =
          _webStore.keys.where((key) => key.startsWith(pathPrefix)).toList();
      for (final key in keysToRemove) {
        _webStore.remove(key);
      }
      _scheduleWebStorePersist();
      return keysToRemove.length;
    }
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

  // 根据动画ID删除历史记录
  Future<int> deleteHistoryByAnimeId(int animeId) async {
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      final keysToRemove = _webStore.entries
          .where((entry) => entry.value.animeId == animeId)
          .map((entry) => entry.key)
          .toList();
      for (final key in keysToRemove) {
        _webStore.remove(key);
      }
      _scheduleWebStorePersist();
      return keysToRemove.length;
    }
    final db = await database;

    try {
      return await db.delete(
        'watch_history',
        where: 'anime_id = ?',
        whereArgs: [animeId],
      );
    } catch (e) {
      debugPrint('删除指定动画观看历史失败: $e');
      return 0;
    }
  }

  // 清空所有历史记录
  Future<void> clearAllHistory() async {
    if (kIsWeb) {
      await _ensureWebStoreLoaded();
      _webStore.clear();
      _scheduleWebStorePersist();
      return;
    }
    final db = await database;

    try {
      await db.delete('watch_history');
    } catch (e) {
      debugPrint('清空观看历史失败: $e');
      rethrow;
    }
  }

  // 调试：打印数据库所有内容
  Future<void> debugPrintAllData() async {}

  // 获取数据库文件路径（调试用）

  // 将数据库行映射为WatchHistoryItem对象
  WatchHistoryItem _mapToWatchHistoryItem(
    Map<String, dynamic> map, {
    bool migratePath = true,
  }) {
    final originalPath = map['file_path'] as String? ?? '';
    final item = WatchHistoryItem(
      filePath: originalPath,
      mediaKey: map['media_key'] as String? ??
          (originalPath.isEmpty
              ? null
              : MediaIdentityResolver.forPath(originalPath)),
      animeName: map['anime_name'],
      episodeTitle: map['episode_title'],
      episodeId: (map['episode_id'] as num?)?.toInt(),
      animeId: (map['anime_id'] as num?)?.toInt(),
      watchProgress: (map['watch_progress'] as num?)?.toDouble() ?? 0.0,
      lastPosition: (map['last_position'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      lastWatchTime: DateTime.parse(map['last_watch_time']),
      thumbnailPath: map['thumbnail_path'],
      isFromScan: map['is_from_scan'] == 1,
    );

    // 如果路径不是新格式，尝试迁移
    if (migratePath && originalPath.isNotEmpty) {
      final migratedPath = MediaSourceUtils.migratePath(originalPath);
      if (migratedPath != originalPath) {
        final migratedItem = item.copyWith(
          filePath: migratedPath,
          mediaKey: MediaIdentityResolver.forPath(migratedPath),
        );
        // 异步写回数据库，不阻塞当前读取
        _migratePathInBackground(originalPath, migratedItem);
        return migratedItem;
      }
    }

    return item;
  }

  static String _mediaKeyFor(WatchHistoryItem item) =>
      item.mediaKey ?? MediaIdentityResolver.forPath(item.filePath);

  String? _legacyConnectionNameAlias(String filePath) {
    final webDav = WebDAVService.instance.resolveMediaPath(filePath);
    if (webDav != null) {
      return MediaSourceUtils.buildWebDavPath(
        webDav.connection.name,
        webDav.relativePath,
      );
    }
    final smb = MediaSourceUtils.parseSmbMediaPath(filePath);
    if (smb != null) {
      final connection =
          SMBService.instance.getConnectionByIdOrName(smb.connectionName);
      if (connection != null) {
        return MediaSourceUtils.buildSmbPath(
          connection.name,
          smb.relativePath,
        );
      }
    }
    return null;
  }

  void _migratePathInBackground(String oldPath, WatchHistoryItem migratedItem) {
    Future.microtask(() async {
      try {
        await insertOrUpdateWatchHistory(migratedItem);
        await deleteHistory(oldPath);
        debugPrint(
            '[路径迁移] ${migratedItem.animeName}: $oldPath -> ${migratedItem.filePath}');
      } catch (e) {
        debugPrint('[路径迁移] 写回失败: $e');
      }
    });
  }
}
