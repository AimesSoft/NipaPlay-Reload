import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/system_proxy_service.dart';
import '../network/api_uri.dart';

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
    if (['127.0.0.1', '::1', 'localhost'].contains(uri.host) ||
        InternetAddress.tryParse(uri.host)?.isLoopback == true) {
      return 'DIRECT';
    }
    return AppHttpProxy.findProxy(
        uri, systemProxy ?? SystemProxyService.instance.findProxy);
  }

  Future<JsonMap> request(String method, String path, [JsonMap? body]) async {
    final bearer = await token();
    if (bearer == null || bearer.isEmpty) {
      throw const Failure(
          FailureCode.unavailable, 'Sign in to Dandanplay to join Mesh.');
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
    }
  }

  Future<JsonMap> _request(
      String method, String path, JsonMap? body, String bearer) async {
    await SystemProxyService.instance.initialize();
    final endpoint = Uri.parse(path);
    final uri = appendApiPath(base, endpoint.path)
        .replace(query: endpoint.hasQuery ? endpoint.query : null);
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
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
