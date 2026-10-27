import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/system_proxy_service.dart';
import '../network/api_uri.dart';

/// The URL of a coordinator API [path] (`/mesh/v1/...`) under [base].
///
/// The API lives under `/mesh/` on the server. A base that is the server's
/// origin (`https://host`) simply gets that path; a base that already ends in
/// `/mesh` (the built-in default, `https://host/mesh`) shares the prefix
/// instead of repeating it. Any other prefix is kept in front, as for a
/// gateway mounted at a sub-path.
Uri meshEndpoint(Uri base, String path) {
  final prefix = base.path.replaceFirst(RegExp(r'/+$'), '');
  if (prefix.endsWith('/mesh') && path.startsWith('/mesh/')) {
    return appendApiPath(base, path.substring('/mesh'.length));
  }
  return appendApiPath(base, path);
}

final class MeshCoordinator {
  MeshCoordinator(
    this.base,
    this.token, {
    HttpClient? httpClient,
    String Function(Uri)? findProxy,
  }) : _client = httpClient ?? HttpClient() {
    if (base.scheme != 'https' &&
        !(base.scheme == 'http' &&
            ['127.0.0.1', '::1', 'localhost'].contains(base.host))) {
      throw const FormatException(
          'Mesh coordinator requires HTTPS (loopback HTTP is permitted).');
    }
    if (base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment) {
      throw const FormatException('Invalid Mesh coordinator URL.');
    }
    _client.findProxy = findProxy ?? resolveProxy;
    _client.connectionTimeout = const Duration(seconds: 10);
  }
  final Uri base;
  final Future<String?> Function() token;
  final HttpClient _client;

  static String resolveProxy(
    Uri uri, {
    String Function(Uri)? systemProxy,
  }) {
    return AppHttpProxy.findProxy(
        uri, systemProxy ?? SystemProxyService.instance.findProxy);
  }

  /// [authenticated] false is for the one call the device key alone may make
  /// (renewing its certificate): no account token is read or sent, so a
  /// device whose token has expired keeps its place in the mesh.
  Future<JsonMap> request(String method, String path,
      [JsonMap? body, bool authenticated = true]) async {
    String? bearer;
    if (authenticated) {
      bearer = await token();
      if (bearer == null || bearer.isEmpty) {
        throw const Failure(
            FailureCode.unavailable, 'Sign in to Dandanplay to join Mesh.');
      }
    }
    try {
      return await _request(method, path, body, bearer)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const Failure(
          FailureCode.unavailable, 'Mesh coordinator timed out.',
          retryable: true);
    } on IOException {
      throw const Failure(
          FailureCode.unavailable, 'Mesh coordinator is unreachable.',
          retryable: true);
    } on FormatException {
      // A captive portal or filtering proxy answers with a page, not JSON.
      throw const Failure(FailureCode.unavailable,
          'Mesh coordinator returned an unreadable response.',
          retryable: true);
    }
  }

  Future<JsonMap> _request(
      String method, String path, JsonMap? body, String? bearer) async {
    await SystemProxyService.instance.initialize();
    final endpoint = Uri.parse(path);
    final uri = meshEndpoint(base, endpoint.path)
        .replace(query: endpoint.hasQuery ? endpoint.query : null);
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    if (bearer != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('Mesh control response too large.');
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! JsonMap) {
      throw const FormatException('Invalid Mesh control response.');
    }
    if (response.statusCode != 200 || decoded['success'] != true) {
      throw Failure(FailureCode.unavailable,
          'Mesh coordinator: ${decoded['error'] ?? 'invalid_response'}.',
          retryable: response.statusCode >= 500 || response.statusCode == 429);
    }
    return decoded;
  }

  void close() => _client.close(force: true);
}
