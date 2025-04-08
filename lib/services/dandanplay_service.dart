import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/painting.dart';

class DandanplayService {
  static const String appId = "nipaplayv1";
  static String? _token;
  static String? _appSecret;
  static const String _videoCacheKey = 'video_recognition_cache';
  static const String _lastTokenRenewKey = 'last_token_renew_time';
  static const int _tokenRenewInterval = 21 * 24 * 60 * 60 * 1000; // 21天（毫秒）
  static bool _isLoggedIn = false;
  static String? _userName;
  static String? _screenName;

  static bool get isLoggedIn => _isLoggedIn;
  static String? get userName => _userName;
  static String? get screenName => _screenName;

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('dandanplay_logged_in') ?? false;
    _userName = prefs.getString('dandanplay_username');
    _screenName = prefs.getString('dandanplay_screenname');
    await loadToken();
  }

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('dandanplay_token');
    
    // 检查是否需要刷新Token
    await _checkAndRenewToken();
  }

  static Future<void> saveLoginInfo(String token, String username, String screenName) async {
    _token = token;
    _userName = username;
    _screenName = screenName;
    _isLoggedIn = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dandanplay_token', token);
    await prefs.setString('dandanplay_username', username);
    await prefs.setString('dandanplay_screenname', screenName);
    await prefs.setBool('dandanplay_logged_in', true);
    await prefs.setInt(_lastTokenRenewKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> clearLoginInfo() async {
    _token = null;
    _userName = null;
    _screenName = null;
    _isLoggedIn = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dandanplay_token');
    await prefs.remove('dandanplay_username');
    await prefs.remove('dandanplay_screenname');
    await prefs.remove('dandanplay_logged_in');
    await prefs.remove(_lastTokenRenewKey);
  }

  // 检查并刷新Token
  static Future<void> _checkAndRenewToken() async {
    if (_token == null) return;

    final prefs = await SharedPreferences.getInstance();
    final lastRenewTime = prefs.getInt(_lastTokenRenewKey) ?? 0;
    final currentTime = DateTime.now().millisecondsSinceEpoch;

    // 如果距离上次刷新超过21天，则刷新Token
    if (currentTime - lastRenewTime >= _tokenRenewInterval) {
      try {
        final appSecret = await _a();
        final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();

        final response = await http.post(
          Uri.parse('https://api.dandanplay.net/api/v2/login/renew'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-AppId': appId,
            'X-Signature': _c(timestamp, '/api/v2/login/renew', appSecret),
            'X-Timestamp': '$timestamp',
            'Authorization': 'Bearer $_token',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true && data['token'] != null) {
            // 更新Token和刷新时间
            _token = data['token'];
            await saveToken(_token!);
            await prefs.setInt(_lastTokenRenewKey, currentTime);
            print('Token已成功刷新');
          } else {
            print('Token刷新失败: ${data['errorMessage']}');
          }
        } else {
          print('Token刷新请求失败: ${response.statusCode}');
        }
      } catch (e) {
        print('Token刷新时发生错误: $e');
      }
    }
  }

  static Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dandanplay_token', token);
    // 保存Token刷新时间
    await prefs.setInt(_lastTokenRenewKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dandanplay_token');
    await prefs.remove(_lastTokenRenewKey);
  }

  // 获取缓存的视频信息
  static Future<Map<String, dynamic>?> getCachedVideoInfo(String fileHash) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString(_videoCacheKey);
    if (cache != null) {
      final Map<String, dynamic> cacheMap = json.decode(cache);
      print('缓存数据: ${json.encode(cacheMap)}');
      print('查找哈希: $fileHash');
      print('缓存中是否有该哈希: ${cacheMap.containsKey(fileHash)}');
      if (cacheMap.containsKey(fileHash)) {
        final videoInfo = cacheMap[fileHash];
        print('视频信息: ${json.encode(videoInfo)}');
        return videoInfo;
      }
    }
    return null;
  }

  // 保存视频信息到缓存
  static Future<void> saveVideoInfoToCache(String fileHash, Map<String, dynamic> videoInfo) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString(_videoCacheKey);
    Map<String, dynamic> cacheMap = {};
    
    if (cache != null) {
      cacheMap = Map<String, dynamic>.from(json.decode(cache));
    }
    
    cacheMap[fileHash] = videoInfo;
    await prefs.setString(_videoCacheKey, json.encode(cacheMap));
  }

  static Future<String> _a() async {
    if (_appSecret != null) return _appSecret!;

    final response = await http.post(
      Uri.parse('https://nipaplay.aimes-soft.com/nipaplay.php'),
      headers: {'Content-Type': 'application/json'},
      body: '{}',
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _appSecret = _b(data['encryptedAppSecret']);
      return _appSecret!;
    } else {
      throw Exception('获取appSecret失败');
    }
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
      if (i.codeUnitAt(0) >= '0'.codeUnitAt(0) && i.codeUnitAt(0) <= '9'.codeUnitAt(0)) {
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

  static String _c(int timestamp, String apiPath, String appSecret) {
    final signatureString = '$appId$timestamp$apiPath$appSecret';
    final hash = sha256.convert(utf8.encode(signatureString));
    return base64.encode(hash.bytes);
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final appSecret = await _a();
      final now = DateTime.now();
      final utcNow = now.toUtc();
      final timestamp = (utcNow.millisecondsSinceEpoch / 1000).round();
      final hashString = '$appId$password$timestamp$username$appSecret';
      final hash = md5.convert(utf8.encode(hashString)).toString();

      final response = await http.post(
        Uri.parse('https://api.dandanplay.net/api/v2/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-AppId': appId,
          'X-Signature': _c(timestamp, '/api/v2/login', appSecret),
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
          _token = data['token'];
          await saveToken(data['token']);
          return {'success': true, 'message': '登录成功'};
        } else {
          return {'success': false, 'message': data['errorMessage'] ?? '登录失败，请检查用户名和密码'};
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? response.body;
        return {'success': false, 'message': '网络请求失败 (${response.statusCode}): $errorMessage'};
      }
    } catch (e) {
      return {'success': false, 'message': '登录失败: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    try {
      final appSecret = await _a();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final file = File(videoPath);
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final fileHash = await _d(file);

      // 尝试从缓存获取视频信息
      final cachedInfo = await getCachedVideoInfo(fileHash);
      if (cachedInfo != null) {
        // 检查缓存中是否有 episodeId
        if (cachedInfo['matches'] != null && cachedInfo['matches'].isNotEmpty) {
          final match = cachedInfo['matches'][0];
          if (match['episodeId'] != null) {
            try {
              final danmakuData = await getDanmaku(videoPath, match['episodeId'].toString());
              // 直接使用弹幕数据，不添加额外的 danmaku 字段
              cachedInfo['comments'] = danmakuData['comments'];
            } catch (e) {
              print('弹幕加载失败: $e');
            }
          }
        }
        
        return cachedInfo;
      }

      print('发送匹配请求:');
      print('文件名: $fileName');
      print('文件大小: $fileSize');
      print('文件哈希: $fileHash');
      print('Token: $_token');

      // 检查是否登录
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('dandanplay_logged_in') ?? false;

      final response = await http.post(
        Uri.parse('https://api.dandanplay.net/api/v2/match'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-AppId': appId,
          'X-Signature': _c(timestamp, '/api/v2/match', appSecret),
          'X-Timestamp': '$timestamp',
          if (isLoggedIn && _token != null) 'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'fileName': fileName,
          'fileHash': fileHash,
          'fileSize': fileSize,
          'matchMode': 'hashAndFileName',
          if (isLoggedIn && _token != null) 'token': _token,
        }),
      );

      print('API响应状态码: ${response.statusCode}');
      print('API响应头: ${response.headers}');
      print('API响应体: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('解析后的数据: $data');
        
        if (data['isMatched'] == true) {
          // 保存到缓存
          await saveVideoInfoToCache(fileHash, data);
          
          // 获取弹幕信息
          if (data['matches'] != null && data['matches'].isNotEmpty) {
            final match = data['matches'][0];
            if (match['episodeId'] != null) {
              try {
                final danmakuData = await getDanmaku(videoPath, match['episodeId'].toString());
                // 直接使用弹幕数据，不添加额外的 danmaku 字段
                data['comments'] = danmakuData['comments'];
              } catch (e) {
                print('获取弹幕失败: $e');
              }
            }
          }
          
          return data;
        } else {
          throw Exception('无法识别该视频');
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('获取视频信息失败: $errorMessage');
      }
    } catch (e) {
      print('获取视频信息时发生错误: $e');
      throw Exception('获取视频信息失败: ${e.toString()}');
    }
  }

  static Future<String> _d(File file) async {
    const int maxBytes = 16 * 1024 * 1024; // 16MB
    final bytes = await file.openRead(0, maxBytes).expand((chunk) => chunk).toList();
    return md5.convert(bytes).toString();
  }

  static Future<Map<String, dynamic>> getDanmaku(String videoPath, String episodeId) async {
    try {
      final appSecret = await _a();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/comment/$episodeId';

      final response = await http.get(
        Uri.parse('https://api.dandanplay.net$apiPath?withRelated=true&chConvert=1'),
        headers: {
          'Accept': 'application/json',
          'X-AppId': appId,
          'X-Signature': _c(timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        //print('弹幕API响应: $data');
        if (data['comments'] != null) {
          final comments = data['comments'] as List;
          final formattedComments = comments.map((comment) {
            // 解析 p 字段，格式为 "时间,模式,颜色,用户ID"
            final pParts = (comment['p'] as String).split(',');
            final time = double.tryParse(pParts[0]) ?? 0.0;
            final mode = int.tryParse(pParts[1]) ?? 1;
            final color = int.tryParse(pParts[2]) ?? 16777215; // 默认白色
            final content = comment['m'] as String;
            
            // 转换颜色格式
            final r = (color >> 16) & 0xFF;
            final g = (color >> 8) & 0xFF;
            final b = color & 0xFF;
            final colorValue = 'rgb($r,$g,$b)';
            
            return {
              'time': time,
              'content': content,
              'type': mode == 1 ? 'scroll' : mode == 5 ? 'top' : 'bottom',
              'color': colorValue,
            };
          }).toList();
          return {'comments': formattedComments};
        } else {
          throw Exception('该视频暂无弹幕');
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('获取弹幕失败: $errorMessage');
      }
    } catch (e) {
      print('获取弹幕错误: $e');
      throw Exception('获取弹幕失败: ${e.toString()}');
    }
  }
} 