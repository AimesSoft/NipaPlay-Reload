import 'dart:convert';
import 'dart:io';

import '../utils/storage_service.dart';

class DanmakuCacheManager {
  static const String _cacheKeyPrefix = 'danmaku_cache_';
  static const int _oldAnimeThreshold = 18343;
  static const Duration _oldAnimeCacheDuration = Duration(days: 7);
  static const Duration _newAnimeCacheDuration = Duration(hours: 2);
  static final Map<String, Map<String, dynamic>> _memoryCache = {};

  static Future<String> _getCacheFilePath(String episodeId) async {
    final directory = await StorageService.getAppStorageDirectory();
    return '${directory.path}/$_cacheKeyPrefix$episodeId.json';
  }

  static Future<bool> isCacheValid(String episodeId) async {
    try {
      //////debugPrint('检查缓存有效性: $episodeId');
      // 首先检查内存缓存
      if (_memoryCache.containsKey(episodeId)) {
        //////debugPrint('找到内存缓存');
        final cacheData = _memoryCache[episodeId]!;
        final timestamp = cacheData['timestamp'] as int;
        final animeId = cacheData['animeId'] as int;
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final now = DateTime.now();

        final cacheDuration = animeId < _oldAnimeThreshold 
            ? _oldAnimeCacheDuration 
            : _newAnimeCacheDuration;

        final isValid = now.difference(cacheTime) < cacheDuration;
        //////debugPrint('内存缓存${isValid ? '有效' : '已过期'}');
        return isValid;
      }

      final file = File(await _getCacheFilePath(episodeId));
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
      if (isValid) {
        //////debugPrint('文件缓存有效，保存到内存缓存');
        _memoryCache[episodeId] = jsonData;
      } else {
        //////debugPrint('文件缓存已过期');
      }
      return isValid;
    } catch (e) {
      //////debugPrint('检查缓存有效性时出错: $e');
      return false;
    }
  }

  static Future<void> saveDanmakuToCache(
    String episodeId, 
    int animeId, 
    List<dynamic> comments
  ) async {
    try {
      final jsonData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'animeId': animeId,
        'comments': comments,
      };

      // 保存到内存缓存
      _memoryCache[episodeId] = jsonData;

      // 异步保存到文件
      final file = File(await _getCacheFilePath(episodeId));
      await file.writeAsString(json.encode(jsonData));
    } catch (e) {
      //////debugPrint('保存弹幕缓存失败: $e');
    }
  }

  static Future<List<dynamic>?> getDanmakuFromCache(String episodeId) async {
    try {
      //////debugPrint('尝试从缓存获取弹幕: $episodeId');
      // 首先检查内存缓存
      if (_memoryCache.containsKey(episodeId)) {
        //////debugPrint('从内存缓存获取弹幕');
        final cacheData = _memoryCache[episodeId]!;
        final timestamp = cacheData['timestamp'] as int;
        final animeId = cacheData['animeId'] as int;
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final now = DateTime.now();

        final cacheDuration = animeId < _oldAnimeThreshold 
            ? _oldAnimeCacheDuration 
            : _newAnimeCacheDuration;

        if (now.difference(cacheTime) < cacheDuration) {
          final comments = cacheData['comments'] as List<dynamic>;
          //////debugPrint('内存缓存有效，返回 ${comments.length} 条弹幕');
          return comments;
        } else {
          //////debugPrint('内存缓存已过期，移除');
          _memoryCache.remove(episodeId);
        }
      }

      if (!await isCacheValid(episodeId)) {
        //////debugPrint('缓存无效');
        return null;
      }

      //////debugPrint('从文件缓存获取弹幕');
      final file = File(await _getCacheFilePath(episodeId));
      final jsonData = json.decode(await file.readAsString());
      final comments = jsonData['comments'] as List<dynamic>;
      //////debugPrint('返回 ${comments.length} 条弹幕');
      return comments;
    } catch (e) {
      //////debugPrint('从缓存获取弹幕时出错: $e');
      return null;
    }
  }

  static Future<void> clearExpiredCache() async {
    try {
      // 清理内存缓存
      final now = DateTime.now();
      _memoryCache.removeWhere((episodeId, cacheData) {
        final timestamp = cacheData['timestamp'] as int;
        final animeId = cacheData['animeId'] as int;
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

        final cacheDuration = animeId < _oldAnimeThreshold 
            ? _oldAnimeCacheDuration 
            : _newAnimeCacheDuration;

        return now.difference(cacheTime) > cacheDuration;
      });

      // 清理文件缓存
      final directory = await StorageService.getAppStorageDirectory();
      final files = await directory.list().where((entity) => 
        entity.path.contains(_cacheKeyPrefix)).toList();

      for (var file in files) {
        if (file is File) {
          try {
            final jsonData = json.decode(await file.readAsString());
            final timestamp = jsonData['timestamp'] as int;
            final animeId = jsonData['animeId'] as int;
            final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
            final now = DateTime.now();

            final cacheDuration = animeId < _oldAnimeThreshold 
                ? _oldAnimeCacheDuration 
                : _newAnimeCacheDuration;

            if (now.difference(cacheTime) > cacheDuration) {
              await file.delete();
            }
          } catch (e) {
            // 如果文件损坏，直接删除
            await file.delete();
          }
        }
      }
    } catch (e) {
      //////debugPrint('清理过期缓存失败: $e');
    }
  }
} 