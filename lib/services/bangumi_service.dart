import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay_core/models/bangumi_model.dart';
import './dandanplay_service.dart';
import 'package:nipaplay_core/services/web_remote_access_service.dart';
import 'package:nipaplay/utils/chinese_converter.dart';

class BangumiService {
  static final BangumiService instance = BangumiService._();
  static const String _basePath = '/api/v2';

  static const String _cacheKey = 'dandanplay_shin_cache';
  static const String _detailsCacheKeyPrefix = 'bangumi_detail_';
  static const String backupAnimeDetailKeyPrefix = 'animeDetail:';
  static const String _customBackgroundKeyPrefix = 'bangumi_custom_background_';
  static const Duration _defaultCacheDuration = Duration(hours: 3);
  static const int _oldAnimeThreshold = 18343; // 和弹幕缓存使用相同的判断标准
  static const Duration _oldAnimeCacheDuration = Duration(days: 7);
  static const Duration _newAnimeCacheDuration = Duration(hours: 24);
  // 简介这类元数据变化慢。读取路径已经改成「过期也先返回旧数据、再后台
  // 回源」，TTL 只决定回源频率、不再决定用户能否看到内容，所以可以把
  // 新番 TTL 从 6h 放宽到 24h，显著降低重启后的重取量。
  static const int _maxConcurrentRequests = 6;
  // 过期缓存不再立刻删除，而是作为 stale 数据继续可用；只有超过这个
  // 硬性保留期才真正丢弃，避免脏数据无限累积。
  static const Duration _staleRetention = Duration(days: 30);

  final Map<String, BangumiAnime> _listCache = {};
  final Map<int, BangumiAnime> _detailsCache = {};
  final Map<int, DateTime> _detailsCacheTime = {};
  // 同一 animeId 的并发详情请求共享同一个 Future，避免媒体库列表、详情页、
  // 首页各自打一发请求把仅有的并发槽占满。
  final Map<int, Future<BangumiAnime>> _inflightDetails = {};
  // 正在后台回源的 animeId，防止 stale 数据触发重复刷新。
  final Set<int> _backgroundRefreshes = <int>{};
  bool _isInitialized = false;
  List<BangumiAnime>? _preloadedAnimes;
  late http.Client _client;
  final _requestQueue = <_RequestItem>[];
  int _activeRequestCount = 0;

  BangumiService._() {
    _client = http.DandanplayHttpClient();
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
      //debugPrint('[番剧服务] 正在预加载缓存的番剧详情到内存');
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      final detailsKeys =
          keys.where((key) => key.startsWith(_detailsCacheKeyPrefix)).toList();
      int loadedCount = 0;

      for (var key in detailsKeys) {
        try {
          final String? cachedString = prefs.getString(key);
          if (cachedString != null) {
            final data = json.decode(cachedString);
            final timestamp = data['timestamp'] as int;
            final now = DateTime.now().millisecondsSinceEpoch;
            final animeId =
                int.parse(key.substring(_detailsCacheKeyPrefix.length));

            // stale-while-revalidate：启动预加载不再按 TTL 删除。超过 TTL 但
            // 仍在保留期内的条目照常载入内存作为 stale 数据（读取路径负责
            // 后台回源），只有超过 _staleRetention 才真正丢弃。此前这里一到
            // 重启就把所有过 TTL 的简介删光，媒体库随即整页走网络重取——
            // 用户反馈的「重启后几部番剧重新获取」的直接来源之一。
            final isTooOld = now - timestamp > _staleRetention.inMilliseconds;

            final Map<String, dynamic> animeData =
                Map<String, dynamic>.from(data['animeDetail'] as Map);
            final animeDetail = BangumiAnime.fromJson(animeData);
            await _persistCustomBackground(animeDetail);

            if (!isTooOld || animeId < 0) {
              _detailsCache[animeId] = animeDetail;
              _detailsCacheTime[animeId] =
                  DateTime.fromMillisecondsSinceEpoch(timestamp);
              loadedCount++;
            } else {
              // 超过保留期才删除
              await prefs.remove(key);
            }
          }
        } catch (e) {
          //debugPrint('[番剧服务] 预加载单个番剧详情缓存失败: $e');
          continue;
        }
      }

      //debugPrint('[番剧服务] 预加载了 $loadedCount 条番剧详情到内存缓存');
    } catch (e) {
      //debugPrint('[番剧服务] 预加载番剧详情缓存失败: $e');
    }
  }

  // 同步获取内存缓存中的番剧详情
  BangumiAnime? getAnimeDetailsFromMemory(int animeId) {
    if (_detailsCache.containsKey(animeId)) {
      // 即使缓存过期也返回数据，优先保证显示
      return _detailsCache[animeId];
    }
    return null;
  }

  String _customBackgroundKey(int animeId) =>
      '$_customBackgroundKeyPrefix$animeId';

  Future<void> _persistCustomBackground(BangumiAnime anime) async {
    final url = anime.backgroundImageUrl?.trim();
    if (url?.isNotEmpty != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customBackgroundKey(anime.id), url!);
  }

  Future<BangumiAnime> _mergeCustomBackground(BangumiAnime anime) async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_customBackgroundKey(anime.id))?.trim();
    if (url?.isNotEmpty != true) return anime;
    return anime.copyWith(backgroundImageUrl: url);
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

  Future<http.Response> _makeRequest(String url,
      {int maxRetries = 3, int priority = 0}) async {
    final completer = Completer<http.Response>();
    _requestQueue.add(_RequestItem(url, maxRetries, priority, completer));
    _pumpQueue();
    return completer.future;
  }

  /// 调度器：始终保持最多 `_maxConcurrentRequests` 个在途请求。
  ///
  /// 早期实现是「一次取满并发数后 `Future.wait`，整批完成才取下一批」，
  /// 于是单个慢请求（尤其是无优先级的日历大包）会让后面所有请求排队等它，
  /// 简介请求的实际并发可能永远到不了 3。改为谁空闲谁取下一个。
  void _pumpQueue() {
    while (_activeRequestCount < _maxConcurrentRequests &&
        _requestQueue.isNotEmpty) {
      _requestQueue.sort((a, b) => b.priority.compareTo(a.priority));
      final item = _requestQueue.removeAt(0);
      _activeRequestCount++;
      _executeRequest(item).whenComplete(() {
        _activeRequestCount--;
        _pumpQueue();
      });
    }
  }

  Future<void> _executeRequest(_RequestItem item) async {
    int retryCount = 0;
    while (retryCount < item.maxRetries) {
      try {
        const String appId = DandanplayService.appId;
        final String appSecret = await DandanplayService.getAppSecret();
        final int timestamp =
            (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();

        final Uri parsedUri = Uri.parse(item.url);
        final String apiPath = parsedUri.path;

        final String signature = DandanplayService.generateSignature(
            appId, timestamp, apiPath, appSecret);

        final response = await _client.get(
          WebRemoteAccessService.proxyUri(Uri.parse(item.url)),
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'NipaPlay/1.0',
            'X-AppId': appId,
            'X-Timestamp': timestamp.toString(),
            'X-Signature': signature,
          },
        // 首试 12s：反代在正常网络下回包远快于此，卡住的多半是代理侧
        // 超时，等 15s 只会白白拖住一个并发槽。
        ).timeout(const Duration(seconds: 12), onTimeout: () {
          throw TimeoutException('请求超时');
        });

        if (response.statusCode == 200) {
          item.completer.complete(response);
          return;
        } else {
          if (response.bodyBytes.length < 1000) {}
          throw Exception('HTTP请求失败: ${response.statusCode}');
        }
      } catch (e) {
        if (e is http.DandanplayLoginRequired) {
          item.completer.completeError(e);
          return;
        }
        retryCount++;
        if (retryCount == item.maxRetries) {
          item.completer.completeError(Exception('请求失败，已达到最大重试次数: $e'));
          return;
        }
        // 抖动的指数退避（500ms/1s/2s + 0~250ms）替代原来的固定 2s/4s：
        // 重试总墙钟时间从 6s 降到约 3.75s，且多个并发失败请求不会同时
        // 在同一毫秒打回去。
        final backoffMs = (500 << retryCount).clamp(500, 2000);
        await Future.delayed(
          Duration(milliseconds: backoffMs + (DateTime.now().microsecondsSinceEpoch % 251)),
        );
      }
    }
  }

  Future<List<BangumiAnime>> getCalendar(
      {bool forceRefresh = false, bool filterAdultContent = true}) async {
    // 优先尝试从缓存加载
    if (!forceRefresh) {
      try {
        final cachedData = await _loadFromCache();
        if (cachedData != null && cachedData.isNotEmpty) {
          //debugPrint('[新番-弹弹play] 命中本地缓存，直接返回');
          _preloadedAnimes = List.from(cachedData);
          return cachedData;
        }
      } catch (e) {
        //debugPrint('[新番-弹弹play] 读取缓存失败: $e');
      }
    }

    //debugPrint('[新番-弹弹play] getCalendar - Strategy: Network first, then cache. forceRefresh: $forceRefresh, filterAdultContent: $filterAdultContent');

    // If forceRefresh is true, we definitely skip trying memory cache first before network.
    // However, the new strategy is always network first unless network fails.

    final baseUrl = await DandanplayService.getApiBaseUrl();
    final apiUrl =
        '$baseUrl$_basePath/bangumi/shin?filterAdultContent=$filterAdultContent';
    //debugPrint('[新番-弹弹play] Attempting to fetch from API: $apiUrl');

    try {
      final response = await _makeRequest(apiUrl,
          priority: 1); // Higher priority for user-facing calendar
      //debugPrint('[新番-弹弹play] API response: Status=${response.statusCode}, Length=${response.bodyBytes.length}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedResponse =
            json.decode(utf8.decode(response.bodyBytes));
        if (decodedResponse['success'] == true &&
            decodedResponse['bangumiList'] != null) {
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
          _listCache
              .clear(); // Clear old memory list cache before populating with new data
          for (var animeData in data) {
            try {
              var anime = BangumiAnime.fromDandanplayIntro(
                  animeData as Map<String, dynamic>);
              // 转换为繁体中文（如果需要）
              anime = await ChineseConverter.convertAnime(anime);
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
          throw Exception(
              'Failed to load shin bangumi from API: ${decodedResponse['errorMessage'] ?? 'Unknown API error'}');
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
        for (var anime in cachedData) {
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
              .map((d) => BangumiAnime.fromJson(d as Map<String, dynamic>))
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

  /// 对外的详情读取入口：在 [_fetchAnimeDetailsInternal] 之上做
  /// in-flight 去重。媒体库列表、详情页、首页可能在同一帧里请求同一个
  /// animeId，各自触发会同时占满并发槽并重复等待。
  ///
  /// [forceRefresh] 为 true 时跳过内存/磁盘快捷路径直接回源（仅用于启动期
  /// 补齐 tags 这类维护任务）。强制请求不参与去重共享：它要的正是「绕过
  /// 现有缓存」，与普通请求的目标不一致。
  Future<BangumiAnime> getAnimeDetails(int animeId,
      {bool forceRefresh = false}) {
    if (forceRefresh) {
      return _fetchAnimeDetailsInternal(animeId, forceRefresh: true);
    }
    final inFlight = _inflightDetails[animeId];
    if (inFlight != null) return inFlight;

    final request = _fetchAnimeDetailsInternal(animeId);
    _inflightDetails[animeId] = request;
    return request.whenComplete(() {
      if (_inflightDetails[animeId] == request) {
        _inflightDetails.remove(animeId);
      }
    });
  }

  Future<BangumiAnime> _fetchAnimeDetailsInternal(int animeId,
      {bool forceRefresh = false}) async {
    // 检查是否需要繁体中文
    final isTraditional =
        await ChineseConverter.isTraditionalChineseEnvironment(null);
    final expectedLanguage = isTraditional ? 'zh_Hant' : 'zh';

// 检查内存缓存
    if (!forceRefresh && _detailsCache.containsKey(animeId)) {
      final cacheTime = _detailsCacheTime[animeId];
      if (cacheTime != null && _isCacheValid(animeId, cacheTime)) {
        final cachedAnime = _detailsCache[animeId]!;
        // 检查缓存数据是否包含标签信息
        if (cachedAnime.tags != null && cachedAnime.tags!.isNotEmpty) {
          // 检查语言是否匹配
          if (cachedAnime.language == expectedLanguage) {
            //debugPrint('[番剧服务] 从内存缓存获取番剧 $animeId 的详情 (缓存时间: ${_getCacheDurationForAnime(animeId).inHours}小时)');
            return cachedAnime;
          } else {
            // 对于自定义媒体信息，即使语言不匹配也返回
            if (animeId < 0) {
              //debugPrint('[番剧服务] 从内存缓存获取语言不匹配的自定义番剧 $animeId 的详情');
              return cachedAnime;
            }
            // 对正常番剧，语言不匹配依然重取
            //debugPrint('[番剧服务] 番剧 $animeId 的内存缓存语言不匹配，将重新获取');
            // 不再直接移除，而是先返回旧数据，随后 API 成功后异步回源
            // 避免每次打开简介都触发网络请求（原行为导致缓存永不命中）
            if (!_backgroundRefreshes.contains(animeId)) {
              _backgroundRefreshes.add(animeId);
              _scheduleRefreshFromMemory(animeId);
            }
            return cachedAnime;
          }
        } else {
          // 标签缺失是 API 的合法状态（部分番剧不返回 tags），不再视为
          // 损坏强制重取——否则这类番剧缓存永不命中，每次打开简介都重新
          // 加载（用户反馈）。
          if (animeId < 0 || cachedAnime.language == expectedLanguage) {
            return cachedAnime;
          }
          // 语言不匹配且有标志的情况：先返回旧数据，后台再回源
          if (!_backgroundRefreshes.contains(animeId)) {
            _backgroundRefreshes.add(animeId);
            _scheduleRefreshFromMemory(animeId);
          }
          return cachedAnime;
        }
      } else {
        // 对于自定义媒体信息，即使缓存过期也返回
        if (animeId < 0 && _detailsCache.containsKey(animeId)) {
          //debugPrint('[番剧服务] 从内存缓存获取过期的自定义番剧 $animeId 的详情');
          return _detailsCache[animeId]!;
        }
        // 缓存已过期，也不再直接移除：改为返回旧数据，随后后台异步回源
        // 以保证用户感知的加载速度不受影响
        //debugPrint('[番剧服务] 番剧 $animeId 的内存缓存已过期，返回旧数据');
        // 若有后台任务在排队则跳过重排，避免重入
        if (!_backgroundRefreshes.contains(animeId)) {
          _backgroundRefreshes.add(animeId);
          _scheduleRefreshFromMemory(animeId);
        }
        return _detailsCache[animeId]!;
      }
    }

    // 检查磁盘缓存（forceRefresh 时直接跳到 API）
    final diskCachedDetail =
        forceRefresh ? null : await _loadDetailFromCache(animeId);
    if (diskCachedDetail != null) {
      // 对于自定义媒体信息，直接返回缓存数据，不检查标签和语言
      if (animeId < 0) {
        //debugPrint('[番剧服务] 从磁盘缓存获取自定义番剧 $animeId 的详情');
        return diskCachedDetail;
      }

      // 对于正常番剧只检查语言：标签缺失是 API 合法状态（与内存缓存同
      // 规则），不再当损坏数据丢弃——否则这类番剧缓存永不命中，每次打
      // 开简介都重新加载（用户反馈）。
      if (diskCachedDetail.language == expectedLanguage) {
        //debugPrint('[番剧服务] 从磁盘缓存获取番剧 $animeId 的详情成功');
        return diskCachedDetail;
      }
      //debugPrint('[番剧服务] 番剧 $animeId 的磁盘缓存语言不匹配，将重新获取');
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_detailsCacheKeyPrefix$animeId';
      await prefs.remove(cacheKey);
    }

    // 对于自定义媒体信息（animeId为负数），尝试从本地数据生成
    if (animeId < 0) {
      // 这里可以从WatchHistoryProvider获取相关数据生成BangumiAnime
      // 暂时返回一个基本的BangumiAnime对象
      final anime = BangumiAnime(
        id: animeId,
        name: '自定义媒体',
        nameCn: '自定义媒体',
        imageUrl: '',
        summary: '自定义媒体信息',
        bangumiUrl: '',
        airDate: DateTime.now().toIso8601String(),
        airWeekday: null,
        isOnAir: false,
        totalEpisodes: 0,
        rating: 0.0,
        ratingDetails: {},
        tags: [],
        metadata: [],
        typeDescription: '自定义',
        isNSFW: false,
        platform: '',
        isFavorited: false,
        titles: [],
        searchKeyword: '',
        language: expectedLanguage,
        episodeList: [],
      );

      // 保存到缓存
      _detailsCache[animeId] = anime;
      _detailsCacheTime[animeId] = DateTime.now();
      _saveDetailToCache(animeId, anime);

      return anime;
    }

    // 从API获取
    final baseUrl = await DandanplayService.getApiBaseUrl();
    final detailUrl = '$baseUrl$_basePath/bangumi/$animeId';
    //debugPrint('[番剧服务] 从API获取番剧 $animeId 的详情: $detailUrl');
    try {
      final response = await _makeRequest(detailUrl);

      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedResponse =
            json.decode(utf8.decode(response.bodyBytes));
        if (decodedResponse['success'] == true &&
            decodedResponse['bangumi'] != null) {
          var anime = BangumiAnime.fromDandanplayDetail(
              decodedResponse['bangumi'] as Map<String, dynamic>);

          // 验证获取的数据是否包含标签
          if (anime.tags != null && anime.tags!.isNotEmpty) {
            //debugPrint('[番剧服务] API获取的番剧 $animeId 包含 ${anime.tags!.length} 个标签');
          } else {
            //debugPrint('[番剧服务] 警告：API获取的番剧 $animeId 没有标签信息');
          }

          // 转换为繁体中文（如果需要）
          anime = await ChineseConverter.convertAnime(anime);
          // 用户背景是本地元数据，API 刷新不能覆盖它。
          anime = await _mergeCustomBackground(anime);

          // 更新内存缓存
          _detailsCache[animeId] = anime;
          _detailsCacheTime[animeId] = DateTime.now();
          final cacheDuration = _getCacheDurationForAnime(animeId);
          //debugPrint('[番剧服务] 成功从API获取番剧 $animeId 的详情并缓存到内存 (缓存时间: ${cacheDuration.inHours}小时)');

          // 异步保存到磁盘缓存
          _saveDetailToCache(animeId, anime).then((_) {
            //debugPrint('[番剧服务] 番剧 $animeId 详情已异步保存到磁盘缓存');
          });

          return anime;
        } else {
          //debugPrint('[番剧服务] 详情API请求成功但响应格式无效: ${decodedResponse['errorMessage']}');
          throw Exception(
              '获取番剧详情失败: ${decodedResponse['errorMessage'] ?? '未知API错误'}');
        }
      } else if (response.statusCode == 404) {
        //debugPrint('[番剧服务] 番剧 $animeId 未找到 (404)');
        throw Exception('未找到该番剧: $animeId');
      } else {
        //debugPrint('[番剧服务] 获取番剧 $animeId 详情失败: HTTP ${response.statusCode}');
        throw Exception('获取番剧 $animeId 详情失败: ${response.statusCode}');
      }
    } catch (e) {
      //debugPrint('[番剧服务] 获取番剧 $animeId 详情时出错: $e');
      rethrow;
    }
  }

  // 清理过期的番剧详情缓存
  Future<void> cleanExpiredDetailCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final detailsKeys =
          keys.where((key) => key.startsWith(_detailsCacheKeyPrefix)).toList();
      final now = DateTime.now().millisecondsSinceEpoch;
      int removedCount = 0;

      for (var key in detailsKeys) {
        try {
          final String? cachedString = prefs.getString(key);
          if (cachedString != null) {
            final data = json.decode(cachedString);
            final timestamp = data['timestamp'] as int;
            final animeId =
                int.parse(key.substring(_detailsCacheKeyPrefix.length));

            // 跳过自定义媒体信息（animeId为负数）
            if (animeId < 0) {
              continue;
            }

            // 与 _loadDetailFromCache 的 stale-while-revalidate 对齐：TTL 过期
            // 的缓存是「待回源的 stale 数据」而不是垃圾，只有超过
            // _staleRetention 才真正删除。此前每次打开详情页都会按 TTL 批量
            // 删除，等于把软过期缓存全部清光，详情页每次都得走网络。
            if (now - timestamp > _staleRetention.inMilliseconds) {
              final raw = data['animeDetail'];
              final anime = raw is Map
                  ? BangumiAnime.fromJson(Map<String, dynamic>.from(raw))
                  : null;
              await _persistCustomBackgroundIfPresent(anime);
              if (anime?.backgroundImageUrl?.trim().isNotEmpty != true) {
                await prefs.remove(key);
                removedCount++;
              }
            }
          }
        } catch (e) {
          //debugPrint('[番剧服务] 清理单个番剧详情缓存失败: $e');
          continue;
        }
      }

      //debugPrint('[番剧服务] 清理了 $removedCount 条过期的番剧详情缓存');

      // 同时清理内存缓存（同一保留期口径）
      final expiredIds = <int>[];
      _detailsCacheTime.forEach((id, time) {
        // 跳过自定义媒体信息（animeId为负数）
        if (id < 0) {
          return;
        }
        if (DateTime.now().difference(time) > _staleRetention) {
          expiredIds.add(id);
        }
      });

      for (var id in expiredIds) {
        _detailsCache.remove(id);
        _detailsCacheTime.remove(id);
      }

      //debugPrint('[番剧服务] 清理了 ${expiredIds.length} 条过期的内存缓存');
    } catch (e) {
      //debugPrint('[番剧服务] 清理过期番剧详情缓存失败: $e');
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
      ////debugPrint('[番剧服务] 番剧 $animeId 详情已保存到磁盘缓存 (缓存时间: ${cacheDuration.inHours}小时)');
    } catch (e) {
      //debugPrint('[番剧服务] 保存番剧详情到磁盘缓存失败: $e');
    }
  }

  Future<void> _persistCustomBackgroundIfPresent(BangumiAnime? anime) async {
    if (anime == null) return;
    await _persistCustomBackground(anime);
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

        //debugPrint('[番剧服务] 找到番剧 $animeId 的磁盘缓存，缓存时间: $cacheTime');

        // 使用动态缓存时间（支持新旧番两套 TTL）
        final cacheDuration = _getCacheDurationForAnime(animeId);

        // 检查是否过期（软过期：先返回旧数据，后台惰性回源）
        bool isExpired = now - timestamp > cacheDuration.inMilliseconds;

        // 对于自定义媒体信息（animeId为负数），即使缓存过期也返回
        final Map<String, dynamic> animeData =
            Map<String, dynamic>.from(data['animeDetail'] as Map);
        final animeDetail = BangumiAnime.fromJson(animeData);
        await _persistCustomBackground(animeDetail);

        // ============= OPTIMIZATION: stale-while-revalidate =============
        // 硬性丢弃前的检查：超过 _staleRetention 天的数据才真正删除，
        // 中间段（cacheDuration < age < _staleRetention）视为 stale 继续可用
        bool isTooOld = now - timestamp > _staleRetention.inMilliseconds;
        if (isTooOld && animeDetail.backgroundImageUrl?.trim().isNotEmpty != true) {
          // 真正过期，清除磁盘缓存，让后续请求重取
          await prefs.remove(cacheKey);
          // 同时从内存移除，保持一致性
          _detailsCache.remove(animeId);
          _detailsCacheTime.remove(animeId);
          return null;
        }
        // 只要没超过 _staleRetention，无论 isExpired 如何都先返回旧数据
        // （若过期了，用户看到的是最后一次成功的简介；随后后台会惰性回源）
        // 加载到内存缓存（即使已标为 expired，也继续显示，以保用户感知不中断）
        _detailsCache[animeId] = animeDetail;
        _detailsCacheTime[animeId] =
            DateTime.fromMillisecondsSinceEpoch(timestamp);
        //debugPrint('[番剧服务] 从磁盘缓存成功加载番剧 $animeId 的详情 (缓存时间: ${cacheDuration.inHours}小时)');
        return animeDetail;
      }
      return null;
    } catch (e) {
      //debugPrint('[番剧服务] 从磁盘加载番剧 $animeId 详情失败: $e');
      return null;
    }
  }

  // 预加载常用的番剧数据，用于页面预热
  Future<void> preloadCommonData() async {
    try {
      //debugPrint('[番剧服务] 开始预加载常用番剧数据');

      // 尝试加载番剧日历数据
      if (_preloadedAnimes == null) {
        await loadData();
      }

      // 如果前两天查看过番剧详情，预加载它们
      await _preloadRecentPopularAnimes();

      //debugPrint('[番剧服务] 常用番剧数据预加载完成');
    } catch (e) {
      //debugPrint('[番剧服务] 预加载常用番剧数据失败: $e');
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
            // 异步加载，不等待完成；预加载失败只需吞掉，不值得让
            // Future<BangumiAnime> 的 catchError 返回一个假数据
            unawaited(getAnimeDetails(anime.id).then<void>((_) {}, onError: (_) {}));

            // 短暂延迟以避免并发请求过多
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    } catch (e) {
      //debugPrint('[番剧服务] 预加载热门番剧失败: $e');
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
      //debugPrint('[番剧服务] 检查番剧 $animeId 缓存状态时出错: $e');
    }

    return false;
  }

  /// 启动期回源清扫（原名 checkAndRefreshCacheWithoutTags，行为已演进）。
  ///
  /// 挑出已过 TTL 的详情缓存，在后台做有预算的强制回源，让媒体库的陈旧
  /// 简介每次启动悄悄更新一批；tags 缺失的补齐搭这趟车（无 tags 已被读
  /// 路径视为合法状态，不再单独作筛选条件——否则 API 永不返回 tags 的
  /// 番剧会永久占用全部预算，过期番剧反而永远轮不到）。
  ///
  /// 历史行为是「先删缓存再逐条串行重取」：重启后简介先被清空、再慢速
  /// 回源，即用户反馈的「重启后几部番剧重新获取且很慢」。现在：
  /// 1. 旧缓存留在原地，stale-while-revalidate 保证用户始终看到内容；
  /// 2. forceRefresh 直接回源，成功后覆盖，失败保留旧数据；
  /// 3. 每次启动最多 4 条、条间隔 200ms，没刷到的下个启动周期再试。
  Future<void> revalidateExpiredCacheOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final detailsKeys =
          keys.where((key) => key.startsWith(_detailsCacheKeyPrefix)).toList();
      final keysToRefresh = <int>[];
      final now = DateTime.now().millisecondsSinceEpoch;

      bool isExpired(int animeId, int timestamp) =>
          now - timestamp > _getCacheDurationForAnime(animeId).inMilliseconds;

      // 检查内存缓存
      _detailsCache.forEach((animeId, _) {
        // 跳过自定义媒体信息（animeId为负数）
        if (animeId < 0) return;
        final timestamp = _detailsCacheTime[animeId]?.millisecondsSinceEpoch;
        if (timestamp == null || isExpired(animeId, timestamp)) {
          keysToRefresh.add(animeId);
        }
      });

      // 检查磁盘缓存
      for (var key in detailsKeys) {
        try {
          final String? cachedString = prefs.getString(key);
          if (cachedString != null) {
            final data = json.decode(cachedString);
            final animeId =
                int.parse(key.substring(_detailsCacheKeyPrefix.length));

            // 跳过自定义媒体信息（animeId为负数）
            if (animeId < 0) continue;

            // 跳过已在内存中检查过的
            if (keysToRefresh.contains(animeId)) continue;

            final timestamp = data['timestamp'];
            if (timestamp is int && isExpired(animeId, timestamp)) {
              keysToRefresh.add(animeId);
            }
          }
        } catch (e) {
          //debugPrint('[番剧服务] 检查单个缓存失败: $e');
          continue;
        }
      }

      if (keysToRefresh.isEmpty) return;

      // 后台清扫（不阻塞 UI）
      Future.microtask(() async {
        var budget = 4;
        for (var animeId in keysToRefresh) {
          if (budget <= 0) break;
          budget--;
          try {
            // 回源成功即覆盖缓存；失败保留旧数据，下个启动周期再试
            await getAnimeDetails(animeId, forceRefresh: true);
            //debugPrint('[番剧服务] 已刷新番剧 $animeId 的缓存');

            // 每次请求后稍微延迟，避免过于频繁的网络请求
            await Future.delayed(const Duration(milliseconds: 200));
          } catch (e) {
            //debugPrint('[番剧服务] 刷新番剧 $animeId 缓存失败: $e');
          }
        }
        //debugPrint('[番剧服务] 完成启动期缓存回源清扫');
      });
    } catch (e) {
      //debugPrint('[番剧服务] 启动期缓存回源清扫失败: $e');
    }
  }

  /// stale-while-revalidate：把已过期的旧数据立即还给调用方，同时后台
  /// 悄悄回源刷新。回源结果只更新缓存，不打断当前这次读取。
  ///
  /// 之前会话期的行为是「过期即删除缓存并同步重新请求」：媒体库一屏有几
  /// 部番剧就并发打几发请求，共享 3 个并发槽，外加 2s/4s 的线性重试背压，
  /// 最后一页卡片要等十几秒才逐一亮出。
  void _scheduleRefreshFromMemory(int animeId) async {
    // 必须 forceRefresh：调用方正是因为「内存里有但已过期」才走到这里，
    // 普通读取会再次命中同一份过期内存数据直接返回，刷新永远触达不到
    // 网络——stale-while-revalidate 的「revalidate」全靠这条强制路径。
    // 仅 animeId > 0 会被调到这里（自定义媒体在上游分支已提前返回）。
    final request = getAnimeDetails(animeId, forceRefresh: true).then<void>(
      (_) {},
      onError: (Object e) {
        // 回源失败：旧数据已经交给调用方了，这里静默保留即可。
        //debugPrint('[番剧服务] 后台刷新番剧缓存失败: $animeId: $e');
      },
    ).whenComplete(() {
      _backgroundRefreshes.remove(animeId);
    });
    // 保证任何地方调用该方法都不会因为忘记 await 而报未处理异常
    unawaited(request);
  }

  // 保存自定义媒体信息到缓存
  Future<void> saveCustomAnimeDetail(
      int animeId, BangumiAnime animeDetail) async {
    final resolved = await _mergeCustomBackground(animeDetail);
    _detailsCache[animeId] = resolved;
    _detailsCacheTime[animeId] = DateTime.now();
    await _persistCustomBackground(resolved);
    await _saveDetailToCache(animeId, resolved);
  }

  /// 修改详情页背景。传入 null 会恢复为海报。
  Future<BangumiAnime> updateBackgroundImageUrl(
    int animeId,
    String? backgroundImageUrl, {
    BangumiAnime? fallbackAnime,
  }) async {
    var anime = _detailsCache[animeId] ?? fallbackAnime;
    anime ??= await _loadDetailFromCache(animeId);
    anime ??= await getAnimeDetails(animeId);

    final normalized = backgroundImageUrl?.trim();
    final updated = normalized?.isNotEmpty == true
        ? anime.copyWith(backgroundImageUrl: normalized)
        : anime.copyWith(clearBackgroundImageUrl: true);
    final prefs = await SharedPreferences.getInstance();
    if (normalized?.isNotEmpty == true) {
      await prefs.setString(_customBackgroundKey(animeId), normalized!);
    } else {
      await prefs.remove(_customBackgroundKey(animeId));
    }
    await saveCustomAnimeDetail(animeId, updated);
    return updated;
  }

  /// 以逐条记录形式导出番剧详情，便于增量同步按 animeId 合并。
  Future<Map<String, dynamic>> exportAnimeDetailsForBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, dynamic>{};
    for (final key in prefs
        .getKeys()
        .where((key) => key.startsWith(_detailsCacheKeyPrefix))) {
      try {
        final animeId = int.parse(key.substring(_detailsCacheKeyPrefix.length));
        final encoded = prefs.getString(key);
        if (encoded == null) continue;
        final wrapper = json.decode(encoded);
        if (wrapper is! Map || wrapper['animeDetail'] is! Map) continue;
        final anime = BangumiAnime.fromJson(
          Map<String, dynamic>.from(wrapper['animeDetail'] as Map),
        );
        result['$backupAnimeDetailKeyPrefix$animeId'] = anime.toJson();
      } catch (_) {
        // 单条旧缓存损坏不应阻断整个备份。
      }
    }
    return result;
  }

  Future<void> restoreAnimeDetailFromBackup(
    String backupKey,
    Map<String, dynamic> data,
  ) async {
    if (!backupKey.startsWith(backupAnimeDetailKeyPrefix)) return;
    final animeId = int.tryParse(
      backupKey.substring(backupAnimeDetailKeyPrefix.length),
    );
    if (animeId == null) return;
    final decoded = BangumiAnime.fromJson(data);
    final anime =
        decoded.id == animeId ? decoded : decoded.copyWith(id: animeId);
    if (anime.backgroundImageUrl?.trim().isNotEmpty != true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_customBackgroundKey(animeId));
    }
    await saveCustomAnimeDetail(animeId, anime);
  }

  Future<void> deleteAnimeDetailFromBackupKey(String backupKey) async {
    if (!backupKey.startsWith(backupAnimeDetailKeyPrefix)) return;
    final animeId = int.tryParse(
      backupKey.substring(backupAnimeDetailKeyPrefix.length),
    );
    if (animeId == null) return;
    _detailsCache.remove(animeId);
    _detailsCacheTime.remove(animeId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_detailsCacheKeyPrefix$animeId');
    await prefs.remove(_customBackgroundKey(animeId));
  }
}

class _RequestItem {
  final String url;
  final int maxRetries;
  final int priority;
  final Completer<http.Response> completer;

  _RequestItem(this.url, this.maxRetries, this.priority, this.completer);
}
