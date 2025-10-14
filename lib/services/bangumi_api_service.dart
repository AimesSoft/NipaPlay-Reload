import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Bangumi API服务
///
/// 提供与Bangumi API的集成功能，包括：
/// - Bearer Token认证管理
/// - 用户收藏状态获取和更新
/// - 剧集收藏状态获取和更新
///
/// 遵循DandanplayService的设计模式，使用静态方法
class BangumiApiService {
  static const String _baseUrl = 'https://api.bgm.tv';
  static const String _userAgent = 'NipaPlay/1.0';
  static const String _tokenKey = 'bangumi_access_token';
  static const String _userInfoKey = 'bangumi_user_info';
  static const String _isLoggedInKey = 'bangumi_logged_in';

  static String? _accessToken;
  static bool _isLoggedIn = false;
  static Map<String, dynamic>? _userInfo;

  /// 初始化服务，加载保存的Token
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_tokenKey);
      _isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;

      final userInfoStr = prefs.getString(_userInfoKey);
      if (userInfoStr != null) {
        try {
          _userInfo = json.decode(userInfoStr);
        } catch (e) {
          debugPrint('[Bangumi API] 解析用户信息失败: $e');
          _userInfo = null;
        }
      }

      if (_accessToken != null && _isLoggedIn) {
        // 验证Token有效性
        final isValid = await _validateToken();
        if (!isValid) {
          debugPrint('[Bangumi API] Token无效，清除登录信息');
          await clearAccessToken();
        } else {
          debugPrint('[Bangumi API] Token验证成功');
        }
      }

      debugPrint('[Bangumi API] 服务初始化完成，登录状态: $_isLoggedIn');
    } catch (e) {
      debugPrint('[Bangumi API] 初始化失败: $e');
    }
  }

  /// 验证Token有效性
  static Future<bool> _validateToken() async {
    if (_accessToken == null) return false;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/v0/me'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        _userInfo = userData;

        // 保存用户信息
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userInfoKey, json.encode(userData));

        debugPrint(
            '[Bangumi API] Token验证成功，用户: ${userData['username'] ?? 'unknown'}');
        return true;
      } else {
        debugPrint('[Bangumi API] Token验证失败: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[Bangumi API] Token验证异常: $e');
      return false;
    }
  }

  /// 保存访问令牌
  static Future<Map<String, dynamic>> saveAccessToken(String token) async {
    try {
      // 验证Token有效性
      final response = await http.get(
        Uri.parse('$_baseUrl/v0/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);

        _accessToken = token;
        _userInfo = userData;
        _isLoggedIn = true;

        // 保存到SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
        await prefs.setString(_userInfoKey, json.encode(userData));
        await prefs.setBool(_isLoggedInKey, true);

        debugPrint(
            '[Bangumi API] Token保存成功，用户: ${userData['username'] ?? 'unknown'}');

        return {
          'success': true,
          'message': '授权成功，已登录Bangumi账户',
          'user': userData,
        };
      } else if (response.statusCode == 401) {
        debugPrint('[Bangumi API] Token无效: ${response.statusCode}');
        return {
          'success': false,
          'message': '访问令牌无效，请检查令牌是否正确',
        };
      } else {
        debugPrint('[Bangumi API] Token验证失败: ${response.statusCode}');
        return {
          'success': false,
          'message': 'Token验证失败，状态码: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('[Bangumi API] 保存Token时发生异常: $e');
      return {
        'success': false,
        'message': '网络错误，请检查网络连接: $e',
      };
    }
  }

  /// 清除访问令牌
  static Future<Map<String, dynamic>> clearAccessToken() async {
    try {
      _accessToken = null;
      _userInfo = null;
      _isLoggedIn = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userInfoKey);
      await prefs.remove(_isLoggedInKey);

      debugPrint('[Bangumi API] Token已清除');

      return {
        'success': true,
        'message': '已清除Bangumi授权信息',
      };
    } catch (e) {
      debugPrint('[Bangumi API] 清除Token时发生异常: $e');
      return {
        'success': false,
        'message': '清除失败: $e',
      };
    }
  }

  /// 检查是否已登录
  static bool get isLoggedIn => _isLoggedIn;

  /// 获取用户信息
  static Map<String, dynamic>? get userInfo => _userInfo;

  /// 获取访问令牌
  static String? get accessToken => _accessToken;

  /// 通用HTTP请求方法
  static Future<Map<String, dynamic>> _makeRequest(
    String method,
    String path, {
    dynamic body,
    Map<String, String>? queryParams,
  }) async {
    if (_accessToken == null) {
      return {
        'success': false,
        'message': '未设置访问令牌，请先授权',
      };
    }

    try {
      Uri uri = Uri.parse('$_baseUrl$path');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }

      final headers = {
        'Authorization': 'Bearer $_accessToken',
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      };

      // Bangumi API 要求 POST/PUT/PATCH 请求必须包含 Content-Type header
      // 使用 utf8.encode 时，必须显式设置 Content-Type
      if (body != null) {
        headers['content-type'] = 'application/json';
      }

      http.Response response;

      // 对于有body的请求，使用 utf8 编码以确保 Content-Type 正确传递
      dynamic requestBody;
      if (body != null) {
        final jsonString = json.encode(body);
        requestBody = utf8.encode(jsonString);
        // debugPrint('[Bangumi API] 请求体 JSON: $jsonString');
      }

      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: requestBody,
          );
          // debugPrint('[Bangumi API] POST 请求头：$headers');
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: headers,
            body: requestBody,
          );
          // debugPrint('[Bangumi API] PUT 请求头：$headers');
          break;
        case 'PATCH':
          response = await http.patch(
            uri,
            headers: headers,
            body: requestBody,
          );
          // debugPrint('[Bangumi API] PATCH 请求头：$headers');
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        default:
          return {
            'success': false,
            'message': '不支持的HTTP方法: $method',
          };
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        dynamic responseData;
        if (response.body.isNotEmpty) {
          try {
            responseData = json.decode(response.body);
          } catch (e) {
            responseData = response.body;
          }
        }

        return {
          'success': true,
          'data': responseData,
          'statusCode': response.statusCode,
        };
      } else if (response.statusCode == 401) {
        debugPrint('[Bangumi API] 认证失败，可能Token已过期');
        await clearAccessToken();
        return {
          'success': false,
          'message': 'Token已过期，请重新授权',
          'statusCode': response.statusCode,
        };
      } else {
        debugPrint(
            '[Bangumi API] 请求失败: ${response.statusCode} - ${response.body}');
        return {
          'success': false,
          'message': 'API请求失败，状态码: ${response.statusCode}',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      debugPrint('[Bangumi API] 请求异常: $e');
      return {
        'success': false,
        'message': '网络错误: $e',
      };
    }
  }

  /// 获取用户收藏状态
  ///
  /// [subjectId] 条目ID
  /// [username] 用户名（如果为null则使用当前登录用户）
  /// 返回收藏信息或错误
  static Future<Map<String, dynamic>> getUserCollection(int subjectId,
      {String? username}) async {
    debugPrint(
        '[Bangumi API] 获取收藏状态: subjectId=$subjectId, username=$username');

    // 如果没有提供username且已登录，使用当前用户的username
    String actualUsername = '-';
    if (username != null && username.isNotEmpty) {
      actualUsername = username;
    } else if (_userInfo != null && _userInfo!['username'] != null) {
      actualUsername = _userInfo!['username'];
    }
    // UNDONE: 如果username不可用，使用uid查询

    debugPrint('[Bangumi API] 实际使用的用户名: $actualUsername');

    final result = await _makeRequest(
        'GET', '/v0/users/$actualUsername/collections/$subjectId');

    if (result['success']) {
      debugPrint('[Bangumi API] 收藏状态获取成功');
      return result;
    } else {
      // 404表示未收藏，这是正常情况
      if (result['statusCode'] == 404) {
        return {
          'success': true,
          'data': null, // 表示未收藏
          'message': '该条目未收藏',
        };
      }
      return result;
    }
  }

  /// 添加用户收藏（仅当未收藏时）
  ///
  /// [subjectId] 条目ID
  /// [type] 收藏类型: 1=Wish, 2=Done, 3=Doing, 4=OnHold, 5=Dropped
  /// [comment] 评论（可选）
  /// [rate] 评分 1-10（可选）
  /// [private] 是否私密收藏（可选）
  static Future<Map<String, dynamic>> addUserCollection(
    int subjectId,
    int type, {
    String? comment,
    int? rate,
    bool? private,
  }) async {
    debugPrint('[Bangumi API] 添加收藏: subjectId=$subjectId, type=$type');

    final body = <String, dynamic>{
      'type': type,
    };

    if (comment != null) body['comment'] = comment;
    if (rate != null && rate >= 1 && rate <= 10) body['rate'] = rate;
    if (private != null) body['private'] = private;

    final result = await _makeRequest(
        'POST', '/v0/users/-/collections/$subjectId',
        body: body);

    if (result['success']) {
      debugPrint('[Bangumi API] 收藏添加成功');
    } else {
      debugPrint('[Bangumi API] 收藏添加失败: ${result['message']}');
    }

    return result;
  }

  /// 更新用户收藏状态
  ///
  /// [subjectId] 条目ID
  /// [type] 收藏类型: 1=Wish, 2=Done, 3=Doing, 4=OnHold, 5=Dropped
  /// [comment] 评论（可选）
  /// [rate] 评分 1-10（可选）
  /// [private] 是否私密收藏（可选）
  static Future<Map<String, dynamic>> updateUserCollection(
    int subjectId, {
    int? type,
    String? comment,
    int? rate,
    bool? private,
  }) async {
    debugPrint('[Bangumi API] 更新收藏状态: subjectId=$subjectId, type=$type');

    final body = <String, dynamic>{};

    if (type != null && type >= 1 && type <= 5) body['type'] = type;
    if (comment != null) body['comment'] = comment;
    if (rate != null && rate >= 1 && rate <= 10) body['rate'] = rate;
    if (private != null) body['private'] = private;

    final result = await _makeRequest(
        'POST', '/v0/users/-/collections/$subjectId',
        body: body);

    if (result['success']) {
      debugPrint('[Bangumi API] 收藏状态更新成功');
    } else {
      debugPrint('[Bangumi API] 收藏状态更新失败: ${result['message']}');
    }

    return result;
  }

  /// 获取用户剧集收藏状态
  ///
  /// [subjectId] 条目ID
  /// 返回该条目下所有剧集的收藏状态
  static Future<Map<String, dynamic>> getUserEpisodeCollections(
      int subjectId) async {
    debugPrint('[Bangumi API] 获取剧集收藏状态: $subjectId');

    final result = await _makeRequest(
        'GET', '/v0/users/-/collections/$subjectId/episodes');

    if (result['success']) {
      debugPrint('[Bangumi API] 剧集收藏状态获取成功');
    }

    return result;
  }

  /// 更新剧集收藏状态
  ///
  /// [episodeId] 剧集ID
  /// [type] 收藏类型: 0=Uncollected, 1=Wish, 2=Done, 3=Dropped
  static Future<Map<String, dynamic>> updateEpisodeCollection(
    int episodeId,
    int type,
  ) async {
    debugPrint('[Bangumi API] 更新剧集收藏状态: $episodeId, type=$type');

    final body = <String, dynamic>{
      'type': type,
    };

    final result = await _makeRequest(
        'PUT', '/v0/users/-/collections/-/episodes/$episodeId',
        body: body);

    if (result['success']) {
      debugPrint('[Bangumi API] 剧集收藏状态更新成功');
    } else {
      debugPrint('[Bangumi API] 剧集收藏状态更新失败: ${result['message']}');
    }

    return result;
  }

  /// 批量更新剧集收藏状态
  ///
  /// [subjectId] 条目ID
  /// [episodes] 剧集收藏状态列表，格式：[{"id": episodeId, "type": type}]
  static Future<Map<String, dynamic>> batchUpdateEpisodeCollections(
    int subjectId,
    List<Map<String, dynamic>> episodes,
  ) async {
    debugPrint('[Bangumi API] 批量更新剧集收藏状态: $subjectId, ${episodes.length}个剧集');

    // 根据Bangumi API文档，请求体格式为：
    // {"episode_id": [id1, id2, ...], "type": 收藏类型}
    // 我们按type分组，分别发送请求

    final Map<int, List<int>> typeGroups = {};
    for (final episode in episodes) {
      final int type = episode['type'] as int;
      final int id = episode['id'] as int;

      if (!typeGroups.containsKey(type)) {
        typeGroups[type] = [];
      }
      typeGroups[type]!.add(id);
    }

    // 发送每个type组的请求
    bool allSuccess = true;
    String lastError = '';

    for (final entry in typeGroups.entries) {
      final int type = entry.key;
      final List<int> episodeIds = entry.value;

      // 跳过未收藏状态(type=0)，因为不需要发送请求
      if (type == 0) continue;

      final body = {
        'episode_id': episodeIds,
        'type': type,
      };

      final result = await _makeRequest(
          'PATCH', '/v0/users/-/collections/$subjectId/episodes',
          body: body);

      if (!result['success']) {
        allSuccess = false;
        lastError = result['message'] ?? '未知错误';
        debugPrint('[Bangumi API] 批量更新剧集收藏状态失败 (type=$type): ${result['message']}');
      } else {
        debugPrint('[Bangumi API] 批量更新剧集收藏状态成功 (type=$type, ${episodeIds.length}个剧集)');
      }
    }

    if (allSuccess) {
      debugPrint('[Bangumi API] 剧集收藏状态批量更新成功');
      return {'success': true};
    } else {
      debugPrint('[Bangumi API] 剧集收藏状态批量更新失败: $lastError');
      return {'success': false, 'message': lastError};
    }
  }

  /// 获取条目信息
  ///
  /// [subjectId] 条目ID
  /// 返回条目详细信息
  static Future<Map<String, dynamic>> getSubject(int subjectId) async {
    debugPrint('[Bangumi API] 获取条目信息: $subjectId');

    final result = await _makeRequest('GET', '/v0/subjects/$subjectId');

    if (result['success']) {
      debugPrint('[Bangumi API] 条目信息获取成功');
    }

    return result;
  }

  /// 获取条目的剧集列表
  ///
  /// [subjectId] 条目ID
  /// [type] 剧集类型过滤（可选）
  /// [limit] 限制数量（可选）
  /// [offset] 偏移量（可选）
  static Future<Map<String, dynamic>> getSubjectEpisodes(
    int subjectId, {
    int? type,
    int? limit,
    int? offset,
  }) async {
    debugPrint('[Bangumi API] 获取条目剧集列表: $subjectId');

    final queryParams = <String, String>{
      'subject_id': subjectId.toString(),
    };

    if (type != null) queryParams['type'] = type.toString();
    if (limit != null) queryParams['limit'] = limit.toString();
    if (offset != null) queryParams['offset'] = offset.toString();

    final result =
        await _makeRequest('GET', '/v0/episodes', queryParams: queryParams);

    if (result['success']) {
      debugPrint('[Bangumi API] 条目剧集列表获取成功');
    }

    return result;
  }

  /// 测试API连接
  ///
  /// 公共方法，用于测试当前Token是否有效
  static Future<Map<String, dynamic>> testConnection() async {
    return await _makeRequest('GET', '/v0/me');
  }

  /// 搜索条目
  ///
  /// [keyword] 搜索关键词
  /// [type] 条目类型过滤（可选）
  /// [tag] 标签过滤（可选）
  /// [sort] 排序方式（可选）
  /// [limit] 限制数量（可选）
  /// [offset] 偏移量（可选）
  static Future<Map<String, dynamic>> searchSubjects(
    String keyword, {
    int? type,
    List<String>? tag,
    String? sort,
    int? limit,
    int? offset,
  }) async {
    debugPrint('[Bangumi API] 搜索条目: $keyword');

    final body = <String, dynamic>{
      'keyword': keyword,
    };

    if (type != null) {
      body['filter'] = {
        'type': [type]
      };
    }
    if (tag != null && tag.isNotEmpty) {
      body['filter'] = (body['filter'] as Map<String, dynamic>?) ?? {};
      body['filter']['tag'] = tag;
    }
    if (sort != null) body['sort'] = sort;
    if (limit != null) body['limit'] = limit;
    if (offset != null) body['offset'] = offset;

    final result =
        await _makeRequest('POST', '/v0/search/subjects', body: body);

    if (result['success']) {
      debugPrint('[Bangumi API] 条目搜索成功');
    }

    return result;
  }
}
