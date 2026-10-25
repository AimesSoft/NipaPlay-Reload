import 'dart:convert';
import 'dart:io' as io;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:nipaplay/utils/storage_service.dart';

// Legacy payload parsing runs off the UI isolate; new entries have small sidecars.
Future<Map<String, dynamic>> _readLegacyDanmakuMetadata(String filePath) async {
  final data = json.decode(await io.File(filePath).readAsString())
      as Map<String, dynamic>;
  return {
    'timestamp': data['timestamp'] as int,
    'animeId': data['animeId'] as int
  };
}

class DanmakuCacheManager {
  static const String _cacheKeyPrefix = 'danmaku_cache_';
  static const int _oldAnimeThreshold = 18343;
  static const Duration _oldAnimeCacheDuration = Duration(days: 7);
  static const Duration _newAnimeCacheDuration = Duration(hours: 2);
  // 刻意不做内存层：一份解析后的弹幕 JSON（2k-10k 条）约 1.5-6MB，驻留
  // 常驻只是让重开快几十毫秒；磁盘缓存仍是唯一层，读回成本可忽略。
  // （旧版内存 LRU 因 _rememberInMemoryCache 自递归从未生效，已随本注释移除。）
  static io.Directory? _cachedDanmakuDir;
  static bool _migrationAttempted = false;

  static Future<void> _diskOperation = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _diskOperation.then((_) => operation());
    _diskOperation =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<bool> isCacheValid(String episodeId) =>
      _serialized(() => _isCacheValid(episodeId));
  static Future<List<dynamic>?> getDanmakuFromCache(String episodeId) =>
      _serialized(() => _getDanmakuFromCache(episodeId));
  static Future<void> saveDanmakuToCache(
          String episodeId, int animeId, List<dynamic> comments) =>
      _serialized(() => _saveDanmakuToCache(episodeId, animeId, comments));
  static Future<void>? _cleanup;
  static Future<void> clearExpiredCache() async {
    final cleanup = _cleanup ??= _clearExpiredCache();
    try {
      await cleanup;
    } finally {
      if (identical(_cleanup, cleanup)) _cleanup = null;
    }
  }

  static Future<void> clearAllCache() => _serialized(_clearAllCache);

  static Future<void> _writeMetadata(
      io.File file, Map<String, dynamic> data) async {
    final stat = await file.stat();
    await io.File('${file.path}.meta').writeAsString(json.encode({
      'timestamp': data['timestamp'],
      'animeId': data['animeId'],
      'size': stat.size,
      'modified': stat.modified.microsecondsSinceEpoch,
    }));
  }

  static Future<Map<String, dynamic>> _metadata(io.File file) async {
    final meta = io.File('${file.path}.meta');
    final stat = await file.stat();
    try {
      final data =
          json.decode(await meta.readAsString()) as Map<String, dynamic>;
      if (data['size'] == stat.size &&
          data['modified'] == stat.modified.microsecondsSinceEpoch &&
          data['timestamp'] is int &&
          data['animeId'] is int) return data;
    } catch (_) {
      /* Old or interrupted writes are migrated from their payload. */
    }
    final data = await compute(_readLegacyDanmakuMetadata, file.path);
    try {
      await _writeMetadata(file, data);
    } catch (_) {}
    return data;
  }

  static Future<io.Directory>? _directoryInitialization;
  static Future<io.Directory> _getDanmakuCacheDirectory() async {
    if (_cachedDanmakuDir != null) return _cachedDanmakuDir!;
    final pending = _directoryInitialization ??= _initializeDirectory();
    try {
      return await pending;
    } finally {
      if (identical(_directoryInitialization, pending))
        _directoryInitialization = null;
    }
  }

  static Future<io.Directory> _initializeDirectory() async {
    final cacheRoot = await StorageService.getCacheDirectory();
    final danmakuDir = io.Directory('${cacheRoot.path}/danmaku');
    if (!await danmakuDir.exists()) {
      await danmakuDir.create(recursive: true);
    }
    await _migrateLegacyCacheIfNeeded(danmakuDir);
    _cachedDanmakuDir = danmakuDir;
    return danmakuDir;
  }

  static Future<String> _getCacheFilePath(String episodeId) async {
    final directory = await _getDanmakuCacheDirectory();
    return '${directory.path}/$_cacheKeyPrefix$episodeId.json';
  }

  static Future<void> _migrateLegacyCacheIfNeeded(io.Directory newDir) async {
    if (_migrationAttempted) return;
    _migrationAttempted = true;
    try {
      final legacyDir = await StorageService.getAppStorageDirectory();
      if (legacyDir.path == newDir.path) {
        return;
      }

      final legacyEntities = await legacyDir.list().toList();
      final legacyFiles = legacyEntities.whereType<io.File>().where((file) {
        final fileName = path.basename(file.path);
        return fileName.startsWith(_cacheKeyPrefix) &&
            fileName.endsWith('.json');
      }).toList();

      if (legacyFiles.isEmpty) {
        return;
      }

      for (final file in legacyFiles) {
        final fileName = path.basename(file.path);
        final targetFile = io.File(path.join(newDir.path, fileName));
        if (await targetFile.exists()) {
          continue;
        }
        try {
          await file.rename(targetFile.path);
        } catch (_) {
          try {
            await file.copy(targetFile.path);
            await file.delete();
          } catch (e) {
            //////debugPrint('迁移弹幕缓存文件失败: $e');
          }
        }
      }
    } catch (e) {
      //////debugPrint('迁移旧弹幕缓存失败: $e');
    }
  }

  static Future<bool> _isCacheValid(String episodeId) async {
    try {
      //////debugPrint('检查缓存有效性: $episodeId');
      final file = io.File(await _getCacheFilePath(episodeId));
      if (!await file.exists()) {
        //////debugPrint('缓存文件不存在');
        return false;
      }

      //////debugPrint('找到文件缓存');
      final jsonData = json.decode(await file.readAsString());
      final timestamp = jsonData['timestamp'] as int;
      final animeId = jsonData['animeId'] as int;
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();

      final cacheDuration = animeId < _oldAnimeThreshold
          ? _oldAnimeCacheDuration
          : _newAnimeCacheDuration;

      final isValid = now.difference(cacheTime) < cacheDuration;
      return isValid;
    } catch (e) {
      //////debugPrint('检查缓存有效性时出错: $e');
      return false;
    }
  }

  static Future<void> _saveDanmakuToCache(
      String episodeId, int animeId, List<dynamic> comments) async {
    if (kIsWeb) return;
    try {
      // 去除重复弹幕
      final uniqueComments = _removeDuplicateDanmaku(comments);

      final jsonData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'animeId': animeId,
        'comments': uniqueComments,
        'count': uniqueComments.length
      };

      // 异步保存到文件
      final file = io.File(await _getCacheFilePath(episodeId));
      await file.writeAsString(json.encode(jsonData));
      await _writeMetadata(file, jsonData);
    } catch (e) {
      //////debugPrint('保存弹幕缓存失败: $e');
    }
  }

  static Future<List<dynamic>?> _getDanmakuFromCache(String episodeId) async {
    if (kIsWeb) return null;
    try {
      //////debugPrint('尝试从缓存获取弹幕: $episodeId');
      if (!await isCacheValid(episodeId)) {
        //////debugPrint('缓存无效');
        return null;
      }

      //////debugPrint('从文件缓存获取弹幕');
      final file = io.File(await _getCacheFilePath(episodeId));
      final jsonData = json.decode(await file.readAsString());
      final comments = jsonData['comments'] as List<dynamic>;
      // 去除重复弹幕
      final uniqueComments = _removeDuplicateDanmaku(comments);

      //////debugPrint('返回 ${uniqueComments.length} 条弹幕');
      return uniqueComments;
    } catch (e) {
      //////debugPrint('从缓存获取弹幕时出错: $e');
      return null;
    }
  }

  /// 去除重复的弹幕
  static List<dynamic> _removeDuplicateDanmaku(List<dynamic> comments) {
    final seen = <String>{};
    final uniqueComments = <dynamic>[];

    for (final comment in comments) {
      // 将弹幕转换为唯一字符串表示，用于去重
      final key =
          '${comment['time']}_${comment['content']}_${comment['type']}_${comment['color']}';
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueComments.add(comment);
      }
    }

    return uniqueComments;
  }

  static Future<void> _clearExpiredCache() async {
    if (kIsWeb) return;
    try {
      // 清理文件缓存
      final directory = await _getDanmakuCacheDirectory();
      final files = await directory
          .list()
          .where((entity) =>
              path.basename(entity.path).startsWith(_cacheKeyPrefix) &&
              entity.path.endsWith('.json'))
          .toList();

      for (var file in files) {
        if (file is io.File) {
          await _serialized(() async {
            if (!await file.exists()) return;
            try {
              final jsonData = await _metadata(file);
              final timestamp = jsonData['timestamp'] as int;
              final animeId = jsonData['animeId'] as int;
              final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
              final now = DateTime.now();

              final cacheDuration = animeId < _oldAnimeThreshold
                  ? _oldAnimeCacheDuration
                  : _newAnimeCacheDuration;

              if (now.difference(cacheTime) > cacheDuration) {
                await file.delete();
                final meta = io.File('${file.path}.meta');
                if (await meta.exists()) await meta.delete();
              }
            } catch (e) {
              // 如果文件损坏，直接删除
              if (await file.exists()) await file.delete();
              final meta = io.File('${file.path}.meta');
              if (await meta.exists()) await meta.delete();
            }
          });
          // Yield between files so playback reads/writes can enter the queue.
          await Future<void>.delayed(Duration.zero);
        }
      }
    } catch (e) {
      //////debugPrint('清理过期缓存失败: $e');
    }
  }

  static Future<void> _clearAllCache() async {
    if (kIsWeb) return;
    try {
      final directory = await _getDanmakuCacheDirectory();
      if (!await directory.exists()) {
        return;
      }

      await for (final entity in directory.list()) {
        if (entity is io.File) {
          final fileName = path.basename(entity.path);
          if (fileName.startsWith(_cacheKeyPrefix) &&
              (fileName.endsWith('.json') || fileName.endsWith('.json.meta'))) {
            try {
              await entity.delete();
            } catch (_) {
              // ignore deletion errors to avoid breaking the cleanup flow
            }
          }
        }
      }
    } catch (e) {
      //////debugPrint('清理弹幕缓存失败: $e');
    }
  }
}
