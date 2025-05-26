import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/search_model.dart';
import './dandanplay_service.dart';

class SearchService {
  static final SearchService instance = SearchService._();
  static const String _baseUrl = 'https://api.dandanplay.net/api/v2';
  static const String _configCacheKey = 'search_config_cache';
  static const Duration _configCacheDuration = Duration(days: 1);

  SearchConfig? _cachedConfig;
  DateTime? _configCacheTime;

  SearchService._();

  /// 获取搜索配置（用于高级搜索）
  Future<SearchConfig> getSearchConfig({String source = 'anidb'}) async {
    // 检查内存缓存
    if (_cachedConfig != null && 
        _configCacheTime != null && 
        DateTime.now().difference(_configCacheTime!) < _configCacheDuration) {
      return _cachedConfig!;
    }

    // 检查本地缓存
    final prefs = await SharedPreferences.getInstance();
    final cachedString = prefs.getString(_configCacheKey);
    if (cachedString != null) {
      try {
        final data = json.decode(cachedString);
        final timestamp = data['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        
        if (now - timestamp <= _configCacheDuration.inMilliseconds) {
          _cachedConfig = SearchConfig.fromJson(data['config']);
          _configCacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          debugPrint('[搜索服务] 从本地缓存加载搜索配置');
          return _cachedConfig!;
        }
      } catch (e) {
        debugPrint('[搜索服务] 解析缓存的搜索配置失败: $e');
      }
    }

    // 从网络获取
    try {
      final url = '$_baseUrl/search/adv/config?source=$source';
      final response = await _makeAuthenticatedRequest(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _cachedConfig = SearchConfig.fromJson(data);
          _configCacheTime = DateTime.now();

          // 保存到本地缓存
          final cacheData = {
            'timestamp': _configCacheTime!.millisecondsSinceEpoch,
            'config': data,
          };
          await prefs.setString(_configCacheKey, json.encode(cacheData));
          
          debugPrint('[搜索服务] 成功获取搜索配置，标签数量: ${_cachedConfig!.tags.length}');
          return _cachedConfig!;
        } else {
          throw Exception('API返回错误: ${data['errorMessage']}');
        }
      } else {
        throw Exception('HTTP错误: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[搜索服务] 获取搜索配置失败: $e');
      rethrow;
    }
  }

  /// 根据文本标签搜索动画
  Future<SearchResult> searchAnimeByTags(List<String> tags) async {
    if (tags.isEmpty) {
      throw ArgumentError('标签列表不能为空');
    }

    if (tags.length > 10) {
      throw ArgumentError('标签数量不能超过10个');
    }

    for (String tag in tags) {
      if (tag.length > 50) {
        throw ArgumentError('单个标签长度不能超过50个字符');
      }
    }

    try {
      final tagsString = tags.join(',');
      final url = '$_baseUrl/search/tag?tags=${Uri.encodeComponent(tagsString)}';
      final response = await _makeAuthenticatedRequest(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final result = SearchResult.fromTagSearchJson(data);
          debugPrint('[搜索服务] 文本标签搜索成功，找到 ${result.animes.length} 个结果');
          return result;
        } else {
          throw Exception('API返回错误: ${data['errorMessage']}');
        }
      } else {
        throw Exception('HTTP错误: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[搜索服务] 文本标签搜索失败: $e');
      rethrow;
    }
  }

  /// 高级搜索（使用标签ID）
  Future<SearchResult> searchAnimeAdvanced({
    String source = 'anidb',
    String? keyword,
    int? type,
    List<int>? tagIds,
    int? year,
    int? month,
    int minRate = 0,
    int maxRate = 10,
    bool? restricted,
    int sort = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'source': source,
        'minRate': minRate.toString(),
        'maxRate': maxRate.toString(),
        'sort': sort.toString(),
      };

      if (keyword != null && keyword.isNotEmpty) {
        queryParams['keyword'] = keyword;
      }

      if (type != null) {
        queryParams['type'] = type.toString();
      }

      if (tagIds != null && tagIds.isNotEmpty) {
        queryParams['tags'] = tagIds.join(',');
      }

      if (year != null) {
        queryParams['year'] = year.toString();
      }

      if (month != null) {
        queryParams['month'] = month.toString();
      }

      if (restricted != null) {
        queryParams['restricted'] = restricted.toString();
      }

      final uri = Uri.parse('$_baseUrl/search/adv').replace(queryParameters: queryParams);
      final response = await _makeAuthenticatedRequest(uri.toString());
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final result = SearchResult.fromAdvancedSearchJson(data);
          debugPrint('[搜索服务] 高级搜索成功，找到 ${result.animes.length} 个结果');
          return result;
        } else {
          throw Exception('API返回错误: ${data['errorMessage']}');
        }
      } else {
        throw Exception('HTTP错误: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[搜索服务] 高级搜索失败: $e');
      rethrow;
    }
  }

  /// 发送经过认证的HTTP请求（使用DanDanPlay标准认证）
  Future<http.Response> _makeAuthenticatedRequest(String url) async {
    try {
      const String appId = DandanplayService.appId;
      final String appSecret = await DandanplayService.getAppSecret();
      final int timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      
      final Uri parsedUri = Uri.parse(url);
      final String apiPath = parsedUri.path;
      final String signature = DandanplayService.generateSignature(appId, timestamp, apiPath, appSecret);

      final headers = {
        'Accept': 'application/json',
        'User-Agent': 'NipaPlay/1.0',
        'X-AppId': appId,
        'X-Signature': signature,
        'X-Timestamp': timestamp.toString(),
      };

      // 如果已登录，添加Authorization头
      if (DandanplayService.isLoggedIn) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('dandanplay_token');
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      }

      debugPrint('[搜索服务] 请求URL: $url');
      debugPrint('[搜索服务] API路径: $apiPath');
      //debugPrint('[搜索服务] 请求头: $headers');

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('请求超时');
        },
      );

      debugPrint('[搜索服务] 响应状态码: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[搜索服务] 响应内容: ${response.body}');
      }

      return response;
    } catch (e) {
      debugPrint('[搜索服务] HTTP请求失败: $e');
      rethrow;
    }
  }

  /// 清除缓存
  Future<void> clearCache() async {
    _cachedConfig = null;
    _configCacheTime = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configCacheKey);
    debugPrint('[搜索服务] 缓存已清除');
  }
} 