import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DandanplayService {
  static const String appId = "nipaplayv1";
  static bool _isLoggedIn = false;
  static String? _userName;
  static String? _screenName;
  
  static bool get isLoggedIn => _isLoggedIn;
  static String? get userName => _userName;
  static String? get screenName => _screenName;

  // Web版本API基础URL
  static String _baseUrl = '';
  
  static Future<void> initialize() async {
    // 从localStorage加载登录状态
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('dandanplay_logged_in') ?? false;
    _userName = prefs.getString('dandanplay_username');
    _screenName = prefs.getString('dandanplay_screenname');
    
    // 设置基础URL为当前主机
    final currentUrl = Uri.base.toString();
    final uri = Uri.parse(currentUrl);
    _baseUrl = '${uri.scheme}://${uri.host}';
    
    if (uri.port != 80 && uri.port != 443) {
      _baseUrl += ':${uri.port}';
    }
    
    // 在初始化时获取最新的登录状态
    if (kIsWeb) {
      await _syncLoginStatus();
    }
  }
  
  // 同步登录状态与本地客户端
  static Future<void> _syncLoginStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/dandanplay/login_status'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _updateLoginStatus(
          isLoggedIn: data['isLoggedIn'] == true,
          userName: data['userName'],
          screenName: data['screenName'],
        );
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 同步登录状态失败: $e');
    }
  }
  
  // 更新本地存储的登录状态
  static Future<void> _updateLoginStatus({
    required bool isLoggedIn,
    String? userName,
    String? screenName,
  }) async {
    _isLoggedIn = isLoggedIn;
    _userName = userName;
    _screenName = screenName;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dandanplay_logged_in', isLoggedIn);
    
    if (userName != null) {
      await prefs.setString('dandanplay_username', userName);
    } else {
      await prefs.remove('dandanplay_username');
    }
    
    if (screenName != null) {
      await prefs.setString('dandanplay_screenname', screenName);
    } else {
      await prefs.remove('dandanplay_screenname');
    }
  }

  static Future<void> preloadRecentAnimes() async {
    // Web版本不需要预加载，直接返回
    return;
  }
  
  static Future<void> loadToken() async {
    // Web版本通过API调用直接使用服务端的token
    return;
  }
  
  static Future<void> saveLoginInfo(String token, String username, String screenName) async {
    // 在Web版本中，只更新本地状态，不保存token
    await _updateLoginStatus(
      isLoggedIn: true,
      userName: username,
      screenName: screenName,
    );
  }
  
  static Future<void> clearLoginInfo() async {
    // 调用API登出，然后清除本地状态
    try {
      await http.post(Uri.parse('$_baseUrl/api/dandanplay/logout'));
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 登出失败: $e');
    }
    
    await _updateLoginStatus(isLoggedIn: false);
  }
  
  static Future<void> saveToken(String token) async {
    // Web版本不直接管理token
    return;
  }
  
  static Future<void> clearToken() async {
    // Web版本不直接管理token
    return;
  }
  
  static Future<Map<String, dynamic>?> getCachedVideoInfo(String fileHash) async {
    return null; // Web版本不支持本地缓存
  }
  
  static Future<void> saveVideoInfoToCache(String fileHash, Map<String, dynamic> videoInfo) async {
    // Web版本不支持本地缓存
    return;
  }
  
  static Future<String> getAppSecret() async {
    // Web版本不需要直接访问appSecret
    return '';
  }
  
  static String generateSignature(String appId, int timestamp, String apiPath, String appSecret) {
    // Web版本不需要生成签名
    return '';
  }
  
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/dandanplay/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );
      
      final data = json.decode(response.body);
      
      if (data['success'] == true) {
        await saveLoginInfo(
          '', // Web不需要保存token
          username,
          data['screenName'] ?? username,
        );
      }
      
      return data;
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 登录失败: $e');
      return {'success': false, 'message': '登录失败: ${e.toString()}'};
    }
  }
  
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String email,
    required String screenName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/dandanplay/register'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'username': username,
          'password': password,
          'email': email,
          'screenName': screenName,
        }),
      );
      
      final data = json.decode(response.body);
      
      if (data['success'] == true) {
        // 注册成功后可能需要自动登录
        if (data['token'] != null) {
          await saveLoginInfo('', username, screenName);
          return {'success': true, 'message': '注册成功并已自动登录'};
        } else {
          return {'success': true, 'message': '注册成功，请使用新账号登录'};
        }
      }
      
      return data;
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 注册失败: $e');
      return {'success': false, 'message': '注册失败: ${e.toString()}'};
    }
  }
  
  static Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/danmaku/video_info?videoPath=${Uri.encodeComponent(videoPath)}'),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('获取视频信息失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 获取视频信息失败: $e');
      return {'success': false, 'message': '获取视频信息失败: ${e.toString()}'};
    }
  }
  
  static Future<Map<String, dynamic>> getDanmaku(String episodeId, int animeId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/danmaku/load?episodeId=$episodeId&animeId=$animeId'),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'comments': [], 'count': 0};
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 获取弹幕失败: $e');
      return {'comments': [], 'count': 0};
    }
  }
  
  // 确保getProxiedImageUrl方法可以被公开访问
  static String getProxiedImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return '';
    }
    
    // 如果不是web端，直接返回原URL
    if (!kIsWeb) {
      return imageUrl;
    }
    
    try {
      // 对URL进行Base64编码，以便在查询参数中安全传输
      final encodedUrl = base64Url.encode(utf8.encode(imageUrl));
      return '$_baseUrl/api/image_proxy?url=$encodedUrl';
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 创建代理URL失败: $e');
      return imageUrl; // 出错时返回原始URL
    }
  }
  
  static Future<Map<String, dynamic>> getUserPlayHistory({DateTime? fromDate, DateTime? toDate}) async {
    try {
      String url = '$_baseUrl/api/dandanplay/play_history';
      
      final queryParams = <String, String>{};
      if (fromDate != null) {
        queryParams['fromDate'] = fromDate.toUtc().toIso8601String();
      }
      if (toDate != null) {
        queryParams['toDate'] = toDate.toUtc().toIso8601String();
      }
      
      if (queryParams.isNotEmpty) {
        url += '?${Uri(queryParameters: queryParams).query}';
      }
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 在Web端处理图片URL
        if (kIsWeb && data['playHistoryAnimes'] != null) {
          final animes = data['playHistoryAnimes'] as List;
          for (final anime in animes) {
            if (anime['imageUrl'] != null) {
              anime['imageUrl'] = getProxiedImageUrl(anime['imageUrl'] as String);
            }
          }
        }
        
        return data;
      } else {
        throw Exception('获取播放历史失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 获取播放历史失败: $e');
      return {'success': false, 'playHistoryAnimes': []};
    }
  }
  
  static Future<Map<String, dynamic>> addPlayHistory({
    required List<int> episodeIdList,
    bool addToFavorite = false,
    int rating = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/dandanplay/add_play_history'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'episodeIdList': episodeIdList,
          'addToFavorite': addToFavorite,
          'rating': rating,
        }),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('提交播放历史失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 提交播放历史失败: $e');
      return {'success': false, 'message': '提交播放历史失败: ${e.toString()}'};
    }
  }
  
  static Future<Map<String, dynamic>> getBangumiDetails(int bangumiId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/bangumi/detail/$bangumiId'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 在Web端处理图片URL
        if (kIsWeb && data['bangumi'] != null) {
          final bangumi = data['bangumi'];
          if (bangumi['imageUrl'] != null) {
            bangumi['imageUrl'] = getProxiedImageUrl(bangumi['imageUrl'] as String);
          }
        }
        
        return data;
      } else {
        throw Exception('获取番剧详情失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 获取番剧详情失败: $e');
      return {'success': false, 'message': '获取番剧详情失败: ${e.toString()}'};
    }
  }
  
  static Future<Map<int, bool>> getEpisodesWatchStatus(List<int> episodeIds) async {
    try {
      // 先获取播放历史
      final historyData = await getUserPlayHistory();
      final Map<int, bool> watchStatus = {};
      
      if (historyData['success'] == true && historyData['playHistoryAnimes'] != null) {
        final List<dynamic> animes = historyData['playHistoryAnimes'];
        
        // 遍历所有动画的观看历史
        for (final anime in animes) {
          if (anime['episodes'] != null) {
            final List<dynamic> episodes = anime['episodes'];
            
            // 检查每个剧集的观看状态
            for (final episode in episodes) {
              final episodeId = episode['episodeId'] as int?;
              final lastWatched = episode['lastWatched'] as String?;
              
              if (episodeId != null && episodeIds.contains(episodeId)) {
                // 如果有lastWatched时间，说明已看过
                watchStatus[episodeId] = lastWatched != null && lastWatched.isNotEmpty;
              }
            }
          }
        }
      }
      
      // 确保所有请求的episodeId都有状态
      for (final episodeId in episodeIds) {
        watchStatus.putIfAbsent(episodeId, () => false);
      }
      
      return watchStatus;
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 获取观看状态失败: $e');
      // 出错时返回默认状态（未看）
      final Map<int, bool> defaultStatus = {};
      for (final episodeId in episodeIds) {
        defaultStatus[episodeId] = false;
      }
      return defaultStatus;
    }
  }
  
  static Future<Map<String, dynamic>> getUserFavorites({bool onlyOnAir = false}) async {
    try {
      String url = '$_baseUrl/api/dandanplay/favorites';
      
      if (onlyOnAir) {
        url += '?onlyOnAir=true';
      }
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 在Web端处理图片URL
        if (kIsWeb && data['favorites'] != null) {
          final favorites = data['favorites'] as List;
          for (final fav in favorites) {
            if (fav['imageUrl'] != null) {
              fav['imageUrl'] = getProxiedImageUrl(fav['imageUrl'] as String);
            }
          }
        }
        
        return data;
      } else {
        throw Exception('获取收藏列表失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 获取收藏列表失败: $e');
      return {'success': false, 'favorites': []};
    }
  }
  
  static Future<Map<String, dynamic>> addFavorite({
    required int animeId,
    String? favoriteStatus,
    int rating = 0,
    String? comment,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/dandanplay/add_favorite'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'animeId': animeId,
          'favoriteStatus': favoriteStatus,
          'rating': rating,
          'comment': comment,
        }),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('添加收藏失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 添加收藏失败: $e');
      return {'success': false, 'message': '添加收藏失败: ${e.toString()}'};
    }
  }
  
  static Future<Map<String, dynamic>> removeFavorite(int animeId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/dandanplay/remove_favorite/$animeId'),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('取消收藏失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 取消收藏失败: $e');
      return {'success': false, 'message': '取消收藏失败: ${e.toString()}'};
    }
  }
  
  static Future<bool> isAnimeFavorited(int animeId) async {
    try {
      final favoritesData = await getUserFavorites();
      
      if (favoritesData['success'] == true && favoritesData['favorites'] != null) {
        final List<dynamic> favorites = favoritesData['favorites'];
        
        // 检查列表中是否包含指定的animeId
        for (final favorite in favorites) {
          if (favorite['animeId'] == animeId) {
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 检查收藏状态失败: $e');
      return false;
    }
  }
  
  static Future<int> getUserRatingForAnime(int animeId) async {
    try {
      final bangumiDetails = await getBangumiDetails(animeId);
      
      if (bangumiDetails['success'] == true && bangumiDetails['bangumi'] != null) {
        final bangumi = bangumiDetails['bangumi'];
        return bangumi['userRating'] as int? ?? 0;
      }
      
      return 0;
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 获取用户评分失败: $e');
      return 0;
    }
  }
  
  static Future<Map<String, dynamic>> submitUserRating({
    required int animeId,
    required int rating,
  }) async {
    // 使用addFavorite接口提交评分，但不修改收藏状态
    return await addFavorite(
      animeId: animeId,
      rating: rating,
      // 不传favoriteStatus参数，这样不会影响现有的收藏状态
    );
  }
  
  static Future<Map<String, dynamic>> sendDanmaku({
    required int episodeId,
    required double time,
    required int mode,
    required int color,
    required String comment,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/dandanplay/send_danmaku'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'episodeId': episodeId,
          'time': time,
          'mode': mode,
          'color': color,
          'comment': comment,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('发送弹幕失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 发送弹幕失败: $e');
      return {'success': false, 'message': '发送弹幕失败: ${e.toString()}'};
    }
  }

  // Web版本的账号注销方法（简化实现）
  static Future<Map<String, dynamic>> getWebToken({
    required String business,
  }) async {
    if (!_isLoggedIn) {
      throw Exception('需要登录才能获取WebToken');
    }

    try {
      debugPrint('[弹弹play服务-Web] 获取WebToken: business=$business');

      final response = await http.get(
        Uri.parse('$_baseUrl/api/dandanplay/webtoken?business=$business'),
      );

      debugPrint('[弹弹play服务-Web] 获取WebToken响应: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('[弹弹play服务-Web] WebToken获取成功');
        return data;
      } else {
        throw Exception('获取WebToken失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 获取WebToken时出错: $e');
      rethrow;
    }
  }

  static Future<String> startDeleteAccountProcess() async {
    if (!_isLoggedIn) {
      throw Exception('需要登录才能注销账号');
    }

    try {
      debugPrint('[弹弹play服务-Web] 开始账号注销流程');

      // Web版本直接返回弹弹play官网的注销页面
      // 因为Web版本无法直接使用OAuth WebToken
      final deleteAccountUrl = 'https://www.dandanplay.com/user/profile';

      debugPrint('[弹弹play服务-Web] 账号注销URL: $deleteAccountUrl');

      return deleteAccountUrl;
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 启动账号注销流程时出错: $e');
      rethrow;
    }
  }

  static Future<void> completeAccountDeletion() async {
    debugPrint('[弹弹play服务-Web] 执行账号注销后的清理工作');

    try {
      // 清除本地登录信息
      await clearLoginInfo();

      debugPrint('[弹弹play服务-Web] 账号注销清理完成');
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 账号注销清理时出错: $e');
      // 即使清理出错，也不抛出异常，因为主要的注销操作已经完成
    }
  }
} 