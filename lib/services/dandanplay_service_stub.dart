import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/utils/media_filename_parser.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

class DandanplayService {
  static const String appId = "nipaplayv1";
  static const String userAgent = "NipaPlay/1.0";
  static const List<String> _servers = [
    'https://nipaplay.aimes-soft.com',
    'https://kurisu.aimes-soft.com'
  ];
  static const String _videoCacheKey = 'video_recognition_cache';
  static bool _isLoggedIn = false;
  static String? _userName;
  static String? _screenName;
  static String? _token;
  static String? _appSecret;
  
  static bool get isLoggedIn => _isLoggedIn;
  static String? get userName => _userName;
  static String? get screenName => _screenName;

  // Web版本API基础URL
  static String _baseUrl = '';
  static String? _webApiBaseUrl;
  static bool _webApiProbeCompleted = false;
  static String? _lastWebApiCandidate;
  static bool _useWebApiProxy = false;

  static Future<bool> _probeWebApiBaseUrl(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/info'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data is Map<String, dynamic> && data['app'] == 'NipaPlay';
      }
    } catch (_) {
      // 忽略探测错误，回退到直连弹弹play
    }
    return false;
  }

  static Future<void> _ensureApiBaseUrl() async {
    final explicitOverride =
        WebRemoteAccessService.resolveBaseUrlFromQuery();
    String? candidate = explicitOverride;
    if (candidate == null) {
      await WebRemoteAccessService.ensureInitialized();
      candidate = WebRemoteAccessService.cachedBaseUrl ??
          WebRemoteAccessService.resolveBaseUrlFromOrigin();
    }
    if (_webApiProbeCompleted && candidate == _lastWebApiCandidate) {
      return;
    }
    _webApiProbeCompleted = true;
    _lastWebApiCandidate = candidate;
    _useWebApiProxy = false;
    _webApiBaseUrl = null;

    if (candidate != null && candidate.isNotEmpty) {
      if (await _probeWebApiBaseUrl(candidate)) {
        _webApiBaseUrl = candidate;
        _useWebApiProxy = true;
      } else {
        // 仅当显式传入地址时才作为直连弹弹play地址使用
        if (explicitOverride != null) {
          _baseUrl = candidate;
        }
      }
    }

    if (_baseUrl.isEmpty || explicitOverride == null) {
      _baseUrl = await NetworkSettings.getDandanplayServer();
    }
  }

  static Future<String?> _getWebApiBaseUrl() async {
    await _ensureApiBaseUrl();
    if (_useWebApiProxy && _webApiBaseUrl != null && _webApiBaseUrl!.isNotEmpty) {
      return _webApiBaseUrl;
    }
    return null;
  }
  
  static Future<void> initialize() async {
    // 从localStorage加载登录状态
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('dandanplay_logged_in') ?? false;
    _userName = prefs.getString('dandanplay_username');
    _screenName = prefs.getString('dandanplay_screenname');

    await loadToken();
    await _ensureApiBaseUrl();

    // 在初始化时获取最新的登录状态（仅当存在Web API代理时）
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (kIsWeb && webApiBaseUrl != null) {
      await _syncLoginStatus(webApiBaseUrl);
    } else if (_token != null && _token!.isNotEmpty) {
      _isLoggedIn = true;
    }
  }

  static Future<void> refreshWebApiBaseUrl({bool syncLogin = true}) async {
    _webApiProbeCompleted = false;
    await _ensureApiBaseUrl();
    if (syncLogin) {
      final webApiBaseUrl = await _getWebApiBaseUrl();
      if (kIsWeb && webApiBaseUrl != null) {
        await _syncLoginStatus(webApiBaseUrl);
      }
    }
  }
  
  // 同步登录状态与本地客户端
  static Future<void> _syncLoginStatus(String webApiBaseUrl) async {
    try {
      final response = await http.get(
        Uri.parse('$webApiBaseUrl/api/dandanplay/login_status'),
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

  /// 获取当前弹弹play API基础URL（Web 版默认同源 `/api/`）
  static Future<String> getApiBaseUrl() async {
    await _ensureApiBaseUrl();
    return _baseUrl;
  }
  
  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('dandanplay_token');
    if (_token != null && _token!.isNotEmpty) {
      _isLoggedIn = true;
    }
  }
  
  static Future<void> saveLoginInfo(String token, String username, String screenName) async {
    _token = token;
    await _updateLoginStatus(
      isLoggedIn: true,
      userName: username,
      screenName: screenName,
    );
    await saveToken(token);
  }
  
  static Future<void> clearLoginInfo() async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      // 调用API登出，然后清除本地状态
      try {
        await http.post(Uri.parse('$webApiBaseUrl/api/dandanplay/logout'));
      } catch (e) {
        debugPrint('[弹弹play服务-Web] 登出失败: $e');
      }
    }

    await clearToken();
    await _updateLoginStatus(isLoggedIn: false);
  }
  
  static Future<void> saveToken(String token) async {
    if (token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dandanplay_token', token);
  }
  
  static Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dandanplay_token');
  }
  
  static Future<Map<String, dynamic>?> getCachedVideoInfo(String fileHash) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = prefs.getString(_videoCacheKey);
      if (cache == null) return null;
      final Map<String, dynamic> cacheMap = json.decode(cache);
      if (!cacheMap.containsKey(fileHash)) return null;
      final videoInfo = cacheMap[fileHash];
      if (videoInfo is Map<String, dynamic>) {
        return Map<String, dynamic>.from(videoInfo);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
  
  static Future<void> saveVideoInfoToCache(String fileHash, Map<String, dynamic> videoInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = prefs.getString(_videoCacheKey);
      Map<String, dynamic> cacheMap = {};
      if (cache != null) {
        cacheMap = Map<String, dynamic>.from(json.decode(cache));
      }
      cacheMap[fileHash] = videoInfo;
      await prefs.setString(_videoCacheKey, json.encode(cacheMap));
    } catch (_) {
    }
  }
  
  static Future<String> getAppSecret() async {
    if (_appSecret != null) {
      return _appSecret!;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedAppSecret = prefs.getString('dandanplay_app_secret');
    if (savedAppSecret != null) {
      _appSecret = savedAppSecret;
      return _appSecret!;
    }

    Exception? lastException;
    for (final server in _servers) {
      try {
        final response = await http.get(
          Uri.parse('$server/nipaplay.php'),
          headers: {
            'User-Agent': userAgent,
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['encryptedAppSecret'] != null) {
            _appSecret = _b(data['encryptedAppSecret']);
            await prefs.setString('dandanplay_app_secret', _appSecret!);
            return _appSecret!;
          }
          throw Exception('从 $server 获取appSecret失败：响应中没有encryptedAppSecret');
        }
        throw Exception('从 $server 获取appSecret失败：HTTP ${response.statusCode}');
      } on TimeoutException {
        lastException = TimeoutException('从 $server 获取appSecret超时');
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
      }
    }

    throw lastException ?? Exception('获取应用密钥失败，请检查网络连接');
  }
  
  static String generateSignature(String appId, int timestamp, String apiPath, String appSecret) {
    final signatureString = '$appId$timestamp$apiPath$appSecret';
    final hash = sha256.convert(utf8.encode(signatureString));
    return base64.encode(hash.bytes);
  }
  
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.post(
          Uri.parse('$webApiBaseUrl/api/dandanplay/login'),
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
            '',
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

    try {
      final appSecret = await getAppSecret();
      final now = DateTime.now();
      final utcNow = now.toUtc();
      final timestamp = (utcNow.millisecondsSinceEpoch / 1000).round();
      final hashString = '$appId$password$timestamp$username$appSecret';
      final hash = md5.convert(utf8.encode(hashString)).toString();

      final response = await http.post(
        Uri.parse('${await getApiBaseUrl()}/api/v2/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature':
              generateSignature(appId, timestamp, '/api/v2/login', appSecret),
          'X-Timestamp': '$timestamp',
        },
        body: json.encode({
          'userName': username,
          'password': password,
          'appId': appId,
          'unixTimestamp': timestamp,
          'hash': hash,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['token'] != null) {
          final screenName = data['user']?['screenName'] ?? username;
          await saveLoginInfo(data['token'], username, screenName);
          return {'success': true, 'message': '登录成功'};
        } else {
          return {
            'success': false,
            'message': data['errorMessage'] ?? '登录失败，请检查用户名和密码'
          };
        }
      } else {
        final errorMessage =
            response.headers['x-error-message'] ?? response.body;
        return {
          'success': false,
          'message': '网络请求失败 (${response.statusCode}): $errorMessage'
        };
      }
    } catch (e) {
      return {'success': false, 'message': '登录失败: ${e.toString()}'};
    }
  }
  
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String email,
    required String screenName,
  }) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.post(
          Uri.parse('$webApiBaseUrl/api/dandanplay/register'),
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

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/register';
      final signature = generateSignature(appId, timestamp, apiPath, appSecret);

      final requestBody = {
        'userName': username,
        'password': password,
        'email': email,
        'screenName': screenName,
      };

      final response = await http.post(
        Uri.parse('${await getApiBaseUrl()}$apiPath'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': signature,
          'X-Timestamp': '$timestamp',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          if (data['token'] != null) {
            await saveLoginInfo(data['token'], username, screenName);
            return {'success': true, 'message': '注册成功并已自动登录'};
          }
          return {'success': true, 'message': '注册成功，请使用新账号登录'};
        }
        return {
          'success': false,
          'message': data['errorMessage'] ?? '注册失败，请检查提交信息'
        };
      }

      final errorMessage =
          response.headers['x-error-message'] ?? response.body;
      return {
        'success': false,
        'message': '网络请求失败 (${response.statusCode}): $errorMessage'
      };
    } catch (e) {
      debugPrint('[弹弹play服务] 注册失败: $e');
      return {'success': false, 'message': '注册失败: ${e.toString()}'};
    }
  }

  static Future<void> updateEpisodeWatchStatus(int episodeId, bool isWatched) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.post(
          Uri.parse('$webApiBaseUrl/api/dandanplay/episodes/watch_status'),
          headers: const {
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'episodeId': episodeId,
            'isWatched': isWatched,
          }),
        );

        if (response.statusCode != 200) {
          debugPrint('[弹弹play服务-Web] 更新观看状态失败: HTTP ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('[弹弹play服务-Web] 更新观看状态异常: $e');
      }
      return;
    }

    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能更新观看状态');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/playhistory';

      final response = await http.post(
        Uri.parse('${await getApiBaseUrl()}$apiPath'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature':
              generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'episodeIdList': [
            episodeId,
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] != true) {
          throw Exception(data['errorMessage'] ?? '更新观看状态失败');
        }
      } else {
        final errorMessage =
            response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('更新观看状态失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 更新观看状态时出错: $e');
      rethrow;
    }
  }
  
  static Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.get(
          Uri.parse('$webApiBaseUrl/api/danmaku/video_info?videoPath=${Uri.encodeComponent(videoPath)}'),
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

    try {
      final bool isRemotePath =
          videoPath.startsWith('http://') || videoPath.startsWith('https://');

      final fileName = isRemotePath
          ? (Uri.tryParse(videoPath)?.pathSegments.last ?? videoPath)
          : videoPath;
      final filePickerService = FilePickerService();
      final fileHash = filePickerService.getWebFileHash(videoPath) ?? '';
      final fileSize = filePickerService.getWebFileSize(videoPath) ?? 0;

      if (fileHash.isNotEmpty && fileSize > 0) {
        return _getVideoInfoWithMetadata(
          fileName: fileName,
          fileHash: fileHash,
          fileSize: fileSize,
        );
      }

      final fallback = await _tryMatchByFileNameFirstResult(
        fileName: fileName,
        fileHash: fileHash,
        fileSize: fileSize,
      );
      if (fallback != null) {
        return fallback;
      }

      return {
        'isMatched': false,
        'fileName': fileName,
        'fileHash': fileHash,
        'fileSize': fileSize,
        'matches': [],
      };
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 获取视频信息失败: $e');
      return {'success': false, 'message': '获取视频信息失败: ${e.toString()}'};
    }
  }
  
  static Future<Map<String, dynamic>> getDanmaku(String episodeId, int animeId) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.get(
          Uri.parse('$webApiBaseUrl/api/danmaku/load?episodeId=$episodeId&animeId=$animeId'),
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

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/comment/$episodeId';
      final chConvert = await _getDanmakuChConvertFlag();
      final apiUrl =
          '${await getApiBaseUrl()}$apiPath?withRelated=true&chConvert=$chConvert';

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        return _parseDanmakuBody(response.body, episodeId, animeId);
      }
      return {'comments': [], 'count': 0};
    } catch (e) {
      debugPrint('[弹弹play服务] 获取弹幕失败: $e');
      return {'comments': [], 'count': 0};
    }
  }
  
  // 确保getProxiedImageUrl方法可以被公开访问
  static String getProxiedImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return '';
    }
    
    // 如果不是web端或没有本地Web API代理，直接返回原URL
    if (!kIsWeb || !_useWebApiProxy || _webApiBaseUrl == null) {
      return imageUrl;
    }
    
    try {
      // 对URL进行Base64编码，以便在查询参数中安全传输
      final encodedUrl = base64Url.encode(utf8.encode(imageUrl));
      return '$_webApiBaseUrl/api/image_proxy?url=$encodedUrl';
    } catch (e) {
      debugPrint('[弹弹play服务-Web] 创建代理URL失败: $e');
      return imageUrl; // 出错时返回原始URL
    }
  }
  
  static Future<Map<String, dynamic>> getUserPlayHistory({DateTime? fromDate, DateTime? toDate}) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        String url = '$webApiBaseUrl/api/dandanplay/play_history';

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

    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能获取播放历史');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/playhistory';

      final queryParams = <String, String>{};
      if (fromDate != null) {
        queryParams['fromDate'] = fromDate.toUtc().toIso8601String();
      }
      if (toDate != null) {
        queryParams['toDate'] = toDate.toUtc().toIso8601String();
      }

      final baseUrl = await getApiBaseUrl();
      final uri = Uri.parse(
          '$baseUrl$apiPath${queryParams.isNotEmpty ? '?' + Uri(queryParameters: queryParams).query : ''}');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature':
              generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('获取播放历史超时'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '获取播放历史失败');
        }
      } else {
        final errorMessage =
            response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('获取播放历史失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 获取播放历史时出错: $e');
      rethrow;
    }
  }
  
  static Future<Map<String, dynamic>> addPlayHistory({
    required List<int> episodeIdList,
    bool addToFavorite = false,
    int rating = 0,
  }) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.post(
          Uri.parse('$webApiBaseUrl/api/dandanplay/add_play_history'),
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

    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能提交播放历史');
    }

    if (episodeIdList.isEmpty) {
      throw Exception('集数ID列表不能为空');
    }

    if (episodeIdList.length > 100) {
      throw Exception('单次最多只能提交100条播放历史');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/playhistory';

      final requestBody = {
        'episodeIdList': episodeIdList,
        'addToFavorite': addToFavorite,
        'rating': rating,
      };

      final response = await http.post(
        Uri.parse('${await getApiBaseUrl()}$apiPath'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature':
              generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '提交播放历史失败');
        }
      } else {
        final errorMessage =
            response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('提交播放历史失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 提交播放历史时出错: $e');
      rethrow;
    }
  }
  
  static Future<Map<String, dynamic>> getBangumiDetails(int bangumiId) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.get(
          Uri.parse('$webApiBaseUrl/api/bangumi/detail/$bangumiId'),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

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

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/bangumi/$bangumiId';

      final headers = {
        'Accept': 'application/json',
        'User-Agent': userAgent,
        'X-AppId': appId,
        'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
        'X-Timestamp': '$timestamp',
      };

      if (_isLoggedIn && _token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await http.get(
        Uri.parse('${await getApiBaseUrl()}$apiPath'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      final errorMessage =
          response.headers['x-error-message'] ?? '请检查网络连接';
      throw Exception('获取番剧详情失败: $errorMessage');
    } catch (e) {
      debugPrint('[弹弹play服务] 获取番剧详情时出错: $e');
      rethrow;
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
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        String url = '$webApiBaseUrl/api/dandanplay/favorites';

        if (onlyOnAir) {
          url += '?onlyOnAir=true';
        }

        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

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

    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能获取收藏列表');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/favorite';

      final queryParams = <String, String>{};
      if (onlyOnAir) {
        queryParams['onlyOnAir'] = 'true';
      }

      final baseUrl = await getApiBaseUrl();
      final uri = Uri.parse(
          '$baseUrl$apiPath${queryParams.isNotEmpty ? '?' + Uri(queryParameters: queryParams).query : ''}');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature':
              generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('获取收藏列表超时'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '获取收藏列表失败');
        }
      } else {
        final errorMessage =
            response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('获取收藏列表失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 获取收藏列表时出错: $e');
      rethrow;
    }
  }
  
  static Future<Map<String, dynamic>> addFavorite({
    required int animeId,
    String? favoriteStatus,
    int rating = 0,
    String? comment,
  }) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.post(
          Uri.parse('$webApiBaseUrl/api/dandanplay/add_favorite'),
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

    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能添加收藏');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/favorite';

      final requestBody = {
        'animeId': animeId,
        if (favoriteStatus != null) 'favoriteStatus': favoriteStatus,
        'rating': rating,
        if (comment != null) 'comment': comment,
      };

      final response = await http.post(
        Uri.parse('${await getApiBaseUrl()}$apiPath'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature':
              generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '添加收藏失败');
        }
      } else {
        final errorMessage =
            response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('添加收藏失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 添加收藏时出错: $e');
      rethrow;
    }
  }
  
  static Future<Map<String, dynamic>> removeFavorite(int animeId) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.delete(
          Uri.parse('$webApiBaseUrl/api/dandanplay/remove_favorite/$animeId'),
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

    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能取消收藏');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/favorite/$animeId';

      final response = await http.delete(
        Uri.parse('${await getApiBaseUrl()}$apiPath'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature':
              generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '取消收藏失败');
        }
      } else {
        final errorMessage =
            response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('取消收藏失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 取消收藏时出错: $e');
      rethrow;
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
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      try {
        final response = await http.post(
          Uri.parse('$webApiBaseUrl/api/dandanplay/send_danmaku'),
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

    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能发送弹幕');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/comment/$episodeId';

      final requestBody = {
        'time': time,
        'mode': mode,
        'color': color,
        'comment': comment,
      };

      final response = await http.post(
        Uri.parse('${await getApiBaseUrl()}$apiPath'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature':
              generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final r = (color >> 16) & 0xFF;
          final g = (color >> 8) & 0xFF;
          final b = color & 0xFF;
          final colorValue = 'rgb($r,$g,$b)';

          final formattedDanmaku = {
            'time': time,
            'content': comment,
            'type': mode == 1
                ? 'scroll'
                : mode == 5
                    ? 'top'
                    : 'bottom',
            'color': colorValue,
            'isMe': true,
          };

          return {'success': true, 'danmaku': formattedDanmaku};
        }
        throw Exception(data['errorMessage'] ?? '发送弹幕失败');
      } else {
        final errorMessage =
            response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('发送弹幕失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 发送弹幕时出错: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> _getVideoInfoWithMetadata({
    required String fileName,
    required String fileHash,
    required int fileSize,
  }) async {
    if (fileHash.isNotEmpty) {
      final cachedInfo = await getCachedVideoInfo(fileHash);
      if (cachedInfo != null) {
        if (cachedInfo['matches'] != null && cachedInfo['matches'].isNotEmpty) {
          final match = cachedInfo['matches'][0];
          if (match['episodeId'] != null && match['animeId'] != null) {
            try {
              final episodeId = match['episodeId'].toString();
              final animeId = match['animeId'] as int;
              final danmakuData = await getDanmaku(episodeId, animeId);
              cachedInfo['comments'] = danmakuData['comments'];
            } catch (e) {
              debugPrint('从缓存匹配信息获取弹幕失败: $e');
            }
          }
        }

        _ensureVideoInfoTitles(cachedInfo);
        return cachedInfo;
      }
    }

    final canMatchByHash = fileHash.isNotEmpty && fileSize > 0;
    if (canMatchByHash) {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();

      final baseUrl = await getApiBaseUrl();
      final apiUrl = '$baseUrl/api/v2/match';

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': userAgent,
        'X-AppId': appId,
        'X-Signature':
            generateSignature(appId, timestamp, '/api/v2/match', appSecret),
        'X-Timestamp': timestamp.toString(),
        if (_isLoggedIn && _token != null) 'Authorization': 'Bearer $_token',
      };

      final body = json.encode({
        'fileName': fileName,
        'fileHash': fileHash,
        'fileSize': fileSize,
        'matchMode': 'hashAndFileName',
        if (_isLoggedIn && _token != null) 'token': _token,
      });

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['isMatched'] == true) {
          _ensureVideoInfoTitles(data);

          if (fileHash.isNotEmpty) {
            await saveVideoInfoToCache(fileHash, data);
          }

          if (data['matches'] != null && data['matches'].isNotEmpty) {
            final match = data['matches'][0];
            if (match['episodeId'] != null && match['animeId'] != null) {
              try {
                final episodeId = match['episodeId'].toString();
                final animeId = match['animeId'] as int;
                final danmakuData = await getDanmaku(episodeId, animeId);
                data['comments'] = danmakuData['comments'];
              } catch (e) {
                debugPrint('获取弹幕失败: $e');
              }
            }
          }

          return data;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final bool autoMatchEnabled = prefs.getBool(
          SettingsKeys.autoMatchDanmakuFirstSearchResultOnHashFail,
        ) ??
        true;

    if (autoMatchEnabled) {
      try {
        final fallback = await _tryMatchByFileNameFirstResult(
          fileName: fileName,
          fileHash: fileHash,
          fileSize: fileSize,
        );
        if (fallback != null && fallback['isMatched'] == true) {
          _ensureVideoInfoTitles(fallback);
          if (fileHash.isNotEmpty) {
            await saveVideoInfoToCache(fileHash, fallback);
          }

          if (fallback['matches'] != null &&
              fallback['matches'] is List &&
              fallback['matches'].isNotEmpty) {
            final match = fallback['matches'][0];
            if (match is Map &&
                match['episodeId'] != null &&
                match['animeId'] != null) {
              try {
                final episodeId = match['episodeId'].toString();
                final animeId = match['animeId'] as int;
                final danmakuData = await getDanmaku(episodeId, animeId);
                fallback['comments'] = danmakuData['comments'];
              } catch (e) {
                debugPrint('fallback 获取弹幕失败: $e');
              }
            }
          }

          return fallback;
        }
      } catch (e) {
        debugPrint('文件名 fallback 匹配失败: $e');
      }
    }

    return {
      'isMatched': false,
      'fileName': fileName,
      'fileHash': fileHash,
      'fileSize': fileSize,
      'matches': [],
    };
  }

  static void _ensureVideoInfoTitles(Map<String, dynamic> videoInfo) {
    if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
      final match = videoInfo['matches'][0];

      if (videoInfo['animeTitle'] == null ||
          videoInfo['animeTitle'].toString().isEmpty) {
        videoInfo['animeTitle'] = match['animeTitle'];
      }

      if (videoInfo['episodeTitle'] == null ||
          videoInfo['episodeTitle'].toString().isEmpty) {
        String? episodeTitle = match['episodeTitle'] as String?;

        if (episodeTitle == null || episodeTitle.isEmpty) {
          final episodeId = match['episodeId'];
          if (episodeId != null) {
            final episodeIdStr = episodeId.toString();
            if (episodeIdStr.length >= 8) {
              final episodeNumber = int.tryParse(episodeIdStr.substring(6, 8));
              if (episodeNumber != null) {
                episodeTitle = '第$episodeNumber话';
                if (match['episodeTitle'] != null &&
                    match['episodeTitle'].toString().isNotEmpty) {
                  episodeTitle += ' ${match['episodeTitle']}';
                }
              }
            }
          }
        }

        videoInfo['episodeTitle'] = episodeTitle;
      }
    }
  }

  static int? _tryParsePositiveInt(dynamic value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is double) {
      final intValue = value.toInt();
      return intValue > 0 ? intValue : null;
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed != null && parsed > 0 ? parsed : null;
    }
    return null;
  }

  static String _extractRawBaseNameFromFileName(String fileName) {
    return MediaFilenameParser.baseNameWithoutExtension(fileName);
  }

  static String _extractAnimeTitleKeywordFromFileName(String fileName) {
    final keyword = MediaFilenameParser.extractAnimeTitleKeyword(fileName);
    return keyword.isNotEmpty ? keyword : _extractRawBaseNameFromFileName(fileName);
  }

  static int? _tryExtractEpisodeNumberFromFileName(String fileName) {
    final baseName = _extractRawBaseNameFromFileName(fileName);
    if (baseName.isEmpty) return null;

    final patterns = <RegExp>[
      RegExp(r'第\\s*(\\d{1,3})\\s*[话集]'),
      RegExp(r'\\bS\\d{1,2}E(\\d{1,3})\\b', caseSensitive: false),
      RegExp(r'\\b(?:EP|Ep|ep)\\s*(\\d{1,3})\\b'),
      RegExp(r'\\bE(\\d{1,3})\\b', caseSensitive: false),
      RegExp(r'\\[(\\d{1,3})\\]'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(baseName);
      if (match != null) {
        final parsed = int.tryParse(match.group(1) ?? '');
        if (parsed != null && parsed > 0 && parsed <= 300) {
          return parsed;
        }
      }
    }

    final allNumbers = RegExp(r'(\\d{1,4})').allMatches(baseName);
    int? candidate;
    for (final m in allNumbers) {
      final parsed = int.tryParse(m.group(1) ?? '');
      if (parsed == null) continue;
      if (parsed == 264 ||
          parsed == 265 ||
          parsed == 480 ||
          parsed == 720 ||
          parsed == 1080 ||
          parsed == 2160 ||
          parsed == 4) {
        continue;
      }
      if (parsed <= 0 || parsed > 300) continue;
      candidate = parsed;
    }
    return candidate;
  }

  static Future<List<Map<String, dynamic>>> _searchAnimeByKeyword(
      String keyword) async {
    if (keyword.trim().isEmpty) return [];

    final appSecret = await getAppSecret();
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    const apiPath = '/api/v2/search/anime';
    final baseUrl = await getApiBaseUrl();
    final url =
        '$baseUrl$apiPath?keyword=${Uri.encodeComponent(keyword.trim())}';

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'User-Agent': userAgent,
        'X-AppId': appId,
        'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
        'X-Timestamp': '$timestamp',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode != 200) {
      return [];
    }

    final data = json.decode(response.body);
    if (data is! Map<String, dynamic>) return [];
    final animes = data['animes'];
    if (animes is! List) return [];

    return animes
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> _getBangumiEpisodes(
      int animeId) async {
    final appSecret = await getAppSecret();
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    final apiPath = '/api/v2/bangumi/$animeId';
    final baseUrl = await getApiBaseUrl();
    final url = '$baseUrl$apiPath';

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'User-Agent': userAgent,
        'X-AppId': appId,
        'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
        'X-Timestamp': '$timestamp',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode != 200) {
      return [];
    }

    final data = json.decode(response.body);
    if (data is! Map<String, dynamic>) return [];

    final dynamic rawEpisodes = (data['bangumi'] is Map<String, dynamic>)
        ? (data['bangumi'] as Map<String, dynamic>)['episodes']
        : data['episodes'];
    if (rawEpisodes is! List) return [];

    return rawEpisodes.whereType<Map>().map((episode) {
      final map = Map<String, dynamic>.from(episode);
      return {
        'episodeId': map['episodeId'],
        'episodeTitle': map['episodeTitle'],
        'episodeNumber': map['episodeNumber'],
      };
    }).toList();
  }

  static Future<Map<String, dynamic>?> _tryMatchByFileNameFirstResult({
    required String fileName,
    required String fileHash,
    required int fileSize,
  }) async {
    final keywordCandidates = <String>[
      _extractAnimeTitleKeywordFromFileName(fileName),
      _extractRawBaseNameFromFileName(fileName),
    ].where((e) => e.trim().isNotEmpty).toSet().toList();

    List<Map<String, dynamic>> animes = const [];
    for (final keyword in keywordCandidates) {
      final result = await _searchAnimeByKeyword(keyword);
      if (result.isNotEmpty) {
        animes = result;
        break;
      }
    }
    if (animes.isEmpty) return null;

    final firstAnime = animes.first;
    final animeId = _tryParsePositiveInt(firstAnime['animeId']);
    final animeTitle = firstAnime['animeTitle']?.toString() ?? '';
    if (animeId == null || animeTitle.trim().isEmpty) return null;

    final episodes = await _getBangumiEpisodes(animeId);
    if (episodes.isEmpty) return null;

    final episodeNumber = _tryExtractEpisodeNumberFromFileName(fileName);
    Map<String, dynamic>? selectedEpisode;
    if (episodeNumber != null) {
      selectedEpisode = episodes.cast<Map<String, dynamic>>().firstWhere(
            (ep) => _tryParsePositiveInt(ep['episodeNumber']) == episodeNumber,
            orElse: () => <String, dynamic>{},
          );
      if (selectedEpisode.isEmpty) {
        selectedEpisode = null;
      }
    }
    selectedEpisode ??= episodes.first;

    final episodeId = _tryParsePositiveInt(selectedEpisode['episodeId']);
    final episodeTitle = selectedEpisode['episodeTitle']?.toString() ?? '';
    if (episodeId == null) return null;

    final match = <String, dynamic>{
      'animeId': animeId,
      'animeTitle': animeTitle,
      'episodeId': episodeId,
      'episodeTitle': episodeTitle,
      'shift': 0,
    };

    return <String, dynamic>{
      'isMatched': true,
      'animeId': animeId,
      'animeTitle': animeTitle,
      'episodeId': episodeId,
      'episodeTitle': episodeTitle,
      'matches': [match],
      'fileHash': fileHash,
      'fileName': fileName,
      'fileSize': fileSize,
      'matchMode': 'fileNameFirstResult',
    };
  }

  static Future<int> _getDanmakuChConvertFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final convert = prefs.getBool('danmaku_convert_to_simplified') ?? true;
    return convert ? 1 : 0;
  }

  static Map<String, dynamic> _parseDanmakuBody(
    String responseBody,
    String episodeId,
    int animeId,
  ) {
    final data = json.decode(responseBody);
    if (data['comments'] != null) {
      final comments = data['comments'] as List;

      final formattedComments = comments.map((comment) {
        final pParts = (comment['p'] as String).split(',');
        final time = double.tryParse(pParts[0]) ?? 0.0;
        final mode = int.tryParse(pParts[1]) ?? 1;
        final color = int.tryParse(pParts[2]) ?? 16777215;
        final content = comment['m'] as String;

        final r = (color >> 16) & 0xFF;
        final g = (color >> 8) & 0xFF;
        final b = color & 0xFF;
        final colorValue = 'rgb($r,$g,$b)';

        return {
          'time': time,
          'content': content,
          'type': mode == 1
              ? 'scroll'
              : mode == 5
                  ? 'top'
                  : 'bottom',
          'color': colorValue,
          'isMe': false,
        };
      }).toList();

      return {
        'comments': formattedComments,
        'fromCache': false,
        'count': formattedComments.length
      };
    }

    throw Exception('该视频暂无弹幕');
  }

  static String _b(String a) {
    String b = a.split('').map((c) {
      if (c.toLowerCase() != c.toUpperCase()) {
        final d = c == c.toUpperCase();
        final e = d ? 'A'.codeUnitAt(0) : 'a'.codeUnitAt(0);
        return String.fromCharCode(e + 25 - (c.codeUnitAt(0) - e));
      }
      return c;
    }).join('');

    String f;
    if (b.length >= 5) {
      final g = b[0];
      f = b.substring(1, b.length - 4) + g + b.substring(b.length - 4);
    } else {
      f = b;
    }

    String h = f.split('').map((i) {
      if (i.codeUnitAt(0) >= '0'.codeUnitAt(0) &&
          i.codeUnitAt(0) <= '9'.codeUnitAt(0)) {
        return String.fromCharCode('0'.codeUnitAt(0) + (10 - int.parse(i)));
      }
      return i;
    }).join('');

    return h.split('').map((j) {
      if (j.toLowerCase() != j.toUpperCase()) {
        return j == j.toLowerCase() ? j.toUpperCase() : j.toLowerCase();
      }
      return j;
    }).join('');
  }

  // Web版本的账号注销方法（简化实现）
  static Future<Map<String, dynamic>> getWebToken({
    required String business,
  }) async {
    final webApiBaseUrl = await _getWebApiBaseUrl();
    if (webApiBaseUrl != null) {
      if (!_isLoggedIn) {
        throw Exception('需要登录才能获取WebToken');
      }

      try {
        debugPrint('[弹弹play服务-Web] 获取WebToken: business=$business');

        final response = await http.get(
          Uri.parse('$webApiBaseUrl/api/dandanplay/webtoken?business=$business'),
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

    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能获取WebToken');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/oauth/webToken';

      final response = await http.get(
        Uri.parse('${await getApiBaseUrl()}$apiPath?business=$business'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature':
              generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorMessage =
            response.headers['x-error-message'] ?? '获取WebToken失败';
        throw Exception('获取WebToken失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 获取WebToken时出错: $e');
      rethrow;
    }
  }

  static Future<String> startDeleteAccountProcess() async {
    if (!_isLoggedIn) {
      throw Exception('需要登录才能注销账号');
    }

    try {
      final webTokenData = await getWebToken(business: 'deleteAccount');
      final webToken = webTokenData['webToken'];
      if (webToken == null || webToken.toString().isEmpty) {
        throw Exception('获取账号注销WebToken失败：响应中没有webToken字段');
      }

      final deleteAccountUrl =
          '${await getApiBaseUrl()}/api/v2/oauth/deleteAccount?webToken=$webToken';
      return deleteAccountUrl;
    } catch (e) {
      debugPrint('[弹弹play服务] 启动账号注销流程时出错: $e');
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
