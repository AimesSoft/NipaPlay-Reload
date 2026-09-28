import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as transport;
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/nipaplay_server_router.dart';
import 'package:nipaplay/utils/http_header_utils.dart';
import 'package:nipaplay/utils/network_settings.dart';

export 'package:http/http.dart'
    hide get, post, put, patch, delete, head, read, readBytes;

class DandanplayLoginRequired extends StateError {
  DandanplayLoginRequired() : super('请先登录弹弹play账号后再使用弹弹play服务');
}

/// One request boundary for all Dandanplay consumers, including the Web relay.
/// Other providers keep their own authentication and never receive our token.
class DandanplayHttpClient extends transport.BaseClient {
  DandanplayHttpClient({
    transport.Client? inner,
    Map<String, String> Function()? authorization,
  })  : _inner = inner ?? transport.Client(),
        _authorization =
            authorization ?? (() => DandanplayService.authorizationHeaders);

  final transport.Client _inner;
  final Map<String, String> Function() _authorization;

  static Uri targetUri(Uri uri) {
    for (var depth = 0; depth < 4; depth++) {
      if (!uri.path.endsWith('/api/web_proxy') &&
          !uri.path.endsWith('/api/image_proxy')) {
        break;
      }
      var targetUrl = uri.queryParameters['url'] ?? '';
      if (uri.path.endsWith('/api/image_proxy')) {
        try {
          targetUrl = utf8.decode(base64Url.decode(targetUrl));
        } on FormatException {
          // The image relay also accepts a plain URL.
        }
      }
      final target = Uri.tryParse(targetUrl);
      if (target == null || !target.hasScheme) break;
      uri = target;
    }
    return uri;
  }

  static bool isAccountEntry(String method, Uri uri) {
    return method == 'POST' &&
        (uri.path.endsWith('/api/v2/login') ||
            uri.path.endsWith('/api/v2/register'));
  }

  @override
  Future<transport.StreamedResponse> send(transport.BaseRequest request) async {
    final target = targetUri(request.url);
    final authorization = _authorization();
    final isGatewayTarget = NetworkSettings.isDandanplayServiceUri(target);
    if (isGatewayTarget) {
      if (!isAccountEntry(request.method, target)) {
        // The desktop relay injects its token. The browser only knows the
        // synchronized login state, and must never receive the desktop token.
        if (kIsWeb && target != request.url && DandanplayService.isLoggedIn) {
          return _inner.send(request);
        }
        if (authorization.isEmpty) throw DandanplayLoginRequired();
        // 这里不能用 removeWhere/addAll 改写：http 的 headers 是自定义
        // equals 的 LinkedHashMap，会踩到 dart-lang/sdk#64217。
        addOrReplaceHeaders(request.headers, authorization);
      }
    } else {
      final token = authorization['Authorization'];
      final isSelectedCustomTarget = token != null &&
          await NetworkSettings.isSelectedCustomDandanplayServiceUri(target);
      if (isSelectedCustomTarget && !isAccountEntry(request.method, target)) {
        // A selected custom server is an explicit trust decision. Give a
        // compatible self-hosted proxy the same current account credential as
        // the built-in gateways, even when an older caller omitted the header.
        addOrReplaceHeaders(request.headers, authorization);
      } else if (token != null && !isSelectedCustomTarget) {
        // Only the custom server explicitly selected by the user is trusted to
        // receive their Dandanplay account token. Keep stripping it from every
        // unrelated provider handled by this shared client.
        removeHeaderIfValueMatches(request.headers, 'authorization', token);
      }
    }
    try {
      final response = await _inner.send(request);
      if (isGatewayTarget) {
        // 网关自身故障（nginx 502/504、网关 5xx）也计入失败，
        // 以便连续失败后由备用服务器接管。
        if (response.statusCode >= 500) {
          NipaplayServerRouter.instance.reportFailure(target);
        } else {
          NipaplayServerRouter.instance.reportSuccess(target);
        }
      }
      return response;
    } catch (error) {
      if (isGatewayTarget) {
        NipaplayServerRouter.instance.reportFailure(target);
      }
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}

Future<transport.Response> _request(String method, Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final client = DandanplayHttpClient();
  try {
    final request = transport.Request(method, url);
    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body is String) {
      request.body = body;
    } else if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body is Map) {
      request.bodyFields = body.cast<String, String>();
    } else if (body != null) {
      throw ArgumentError.value(body, 'body', 'Unsupported request body');
    }
    return await transport.Response.fromStream(await client.send(request));
  } finally {
    client.close();
  }
}

Future<transport.Response> get(Uri url, {Map<String, String>? headers}) =>
    _request('GET', url, headers: headers);
Future<transport.Response> head(Uri url, {Map<String, String>? headers}) =>
    _request('HEAD', url, headers: headers);
Future<transport.Response> post(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _request('POST', url, headers: headers, body: body, encoding: encoding);
Future<transport.Response> put(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _request('PUT', url, headers: headers, body: body, encoding: encoding);
Future<transport.Response> patch(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _request('PATCH', url, headers: headers, body: body, encoding: encoding);
Future<transport.Response> delete(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _request('DELETE', url, headers: headers, body: body, encoding: encoding);
