import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart' show AuthType, DigestParts;

/// WebDAV HTTP 认证协商器。
///
/// 与 webdav_client 的 WdDio 行为一致：先发送乐观 Basic；收到 401 时按
/// WWW-Authenticate 挑战切换到 Digest（stale=true 时刷新 nonce 重试一次）。
/// 挑战参数用 webdav_client 的 [DigestParts] 解析，摘要按 RFC 7616 自行计算：
/// webdav_client 的 DigestAuth 会对 uri 再做一次 encodeFull，已编码的请求
/// 路径（空格、中文文件名）会被二次编码，导致摘要与实际请求不符。
class WebDavChallengeAuth {
  WebDavChallengeAuth({
    required this.username,
    required this.password,
    @visibleForTesting String Function()? cnonceGenerator,
  }) : _cnonceGenerator = cnonceGenerator ?? _randomCnonce;

  /// 无凭证模式：不发送 Authorization，仅在收到挑战后按需协商。
  WebDavChallengeAuth.unauthenticated()
      : username = '',
        password = '',
        _cnonceGenerator = _randomCnonce;

  final String username;
  final String password;
  final String Function() _cnonceGenerator;
  int _nonceCount = 0;

  AuthType _type = AuthType.BasicAuth;
  DigestParts? _digestParts;
  // 允许的 401 重试次数：一次 Basic→Digest 切换 + 一次 stale nonce 刷新。
  int _retryBudget = 2;

  bool get hasCredentials =>
      username.trim().isNotEmpty || password.isNotEmpty;

  /// 当前应发送的 Authorization 头；连接未配置凭证时返回 null。
  String? authorizationHeader(String method, String requestTarget) {
    if (!hasCredentials) return null;
    if (_type == AuthType.DigestAuth) {
      return _digestAuthorization(method, requestTarget);
    }
    return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }

  /// RFC 7616 Digest（MD5 / MD5-sess，qop=auth 或无 qop）。
  ///
  /// [requestTarget] 必须与实际发送的请求路径逐字相同（已编码），这里不再编码。
  String _digestAuthorization(String method, String requestTarget) {
    final parts = _digestParts?.parts ?? const <String, String>{};
    final realm = parts['realm'] ?? '';
    final nonce = parts['nonce'] ?? '';
    final opaque = parts['opaque'] ?? '';
    final algorithm = (parts['algorithm'] ?? '').trim();
    // 挑战可能给出 "auth,auth-int"；不对实体做摘要，只用 auth。
    final qopOptions = (parts['qop'] ?? '')
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList();
    final qop = qopOptions.contains('auth') ? 'auth' : null;

    final cnonce = _cnonceGenerator();
    final nc = (++_nonceCount).toRadixString(16).padLeft(8, '0');
    var ha1 = _md5Hex('$username:$realm:$password');
    if (algorithm.toUpperCase() == 'MD5-SESS') {
      ha1 = _md5Hex('$ha1:$nonce:$cnonce');
    }
    final ha2 = _md5Hex('$method:$requestTarget');
    final response = qop == null
        ? _md5Hex('$ha1:$nonce:$ha2')
        : _md5Hex('$ha1:$nonce:$nc:$cnonce:$qop:$ha2');

    final header = StringBuffer(
      'Digest username="$username", realm="$realm", nonce="$nonce", '
      'uri="$requestTarget", response="$response"',
    );
    if (algorithm.isNotEmpty) header.write(', algorithm=$algorithm');
    if (qop != null) header.write(', qop=$qop, nc=$nc, cnonce="$cnonce"');
    if (opaque.isNotEmpty) header.write(', opaque="$opaque"');
    return header.toString();
  }

  static String _md5Hex(String value) =>
      md5.convert(utf8.encode(value)).toString();

  static String _randomCnonce() {
    final random = Random.secure();
    return List.generate(8, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 生成携带当前认证方案的请求头集合。
  Map<String, String> authHeaders(String method, String requestTarget) {
    final value = authorizationHeader(method, requestTarget);
    return value == null ? const {} : <String, String>{'authorization': value};
  }

  /// 收到 401 时尝试按挑战更新认证方案。
  ///
  /// 返回 true 表示方案已更新、应当用新 Authorization 重发请求；
  /// 返回 false 表示凭证本身被拒（或重试预算耗尽），无重试价值。
  bool tryHandleUnauthorized(String? wwwAuthenticate) {
    if (_retryBudget <= 0) return false;
    final challenge = wwwAuthenticate?.toLowerCase() ?? '';
    if (_type == AuthType.DigestAuth) {
      // stale=true：nonce 过期，按新挑战参数刷新后重试。
      if (challenge.contains('digest') && challenge.contains('stale=true')) {
        _digestParts = DigestParts(wwwAuthenticate);
        _nonceCount = 0;
        _retryBudget--;
        return true;
      }
      return false;
    }
    if (challenge.contains('digest')) {
      _type = AuthType.DigestAuth;
      _digestParts = DigestParts(wwwAuthenticate);
      _nonceCount = 0;
      _retryBudget--;
      return true;
    }
    // Basic 挑战说明乐观 Basic 已被拒，凭证错误，重试无意义。
    return false;
  }
}

/// Digest 认证的 request-target（RFC 7616 的 uri 参数应为 path[?query]）。
String webDavDigestRequestTarget(Uri url) {
  final query = url.query;
  return query.isEmpty ? url.path : '${url.path}?$query';
}

/// 带挑战式认证的 WebDAV GET。
///
/// 401 时按 WWW-Authenticate 切换 Basic/Digest 重试，30x 手动跟随。凭证只发往
/// [url] 的源（scheme + host + port），跨源跳转后不再携带；Digest 的 uri 按
/// 每一跳实际请求的路径计算。返回最终响应，状态码由调用方判断。
Future<Response<List<int>>> webDavAuthenticatedGet(
  Dio dio,
  Uri url,
  WebDavChallengeAuth auth, {
  Map<String, String> headers = const {},
  int maxRedirects = 5,
}) async {
  final origin = url.replace(userInfo: '');
  var target = origin;
  var redirects = 0;
  while (true) {
    final sameOrigin = _isSameOrigin(target, origin);
    final response = await dio.getUri<List<int>>(
      target,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        // 401 和 30x 都在这里处理，不能让 Dio 抛错或自动跟随。
        validateStatus: (status) => status != null,
        headers: <String, String>{
          ...headers,
          if (sameOrigin)
            ...auth.authHeaders('GET', webDavDigestRequestTarget(target)),
        },
      ),
    );
    final status = response.statusCode ?? 0;
    if (status == 401 &&
        sameOrigin &&
        auth.tryHandleUnauthorized(response.headers.value('www-authenticate'))) {
      continue;
    }
    final location = response.headers.value('location');
    if (status >= 300 &&
        status < 400 &&
        location != null &&
        redirects < maxRedirects) {
      target = target.resolve(location).replace(userInfo: '');
      redirects++;
      continue;
    }
    return response;
  }
}

bool _isSameOrigin(Uri a, Uri b) =>
    a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
    a.host.toLowerCase() == b.host.toLowerCase() &&
    a.port == b.port;
