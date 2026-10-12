import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay_core/services/nipaplay_server_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TV 版账号服务：弹弹play 登录 + 登录态持久化。
///
/// 登录协议与普通版一致（`/api/v2/login`，appId `nipaplayv1`，
/// MD5 口令 hash + SHA256 请求签名），凭据键名沿用普通版
/// （`dandanplay_token` / `dandanplay_username` / `dandanplay_logged_in`），
/// 因此两版登录态互认。网关经 core 的 [NipaplayServerRouter] 选择。
///
/// 用户要求：**弹弹远程服务需登录后才可使用**——[isLoggedIn] 即为该闸门。
class TvAccountService {
  TvAccountService._();
  static final TvAccountService instance = TvAccountService._();

  static const String appId = 'nipaplayv1';
  static const String appSecret = 'server-managed';
  static const String userAgent = 'NipaPlay/1.0';

  // 与普通版共享的键名（两版登录态互认）
  static const _tokenKey = 'dandanplay_token';
  static const _userKey = 'dandanplay_username';
  static const _screenNameKey = 'dandanplay_screenname';
  static const _loggedInKey = 'dandanplay_logged_in';

  bool _loggedIn = false;
  String? _userName;
  String? _screenName;
  String? _token;

  bool get isLoggedIn => _loggedIn;
  String? get userName => _userName;
  String? get screenName => _screenName;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _loggedIn = prefs.getBool(_loggedInKey) ?? false;
    _userName = prefs.getString(_userKey);
    _screenName = prefs.getString(_screenNameKey);
    _token = prefs.getString(_tokenKey);
  }

  String _generateSignature(int timestamp, String apiPath) {
    final source = '$appId$timestamp$apiPath$appSecret';
    return base64Encode(sha256.convert(utf8.encode(source)).bytes);
  }

  /// 弹弹play 账号登录。成功返回 true；失败抛异常并带可读信息。
  Future<void> login(String username, String password) async {
    final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000)
        .round();
    final hash = md5
        .convert(utf8.encode('$appId$password$timestamp$username$appSecret'))
        .toString();
    final base = await NipaplayServerRouter.instance.effectiveServer();

    final resp = await http
        .post(
          Uri.parse('$base/api/v2/login'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': userAgent,
            'X-AppId': appId,
            'X-Signature': _generateSignature(timestamp, '/api/v2/login'),
            'X-Timestamp': '$timestamp',
          },
          body: json.encode({
            'userName': username,
            'password': password,
            'appId': appId,
            'unixTimestamp': timestamp,
            'hash': hash,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw Exception('登录失败：HTTP ${resp.statusCode}');
    }
    final data = json.decode(utf8.decode(resp.bodyBytes));
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('登录失败：服务器未返回 token'
          '${data['errorMessage'] != null ? '（${data['errorMessage']}）' : ''}');
    }
    await _persist(
      token: token,
      userName: (data['userName'] as String?) ?? username,
      screenName: (data['screenName'] as String?) ?? username,
    );
  }

  Future<void> _persist({
    required String token,
    required String userName,
    required String screenName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, userName);
    await prefs.setString(_screenNameKey, screenName);
    await prefs.setBool(_loggedInKey, true);
    _token = token;
    _userName = userName;
    _screenName = screenName;
    _loggedIn = true;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_screenNameKey);
    await prefs.setBool(_loggedInKey, false);
    _token = null;
    _userName = null;
    _screenName = null;
    _loggedIn = false;
  }

  /// 供远程服务带鉴权头（弹弹远程服务需登录后使用）。
  Map<String, String> authHeaders() {
    final token = _token;
    if (token == null || token.isEmpty) return const {};
    return {
      'Authorization': 'Bearer $token',
      'X-AppId': appId,
      'User-Agent': userAgent,
    };
  }
}
