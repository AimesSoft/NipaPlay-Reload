import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bangumi_model.dart';
import './dandanplay_service.dart';

class BangumiService {
  static final BangumiService instance = BangumiService._();
  static const String _dandanplayBaseUrl = 'https://api.dandanplay.net/api/v2';
  static const String _shinBangumiUrl = '$_dandanplayBaseUrl/bangumi/shin';
  static const String _bangumiDetailUrl = '$_dandanplayBaseUrl/bangumi/';

  static const String _cacheKey = 'dandanplay_shin_cache';
  static const String _detailsCacheKeyPrefix = 'bangumi_detail_';
  static const Duration _defaultCacheDuration = Duration(hours: 3);
  static const int _oldAnimeThreshold = 18343; // 和弹幕缓存使用相同的判断标准
  static const Duration _oldAnimeCacheDuration = Duration(days: 7);
  static const Duration _newAnimeCacheDuration = Duration(hours: 6); // 新番缓存时间可以比弹幕长一些
  static const int _maxConcurrentRequests = 3;

  final Map<String, BangumiAnime> _listCache = {};
  final Map<int, BangumiAnime> _detailsCache = {};
  final Map<int, DateTime> _detailsCacheTime = {};
  bool _isInitialized = false;
  List<BangumiAnime>? _preloadedAnimes;
  late http.Client _client;
  final _requestQueue = <_RequestItem>[];
  bool _isProcessingQueue = false;

  BangumiService._() {
    _client = http.Client();
  }

  // 根据番剧ID获取缓存时间
  Duration _getCacheDurationForAnime(int animeId) {
    return animeId < _oldAnimeThreshold
        ? _oldAnimeCacheDuration
        : _newAnimeCacheDuration;
  }

  // 检查缓存是否有效
  bool _isCacheValid(int animeId, DateTime cacheTime) {
    final cacheDuration = _getCacheDurationForAnime(animeId);
    return DateTime.now().difference(cacheTime) < cacheDuration;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    // 初始化时预加载已缓存的详情数据到内存
    await _preloadDetailsCacheFromDisk();
  }

  // 预加载已缓存的详情数据到内存
  Future<void> _preloadDetailsCacheFromDisk() async {
    try {
      debugPrint('[番剧服务] 正在预加载缓存的番剧详情到内存');
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      final detailsKeys = keys.where((key) => key.startsWith(_detailsCacheKeyPrefix)).toList();
      int loadedCount = 0;
      
      for (var key in detailsKeys) {
        try {
          final String? cachedString = prefs.getString(key);
          if (cachedString != null) {
            final data = json.decode(cachedString);
            final timestamp = data['timestamp'] as int;
            final now = DateTime.now().millisecondsSinceEpoch;
            final animeId = int.parse(key.substring(_detailsCacheKeyPrefix.length));
            
            // 使用动态缓存时间检查是否过期
            final cacheDuration = _getCacheDurationForAnime(animeId);
            
            // 检查是否过期
            if (now - timestamp <= cacheDuration.inMilliseconds) {
              final Map<String, dynamic> animeData = data['animeDetail'];
              
              final animeDetail = BangumiAnime.fromDandanplayDetail(animeData);
              _detailsCache[animeId] = animeDetail;
              _detailsCacheTime[animeId] = DateTime.fromMillisecondsSinceEpoch(timestamp);
              loadedCount++;
            } else {
              // 过期的缓存自动删除
              await prefs.remove(key);
            }
          }
        } catch (e) {
          debugPrint('[番剧服务] 预加载单个番剧详情缓存失败: $e');
          continue;
        }
      }
      
      debugPrint('[番剧服务] 预加载了 $loadedCount 条番剧详情到内存缓存');
    } catch (e) {
      debugPrint('[番剧服务] 预加载番剧详情缓存失败: $e');
    }
  }

  Future<void> loadData() async {
    try {
      //debugPrint('[新番-弹弹play] 开始加载新番数据');
      final animes = await getCalendar();
      _preloadedAnimes = animes;
      //debugPrint('[新番-弹弹play] 加载新番数据完成，数量: ${_preloadedAnimes?.length ?? 0}');
    } catch (e) {
      //debugPrint('[新番-弹弹play] 加载数据时出错: ${e.toString()}');
      rethrow;
    }
  }

  Future<http.Response> _makeRequest(String url, {int maxRetries = 3, int priority = 0}) async {
    final completer = Completer<http.Response>();
    _requestQueue.add(_RequestItem(url, maxRetries, priority, completer));
    _processQueue();
    return completer.future;
  }

  void _processQueue() async {
    if (_isProcessingQueue || _requestQueue.isEmpty) return;
    _isProcessingQueue = true;

    try {
      _requestQueue.sort((a, b) => b.priority.compareTo(a.priority));
      
      while (_requestQueue.isNotEmpty) {
        final activeRequests = <Future>[];
        final itemsToRemove = <_RequestItem>[];
        
        for (var i = 0; i < _maxConcurrentRequests && _requestQueue.isNotEmpty; i++) {
          final item = _requestQueue.removeAt(0);
          itemsToRemove.add(item);
          activeRequests.add(_executeRequest(item));
        }
        
        await Future.wait(activeRequests);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _executeRequest(_RequestItem item) async {
    int retryCount = 0;
    while (retryCount < item.maxRetries) {
      try {
        const String appId = DandanplayService.appId;
        final String appSecret = await DandanplayService.getAppSecret();
        final int timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
        
        final Uri parsedUri = Uri.parse(item.url);
        final String apiPath = parsedUri.path;
        
        final String signature = DandanplayService.generateSignature(appId, timestamp, apiPath, appSecret);

        final response = await _client.get(
          Uri.parse(item.url),
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'NipaPlay/1.0',
            'X-AppId': appId,
            'X-Timestamp': timestamp.toString(),
            'X-Signature': signature,
          },
        ).timeout(
          Duration(seconds: 15 + retryCount * 5),
          onTimeout: () {
            throw TimeoutException('请求超时');
          }
        );
        
        if (response.statusCode == 200) {
          item.completer.complete(response);
          return;
        } else {
          if (response.bodyBytes.length < 1000) {
          }
          throw Exception('HTTP请求失败: ${response.statusCode}');
        }
      } catch (e) {
        retryCount++;
        if (retryCount == item.maxRetries) {
          item.completer.completeError(Exception('请求失败，已达到最大重试次数: $e'));
          return;
        }
        final waitSeconds = retryCount * 2;
        await Future.delayed(Duration(seconds: waitSeconds));
      }
    }
  }

  Future<List<BangumiAnime>> getCalendar({bool forceRefresh = false, bool filterAdultContent = true}) async {
    //debugPrint('[新番-弹弹play] getCalendar - Strategy: Network first, then cache. forceRefresh: $forceRefresh, filterAdultContent: $filterAdultContent');

    // If forceRefresh is true, we definitely skip trying memory cache first before network.
    // However, the new strategy is always network first unless network fails.

    final apiUrl = '$_shinBangumiUrl?filterAdultContent=$filterAdultContent';
    //debugPrint('[新番-弹弹play] Attempting to fetch from API: $apiUrl');

    try {
      final response = await _makeRequest(apiUrl, priority: 1); // Higher priority for user-facing calendar
      //debugPrint('[新番-弹弹play] API response: Status=${response.statusCode}, Length=${response.bodyBytes.length}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedResponse = json.decode(utf8.decode(response.bodyBytes));
        if (decodedResponse['success'] == true && decodedResponse['bangumiList'] != null) {
          final List<dynamic> data = decodedResponse['bangumiList'];
          //debugPrint('[新番-弹弹play] Parsed ${data.length} animes from API.');

          if (data.isNotEmpty) {
            try {
              final firstAnimeRawJson = json.encode(data[0]);
              //debugPrint('[新番-弹弹play] Raw JSON of the first anime from API: $firstAnimeRawJson');
            } catch (e) {
              //debugPrint('[新番-弹弹play] Error encoding first anime raw JSON from API: $e');
            }
          }

          final List<BangumiAnime> animes = [];
          _listCache.clear(); // Clear old memory list cache before populating with new data
          for (var animeData in data) {
            try {
              final anime = BangumiAnime.fromDandanplayIntro(animeData as Map<String, dynamic>);
              _listCache[anime.id.toString()] = anime; // Update memory cache
              animes.add(anime);
            } catch (e) {
              //debugPrint('[新番-弹弹play] Error parsing single anime (Intro) from API: ${e.toString()}, Data: $animeData');
              continue;
            }
          }
          
          // Update preloaded animes as well, as this is the latest data now.
          _preloadedAnimes = List.from(animes); 
          //debugPrint('[新番-弹弹play] Successfully fetched and cached ${animes.length} animes from API.');
          
          // Asynchronously save to disk cache. No need to await this for returning data to UI.
          _saveToCache(animes).then((_) {
            //debugPrint('[新番-弹弹play] Disk cache updated in background after API fetch.');
          }).catchError((e) {
            //debugPrint('[新番-弹弹play] Error updating disk cache in background: $e');
          });

          return animes;
        } else {
          //debugPrint('[新番-弹弹play] API request successful but response format invalid or success is false: ${decodedResponse['errorMessage']}');
          throw Exception('Failed to load shin bangumi from API: ${decodedResponse['errorMessage'] ?? 'Unknown API error'}');
        }
      } else {
        //debugPrint('[新番-弹弹play] API request failed with HTTP ${response.statusCode}. Will try cache.');
        // Throw an exception to be caught by the outer try-catch, which will then try cache.
        throw Exception('API request failed: ${response.statusCode}'); 
      }
    } catch (e) {
      //debugPrint('[新番-弹弹play] Error fetching from API: ${e.toString()}. Attempting to load from cache...');
      
      // API fetch failed, try to load from SharedPreferences cache
      // We don't need to check _preloadedAnimes or _listCache here because if API failed,
      // we want to provide at least some data if available in disk cache.
      final cachedData = await _loadFromCache();
      if (cachedData != null && cachedData.isNotEmpty) {
        //debugPrint('[新番-弹弹play] Successfully loaded ${cachedData.length} animes from disk cache as fallback.');
        // Populate memory caches if we are returning disk-cached data
        _listCache.clear();
        for(var anime in cachedData) {
            _listCache[anime.id.toString()] = anime;
        }
        _preloadedAnimes = List.from(cachedData);
        return cachedData;
      } else {
        //debugPrint('[新番-弹弹play] Failed to load from API and no valid disk cache found. Rethrowing error.');
        rethrow; // Rethrow the original error if cache is also unavailable
      }
    }
  }

  Future<void> _saveToCache(List<BangumiAnime> animes) async {
    try {
      //debugPrint('[新番-弹弹play] 保存数据到本地缓存...');
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'animes': animes.map((a) => a.toJson()).toList(), 
      };
      await prefs.setString(_cacheKey, json.encode(data));
      //debugPrint('[新番-弹弹play] 数据已保存到本地存储 (key: $_cacheKey)');
    } catch (e) {
      //debugPrint('[新番-弹弹play] 保存到本地存储时出错: ${e.toString()}');
    }
  }

  Future<List<BangumiAnime>?> _loadFromCache() async {
    try {
      //debugPrint('[新番-弹弹play] 尝试从本地缓存加载数据 (key: $_cacheKey)...');
      final prefs = await SharedPreferences.getInstance();
      final String? cachedString = prefs.getString(_cacheKey);
      if (cachedString != null) {
        final data = json.decode(cachedString);
        final timestamp = data['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        //debugPrint('[新番-弹弹play] 本地缓存时间戳: $timestamp, 当前: $now');
        if (now - timestamp <= _defaultCacheDuration.inMilliseconds) {
          final List<dynamic> animesData = data['animes'];
          final animes = animesData
              .map((d) => BangumiAnime.fromDandanplayIntro(d as Map<String, dynamic>))
              .toList();
          for (var anime in animes) {
            _listCache[anime.id.toString()] = anime;
          }
          //debugPrint('[新番-弹弹play] 从本地存储加载了 ${animes.length} 个番剧');
          return animes;
        } else {
          //debugPrint('[新番-弹弹play] 缓存已过期');
          await prefs.remove(_cacheKey);
          return null;
        }
      }
      //debugPrint('[新番-弹弹play] 没有找到缓存数据');
      return null;
    } catch (e) {
      //debugPrint('[新番-弹弹play] 加载缓存数据时出错: ${e.toString()}');
      return null;
    }
  }

  Future<BangumiAnime> getAnimeDetails(int animeId) async {
    // 检查内存缓存
    if (_detailsCache.containsKey(animeId)) {
      final cacheTime = _detailsCacheTime[animeId];
      if (cacheTime != null && _isCacheValid(animeId, cacheTime)) {
        final cachedAnime = _detailsCache[animeId]!;
        // 检查缓存数据是否包含标签信息
        if (cachedAnime.tags != null && cachedAnime.tags!.isNotEmpty) {
          debugPrint('[番剧服务] 从内存缓存获取番剧 $animeId 的详情 (缓存时间: ${_getCacheDurationForAnime(animeId).inHours}小时)');
          return cachedAnime;
        } else {
          debugPrint('[番剧服务] 番剧 $animeId 的内存缓存缺少标签信息，将重新获取');
          // 移除缓存，强制重新获取
          _detailsCache.remove(animeId);
          _detailsCacheTime.remove(animeId);
        }
      } else {
        debugPrint('[番剧服务] 番剧 $animeId 的内存缓存已过期');
      }
    }
    
    // 检查磁盘缓存
    final diskCachedDetail = await _loadDetailFromCache(animeId);
    if (diskCachedDetail != null) {
      // 检查磁盘缓存是否包含标签信息
      if (diskCachedDetail.tags != null && diskCachedDetail.tags!.isNotEmpty) {
        debugPrint('[番剧服务] 从磁盘缓存获取番剧 $animeId 的详情成功');
        return diskCachedDetail;
      } else {
        debugPrint('[番剧服务] 番剧 $animeId 的磁盘缓存缺少标签信息，将重新获取');
        // 删除有问题的磁盘缓存
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = '$_detailsCacheKeyPrefix$animeId';
        await prefs.remove(cacheKey);
      }
    }

    // 从API获取
    final detailUrl = '$_bangumiDetailUrl$animeId';
    debugPrint('[番剧服务] 从API获取番剧 $animeId 的详情: $detailUrl');
    try {
      final response = await _makeRequest(detailUrl);
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedResponse = json.decode(utf8.decode(response.bodyBytes));
        if (decodedResponse['success'] == true && decodedResponse['bangumi'] != null) {
          final anime = BangumiAnime.fromDandanplayDetail(decodedResponse['bangumi'] as Map<String, dynamic>);
          
          // 验证获取的数据是否包含标签
          if (anime.tags != null && anime.tags!.isNotEmpty) {
            debugPrint('[番剧服务] API获取的番剧 $animeId 包含 ${anime.tags!.length} 个标签');
          } else {
            debugPrint('[番剧服务] 警告：API获取的番剧 $animeId 没有标签信息');
          }
          
          // 更新内存缓存
          _detailsCache[animeId] = anime;
          _detailsCacheTime[animeId] = DateTime.now();
          final cacheDuration = _getCacheDurationForAnime(animeId);
          debugPrint('[番剧服务] 成功从API获取番剧 $animeId 的详情并缓存到内存 (缓存时间: ${cacheDuration.inHours}小时)');
          
          // 异步保存到磁盘缓存
          _saveDetailToCache(animeId, anime).then((_) {
            debugPrint('[番剧服务] 番剧 $animeId 详情已异步保存到磁盘缓存');
          });
          
          return anime;
        } else {
          debugPrint('[番剧服务] 详情API请求成功但响应格式无效: ${decodedResponse['errorMessage']}');
          throw Exception('获取番剧详情失败: ${decodedResponse['errorMessage'] ?? '未知API错误'}');
        }
      } else if (response.statusCode == 404) {
        debugPrint('[番剧服务] 番剧 $animeId 未找到 (404)');
        throw Exception('未找到该番剧: $animeId');
      } else {
        debugPrint('[番剧服务] 获取番剧 $animeId 详情失败: HTTP ${response.statusCode}');
        throw Exception('获取番剧 $animeId 详情失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[番剧服务] 获取番剧 $animeId 详情时出错: $e');
      rethrow;
    }
  }
  
  // 清理过期的番剧详情缓存
  Future<void> cleanExpiredDetailCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final detailsKeys = keys.where((key) => key.startsWith(_detailsCacheKeyPrefix)).toList();
      final now = DateTime.now().millisecondsSinceEpoch;
      int removedCount = 0;
      
      for (var key in detailsKeys) {
        try {
          final String? cachedString = prefs.getString(key);
          if (cachedString != null) {
            final data = json.decode(cachedString);
            final timestamp = data['timestamp'] as int;
            final animeId = int.parse(key.substring(_detailsCacheKeyPrefix.length));
            
            final cacheDuration = _getCacheDurationForAnime(animeId);
            
            // 检查是否过期
            if (now - timestamp > cacheDuration.inMilliseconds) {
              await prefs.remove(key);
              removedCount++;
            }
          }
        } catch (e) {
          debugPrint('[番剧服务] 清理单个番剧详情缓存失败: $e');
          continue;
        }
      }
      
      debugPrint('[番剧服务] 清理了 $removedCount 条过期的番剧详情缓存');
      
      // 同时清理内存缓存
      final expiredIds = <int>[];
      _detailsCacheTime.forEach((id, time) {
        if (!_isCacheValid(id, time)) {
          expiredIds.add(id);
        }
      });
      
      for (var id in expiredIds) {
        _detailsCache.remove(id);
        _detailsCacheTime.remove(id);
      }
      
      debugPrint('[番剧服务] 清理了 ${expiredIds.length} 条过期的内存缓存');
    } catch (e) {
      debugPrint('[番剧服务] 清理过期番剧详情缓存失败: $e');
    }
  }

  // 保存详情数据到磁盘缓存
  Future<void> _saveDetailToCache(int animeId, BangumiAnime animeDetail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'animeDetail': animeDetail.toJson(),
      };
      
      final cacheKey = '$_detailsCacheKeyPrefix$animeId';
      await prefs.setString(cacheKey, json.encode(data));
      final cacheDuration = _getCacheDurationForAnime(animeId);
      //debugPrint('[番剧服务] 番剧 $animeId 详情已保存到磁盘缓存 (缓存时间: ${cacheDuration.inHours}小时)');
    } catch (e) {
      debugPrint('[番剧服务] 保存番剧详情到磁盘缓存失败: $e');
    }
  }

  // 从磁盘缓存加载详情数据
  Future<BangumiAnime?> _loadDetailFromCache(int animeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_detailsCacheKeyPrefix$animeId';
      final String? cachedString = prefs.getString(cacheKey);
      
      if (cachedString != null) {
        final data = json.decode(cachedString);
        final timestamp = data['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        
        debugPrint('[番剧服务] 找到番剧 $animeId 的磁盘缓存，缓存时间: $cacheTime');
        
        // 使用动态缓存时间
        final cacheDuration = _getCacheDurationForAnime(animeId);
        
        // 检查是否过期
        if (now - timestamp <= cacheDuration.inMilliseconds) {
          final Map<String, dynamic> animeData = data['animeDetail'];
          
          // 加载到内存缓存
          final animeDetail = BangumiAnime.fromDandanplayDetail(animeData);
          _detailsCache[animeId] = animeDetail;
          _detailsCacheTime[animeId] = DateTime.fromMillisecondsSinceEpoch(timestamp);
          
          debugPrint('[番剧服务] 从磁盘缓存成功加载番剧 $animeId 的详情 (缓存时间: ${cacheDuration.inHours}小时)');
          return animeDetail;
        } else {
          debugPrint('[番剧服务] 番剧 $animeId 的磁盘缓存已过期，将从网络重新获取');
          await prefs.remove(cacheKey);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[番剧服务] 从磁盘加载番剧 $animeId 详情失败: $e');
      return null;
    }
  }

  // 预加载常用的番剧数据，用于页面预热
  Future<void> preloadCommonData() async {
    try {
      debugPrint('[番剧服务] 开始预加载常用番剧数据');
      
      // 尝试加载番剧日历数据
      if (_preloadedAnimes == null) {
        await loadData();
      }
      
      // 如果前两天查看过番剧详情，预加载它们
      await _preloadRecentPopularAnimes();
      
      debugPrint('[番剧服务] 常用番剧数据预加载完成');
    } catch (e) {
      debugPrint('[番剧服务] 预加载常用番剧数据失败: $e');
    }
  }
  
  // 预加载最近流行的动画
  Future<void> _preloadRecentPopularAnimes() async {
    try {
      // 这里可以根据实际需求预加载某些特定类别或热门的番剧
      // 比如每季度新番、高分作品等
      // 为了演示，我们这里只预加载日历中的前5个番剧详情
      if (_preloadedAnimes != null && _preloadedAnimes!.isNotEmpty) {
        final animesToPreload = _preloadedAnimes!.take(5).toList();
        
        for (final anime in animesToPreload) {
          if (!_detailsCache.containsKey(anime.id)) {
            // 异步加载，不等待完成
            getAnimeDetails(anime.id).catchError((e) {
              // 忽略预加载错误
              debugPrint('[番剧服务] 预加载番剧 ${anime.id} 详情失败: $e');
            });
            
            // 短暂延迟以避免并发请求过多
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    } catch (e) {
      debugPrint('[番剧服务] 预加载热门番剧失败: $e');
    }
  }
  
  // 检查是否已经缓存了番剧详情
  Future<bool> hasCachedAnimeDetails(int animeId) async {
    // 检查内存缓存
    if (_detailsCache.containsKey(animeId)) {
      final cacheTime = _detailsCacheTime[animeId];
      if (cacheTime != null && _isCacheValid(animeId, cacheTime)) {
        return true;
      }
    }
    
    // 检查磁盘缓存
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_detailsCacheKeyPrefix$animeId';
      final String? cachedString = prefs.getString(cacheKey);
      
      if (cachedString != null) {
        final data = json.decode(cachedString);
        final timestamp = data['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        final cacheDuration = _getCacheDurationForAnime(animeId);
        
        // 检查是否过期
        if (now - timestamp <= cacheDuration.inMilliseconds) {
          return true;
        }
      }
    } catch (e) {
      // 出错时假设没有缓存
      debugPrint('[番剧服务] 检查番剧 $animeId 缓存状态时出错: $e');
    }
    
    return false;
  }

  // 检查并刷新缺少标签的缓存数据
  Future<void> checkAndRefreshCacheWithoutTags() async {
    try {
      debugPrint('[番剧服务] 开始检查缺少标签的缓存数据');
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final detailsKeys = keys.where((key) => key.startsWith(_detailsCacheKeyPrefix)).toList();
      final keysToRefresh = <int>[];
      
      // 检查内存缓存
      _detailsCache.forEach((animeId, anime) {
        if (anime.tags == null || anime.tags!.isEmpty) {
          keysToRefresh.add(animeId);
        }
      });
      
      // 检查磁盘缓存
      for (var key in detailsKeys) {
        try {
          final String? cachedString = prefs.getString(key);
          if (cachedString != null) {
            final data = json.decode(cachedString);
            final animeId = int.parse(key.substring(_detailsCacheKeyPrefix.length));
            
            // 跳过已在内存中检查过的
            if (keysToRefresh.contains(animeId)) continue;
            
            final Map<String, dynamic> animeData = data['animeDetail'];
            
            // 检查是否缺少标签
            final tags = animeData['tags'] as List<dynamic>?;
            if (tags == null || tags.isEmpty) {
              keysToRefresh.add(animeId);
            }
          }
        } catch (e) {
          debugPrint('[番剧服务] 检查单个缓存失败: $e');
          continue;
        }
      }
      
      if (keysToRefresh.isNotEmpty) {
        debugPrint('[番剧服务] 发现 ${keysToRefresh.length} 个缺少标签的缓存，将在后台刷新');
        
        // 后台刷新这些缓存（不阻塞UI）
        Future.microtask(() async {
          for (var animeId in keysToRefresh) {
            try {
              // 移除旧缓存
              _detailsCache.remove(animeId);
              _detailsCacheTime.remove(animeId);
              final cacheKey = '$_detailsCacheKeyPrefix$animeId';
              await prefs.remove(cacheKey);
              
              // 重新获取（这会触发网络请求并重新缓存）
              await getAnimeDetails(animeId);
              debugPrint('[番剧服务] 已刷新番剧 $animeId 的缓存');
              
              // 每次请求后稍微延迟，避免过于频繁的网络请求
              await Future.delayed(const Duration(milliseconds: 200));
            } catch (e) {
              debugPrint('[番剧服务] 刷新番剧 $animeId 缓存失败: $e');
            }
          }
          debugPrint('[番剧服务] 完成缺少标签的缓存刷新');
        });
      } else {
        debugPrint('[番剧服务] 所有缓存数据都包含标签信息');
      }
    } catch (e) {
      debugPrint('[番剧服务] 检查缓存标签失败: $e');
    }
  }
}

class _RequestItem {
  final String url;
  final int maxRetries;
  final int priority;
  final Completer<http.Response> completer;

  _RequestItem(this.url, this.maxRetries, this.priority, this.completer);
} 