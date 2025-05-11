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
  static const Duration _cacheDuration = Duration(hours: 3);
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

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
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
        final String appId = DandanplayService.appId;
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
        if (now - timestamp <= _cacheDuration.inMilliseconds) {
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
    if (_detailsCache.containsKey(animeId)) {
      final cacheTime = _detailsCacheTime[animeId];
      if (cacheTime != null && DateTime.now().difference(cacheTime) < _cacheDuration) {
        ////debugPrint('[新番-弹弹play] 从内存缓存获取番剧 $animeId 的详情');
        return _detailsCache[animeId]!;
      }
    }

    final detailUrl = '$_bangumiDetailUrl$animeId';
    ////debugPrint('[新番-弹弹play] 开始从API获取番剧 $animeId 的详情: $detailUrl');
    try {
      final response = await _makeRequest(detailUrl);
      ////debugPrint('[新番-弹弹play] 详情API响应: 状态码=${response.statusCode}, 长度=${response.bodyBytes.length}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedResponse = json.decode(utf8.decode(response.bodyBytes));
        if (decodedResponse['success'] == true && decodedResponse['bangumi'] != null) {
          final anime = BangumiAnime.fromDandanplayDetail(decodedResponse['bangumi'] as Map<String, dynamic>);
          _detailsCache[animeId] = anime;
          _detailsCacheTime[animeId] = DateTime.now();
          ////debugPrint('[新番-弹弹play] 成功获取并缓存番剧 $animeId 的详情');
          return anime;
        } else {
           //debugPrint('[新番-弹弹play] 详情API请求成功但响应格式无效或success为false: ${decodedResponse['errorMessage']}');
          throw Exception('Failed to load anime details: ${decodedResponse['errorMessage'] ?? 'Unknown API error'}');
        }
      } else if (response.statusCode == 404) {
        //debugPrint('[新番-弹弹play] 番剧 $animeId 未找到 (404)');
        throw Exception('Anime not found: $animeId');
      } else {
        //debugPrint('[新番-弹弹play] 获取番剧 $animeId 详情失败: HTTP ${response.statusCode}');
        throw Exception('Failed to load anime details for $animeId: ${response.statusCode}');
      }
    } catch (e) {
      //debugPrint('[新番-弹弹play] 获取番剧 $animeId 详情时出错: ${e.toString()}');
      rethrow;
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