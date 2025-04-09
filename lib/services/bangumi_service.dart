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

  final Map<String, BangumiAnime> _cache = {};
  final Map<int, BangumiAnime> _detailsCache = {};
  bool _isInitialized = false;
  List<BangumiAnime>? _preloadedAnimes;
  late http.Client _client;

  BangumiService._() {
    _client = http.Client();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // 在后台预加载数据
    _preloadData();
  }

  Future<http.Response> _makeRequest(String url, {int maxRetries = 3}) async {
    int retryCount = 0;
    while (retryCount < maxRetries) {
      try {
        print('🌐 发起请求(尝试 ${retryCount+1}/$maxRetries): $url');
        
        final client = http.Client();
        final response = await client.get(
          Uri.parse(url),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=utf-8',
            'User-Agent': 'NipaPlay/1.0',
          },
        ).timeout(
          // 随着重试次数增加超时时间
          Duration(seconds: 5 + retryCount * 3),
          onTimeout: () {
            client.close();
            throw TimeoutException('请求超时');
          }
        );
        
        client.close();

        if (response.statusCode == 200) {
          print('✅ 请求成功: $url');
          return response;
        } else {
          print('⚠️ HTTP请求失败: ${response.statusCode}');
          throw Exception('HTTP请求失败: ${response.statusCode}');
        }
      } catch (e) {
        retryCount++;
        print('❌ 请求失败 (尝试 $retryCount/$maxRetries): $e');
        if (retryCount == maxRetries) {
          throw Exception('请求失败，已达到最大重试次数: $e');
        }
        // 使用指数退避策略，等待时间逐渐增加
        final waitSeconds = retryCount * 2;
        print('⏳ 等待 $waitSeconds 秒后重试...');
        await Future.delayed(Duration(seconds: waitSeconds));
      }
    }
    throw Exception('请求失败，未知错误');
  }

  Future<void> _preloadData() async {
    try {
      print('开始预加载番剧数据');
      final animes = await getCalendar();
      _preloadedAnimes = animes;
      print('预加载 ${animes.length} 个番剧的图片');
      
      // 预加载所有图片
      await ImageCacheManager.instance.preloadImages(
        animes.map((anime) => anime.imageUrl).toList(),
      );
    } catch (e) {
      print('预加载数据时出错: $e');
    }
  }

  Future<List<BangumiAnime>> getCalendar({bool forceRefresh = false}) async {
    // 如果有预加载的数据且不强制刷新，直接返回
    if (!forceRefresh && _preloadedAnimes != null) {
      print('使用预加载的数据');
      return _preloadedAnimes!;
    }

    if (!forceRefresh) {
      // 尝试从内存缓存加载
      if (_cache.isNotEmpty) {
        print('从内存缓存加载数据');
        return _cache.values.toList();
      }

      // 尝试从本地存储加载
      final cachedData = await _loadFromCache();
      if (cachedData != null) {
        print('从本地存储加载数据');
        return cachedData;
      }
    }

    print('从 API 获取新数据');
    try {
      final response = await _makeRequest(_baseUrl);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        final List<BangumiAnime> animes = [];

        for (var item in data) {
          if (item['items'] != null) {
            for (var animeData in item['items']) {
              try {
                final anime = BangumiAnime.fromCalendarItem(animeData);
                _cache[anime.id.toString()] = anime;
                animes.add(anime);
              } catch (e) {
                print('跳过无效的番剧数据: $e');
                continue;
              }
            }
          }
        }

        // 保存到本地存储
        await _saveToCache(animes);
        print('成功获取并缓存 ${animes.length} 个番剧');
        return animes;
      } else {
        throw Exception('Failed to load calendar: ${response.statusCode}');
      }
    } catch (e) {
      print('获取日历数据时出错: $e');
      rethrow;
    }
  }

  Future<void> _saveToCache(List<BangumiAnime> animes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'animes': animes.map((a) => a.toJson()).toList(),
      };
      await prefs.setString(_cacheKey, json.encode(data));
      print('数据已保存到本地存储');
    } catch (e) {
      print('保存到本地存储时出错: $e');
    }
  }

  Future<List<BangumiAnime>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedString = prefs.getString(_cacheKey);
      
      if (cachedString != null) {
        final data = json.decode(cachedString);
        final timestamp = data['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // 检查缓存是否过期
        if (now - timestamp <= _cacheDuration.inMilliseconds) {
          final List<dynamic> animesData = data['animes'];
          final animes = animesData
              .map((data) => BangumiAnime.fromJson(data))
              .toList();
          
          // 更新内存缓存
          for (var anime in animes) {
            _cache[anime.id.toString()] = anime;
          }
          
          print('从本地存储加载了 ${animes.length} 个番剧');
          return animes;
        } else {
          print('缓存已过期');
          return null;
        }
      }
      print('没有找到缓存数据');
      return null;
    } catch (e) {
      print('加载缓存数据时出错: $e');
      return null;
    }
  }

  Future<BangumiAnime> getAnimeDetails(int id) async {
    try {
      // 检查详情缓存
      if (_detailsCache.containsKey(id)) {
        print('从缓存获取番剧 $id 的详情');
        return _detailsCache[id]!;
      }

      print('开始获取番剧 $id 的详情');
      final response = await _makeRequest('$_animeUrl$id');

      if (response.statusCode == 404) {
        throw Exception('番剧不存在');
      }

      if (response.statusCode != 200) {
        throw Exception('获取番剧详情失败: ${response.statusCode}');
      }

      final jsonData = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      print('获取到的原始数据:');
      print('- air_date: ${jsonData['air_date']}');
      print('- date: ${jsonData['date']}');
      
      if (jsonData['infobox'] != null) {
        print('\n制作信息:');
        for (var item in jsonData['infobox']) {
          print('${item['key']}: ${item['value']}');
        }
      }
      
      print('\n完整的番剧详情数据: $jsonData');

      final anime = BangumiAnime.fromJson(jsonData);
      // 保存到详情缓存
      _detailsCache[id] = anime;
      
      print('\n解析后的番剧对象:');
      print('- 标题: ${anime.nameCn}');
      print('- 播放日期: ${anime.airDate}');
      print('- 制作公司: ${anime.studio}');
      return anime;
    } catch (e) {
      print('获取番剧详情时出错: $e');
      rethrow;
    }
  }
} 