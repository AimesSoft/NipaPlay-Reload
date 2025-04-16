import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bangumi_model.dart';
import '../utils/image_cache_manager.dart';

class BangumiService {
  static final BangumiService instance = BangumiService._();
  static const String _baseUrl = 'https://api.bgm.tv/calendar';
  static const String _animeUrl = 'https://api.bgm.tv/v0/subjects/';
  static const String _cacheKey = 'bangumi_calendar_cache';
  static const Duration _cacheDuration = Duration(hours: 1);
  static const int _maxConcurrentRequests = 3;

  final Map<String, BangumiAnime> _cache = {};
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
      print('[新番] 开始加载番剧数据');
      final animes = await getCalendar();
      _preloadedAnimes = animes;
      print('[新番] 加载番剧数据完成，数量: \\${animes.length}');
      // 去掉图片预加载，图片由页面懒加载
    } catch (e) {
      print('[新番] 加载数据时出错: \\${e.toString()}');
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
      // 按优先级排序请求队列
      _requestQueue.sort((a, b) => b.priority.compareTo(a.priority));
      
      // 处理队列中的请求
      while (_requestQueue.isNotEmpty) {
        final activeRequests = <Future>[];
        final itemsToRemove = <_RequestItem>[];
        
        // 获取最多 _maxConcurrentRequests 个请求
        for (var i = 0; i < _maxConcurrentRequests && _requestQueue.isNotEmpty; i++) {
          final item = _requestQueue.removeAt(0);
          itemsToRemove.add(item);
          activeRequests.add(_executeRequest(item));
        }
        
        // 等待所有请求完成
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
        //print('🌐 发起请求(尝试 ${retryCount+1}/${item.maxRetries}): ${item.url}');
        
        final response = await _client.get(
          Uri.parse(item.url),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=utf-8',
            'User-Agent': 'NipaPlay/1.0',
          },
        ).timeout(
          Duration(seconds: 15 + retryCount * 5),
          onTimeout: () {
            //print('⏱️ 请求超时: ${item.url}');
            throw TimeoutException('请求超时');
          }
        );
        
        //print('📊 HTTP状态: ${response.statusCode}, 内容长度: ${response.bodyBytes.length}');
        
        if (response.statusCode == 200) {
          //print('✅ 请求成功: ${item.url}');
          item.completer.complete(response);
          return;
        } else {
          //print('⚠️ HTTP请求失败: ${response.statusCode}, URL: ${item.url}');
          if (response.bodyBytes.length < 1000) {
            //print('📄 响应内容: ${utf8.decode(response.bodyBytes)}');
          }
          throw Exception('HTTP请求失败: ${response.statusCode}');
        }
      } catch (e) {
        retryCount++;
        //print('❌ 请求失败 (尝试 $retryCount/${item.maxRetries}): $e');
        if (retryCount == item.maxRetries) {
          //print('🛑 达到最大重试次数，放弃请求: ${item.url}');
          item.completer.completeError(Exception('请求失败，已达到最大重试次数: $e'));
          return;
        }
        final waitSeconds = retryCount * 2;
        //print('⏳ 等待 $waitSeconds 秒后重试...');
        await Future.delayed(Duration(seconds: waitSeconds));
      }
    }
  }

  Future<List<BangumiAnime>> getCalendar({bool forceRefresh = false}) async {
    print('[新番] getCalendar(forceRefresh: \\${forceRefresh})');
    if (!forceRefresh && _preloadedAnimes != null) {
      print('[新番] 命中预加载数据');
      return _preloadedAnimes!;
    }

    if (!forceRefresh) {
      if (_cache.isNotEmpty) {
        print('[新番] 命中内存缓存');
        return _cache.values.toList();
      }
      final cachedData = await _loadFromCache();
      if (cachedData != null) {
        print('[新番] 命中本地缓存');
        return cachedData;
      }
    }

    print('[新番] 从API获取新番列表: \\$_baseUrl');
    try {
      final response = await _makeRequest(_baseUrl);
      print('[新番] API响应: 状态码=\\${response.statusCode}, 长度=\\${response.bodyBytes.length}');
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        print('[新番] 解析到天数: \\${data.length}');
        final List<BangumiAnime> animes = [];
        for (var item in data) {
          if (item['items'] != null) {
            final weekdayItems = item['items'] as List;
            print('[新番] 星期 \\${item['weekday'] ?? '?'}: \\${weekdayItems.length} 个番剧');
            for (var animeData in weekdayItems) {
              try {
                final anime = BangumiAnime.fromCalendarItem(animeData);
                _cache[anime.id.toString()] = anime;
                animes.add(anime);
              } catch (e) {
                print('[新番] 跳过无效番剧: \\${e.toString()}');
                continue;
              }
            }
          }
        }
        await _saveToCache(animes);
        print('[新番] 成功获取并缓存 \\${animes.length} 个番剧');
        return animes;
      } else {
        print('[新番] 获取日历数据失败: HTTP \\${response.statusCode}');
        throw Exception('Failed to load calendar: \\${response.statusCode}');
      }
    } catch (e) {
      print('[新番] 获取日历数据时出错: \\${e.toString()}');
      rethrow;
    }
  }

  Future<void> _saveToCache(List<BangumiAnime> animes) async {
    try {
      print('[新番] 保存数据到本地缓存...');
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'animes': animes.map((a) => a.toJson()).toList(),
      };
      await prefs.setString(_cacheKey, json.encode(data));
      print('[新番] 数据已保存到本地存储');
    } catch (e) {
      print('[新番] 保存到本地存储时出错: \\${e.toString()}');
    }
  }

  Future<List<BangumiAnime>?> _loadFromCache() async {
    try {
      print('[新番] 尝试从本地缓存加载数据...');
      final prefs = await SharedPreferences.getInstance();
      final String? cachedString = prefs.getString(_cacheKey);
      if (cachedString != null) {
        final data = json.decode(cachedString);
        final timestamp = data['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        print('[新番] 本地缓存时间戳: \\${timestamp}, 当前: \\${now}');
        if (now - timestamp <= _cacheDuration.inMilliseconds) {
          final List<dynamic> animesData = data['animes'];
          final animes = animesData
              .map((data) => BangumiAnime.fromJson(data))
              .toList();
          for (var anime in animes) {
            _cache[anime.id.toString()] = anime;
          }
          print('[新番] 从本地存储加载了 \\${animes.length} 个番剧');
          return animes;
        } else {
          print('[新番] 缓存已过期');
          return null;
        }
      }
      print('[新番] 没有找到缓存数据');
      return null;
    } catch (e) {
      print('[新番] 加载缓存数据时出错: \\${e.toString()}');
      return null;
    }
  }

  Future<BangumiAnime> getAnimeDetails(int id) async {
    try {
      // 检查详情缓存
      if (_detailsCache.containsKey(id)) {
        final cacheTime = _detailsCacheTime[id];
        if (cacheTime != null && DateTime.now().difference(cacheTime) < _cacheDuration) {
          ////print('从缓存获取番剧 $id 的详情');
          return _detailsCache[id]!;
        } else {
          // 缓存过期，清除
          _detailsCache.remove(id);
          _detailsCacheTime.remove(id);
        }
      }

      ////print('开始获取番剧 $id 的详情');
      final response = await _makeRequest('$_animeUrl$id');

      if (response.statusCode == 404) {
        throw Exception('番剧不存在');
      }

      if (response.statusCode != 200) {
        throw Exception('获取番剧详情失败: ${response.statusCode}');
      }

      final jsonData = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      
      if (jsonData['infobox'] != null) {
        ////print('\n制作信息:');
        for (var item in jsonData['infobox']) {
          ////print('${item['key']}: ${item['value']}');
        }
      }
      
      ////print('\n完整的番剧详情数据: $jsonData');

      final anime = BangumiAnime.fromJson(jsonData);
      // 保存到详情缓存
      _detailsCache[id] = anime;
      _detailsCacheTime[id] = DateTime.now();
      
      ////print('\n解析后的番剧对象:');
      ////print('- 标题: ${anime.nameCn}');
      ////print('- 播放日期: ${anime.airDate}');
      ////print('- 制作公司: ${anime.studio}');
      return anime;
    } catch (e) {
      ////print('获取番剧详情时出错: $e');
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