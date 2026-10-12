import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import '../network/no_dandanplay_client.dart'
    if (dart.library.ui) '../../services/dandanplay_http_client.dart'
    show DandanplayLoginRequired;

import '../network/api_uri.dart';
import '../network/metadata_gateway.dart';
import '../network/http_diagnostics.dart';

import 'metadata_provider.dart';
export 'no_vault_credential_resolver.dart'
    if (dart.library.ui) 'vault_credential_resolver.dart';

abstract interface class MetadataTransport {
  Future<JsonMap> request(String path,
      {Map<String, String> query = const {}, JsonMap? body});
}

final class HttpMetadataTransport implements MetadataTransport {
  HttpMetadataTransport(
      {required this.provider,
      required this.baseUri,
      required http.Client client,
      Future<Map<String, String>> Function(String path)? headers,
      Future<Map<String, String>> Function()? privateQuery,
      this.interval = const Duration(milliseconds: 250)})
      : _client = client,
        _gateway = null,
        _headers = headers,
        _privateQuery = privateQuery;

  HttpMetadataTransport.dandanplay(MetadataGateway gateway,
      {this.interval = const Duration(milliseconds: 250)})
      : provider = 'dandanplay',
        baseUri = Uri(),
        _client = gateway.client,
        _gateway = gateway,
        _headers = null,
        _privateQuery = null;
  final String provider;
  final Uri baseUri;
  final http.Client _client;
  final MetadataGateway? _gateway;
  final Future<Map<String, String>> Function(String path)? _headers;
  final Future<Map<String, String>> Function()? _privateQuery;
  final Duration interval;
  Future<void> _tail = Future.value();
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _blockedUntil;

  @override
  Future<JsonMap> request(String path,
      {Map<String, String> query = const {}, JsonMap? body}) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      if (_blockedUntil case final at? when at.isAfter(DateTime.now())) {
        throw ProviderRetry(
            provider, at.toUtc(), 'Provider is waiting for Retry-After.');
      }
      final delay = _next.difference(DateTime.now());
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final headers = {
        'Accept': 'application/json',
        'User-Agent':
            'NipaPlay-Next/1.0 (https://github.com/MCQ-25/NipaPlay-Reload)',
        if (body != null) 'Content-Type': 'application/json',
        ...?await _headers?.call(path)
      };
      final endpoint = Uri(
          path: path,
          queryParameters: {...query, ...?await _privateQuery?.call()});
      final uri = _gateway != null
          ? await _gateway.resolve(endpoint)
          : appendApiPath(baseUri, path)
              .replace(query: endpoint.query.isEmpty ? null : endpoint.query);
      final target = httpDiagnostics(uri);
      final http.Response response;
      try {
        response = await (body == null
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 15));
      } on DandanplayLoginRequired {
        throw Failure(
            FailureCode.unavailable, 'Dandanplay login is required. $target');
      } on TimeoutException {
        throw ProviderRetry(
            provider,
            DateTime.now().toUtc().add(const Duration(seconds: 30)),
            'Request timed out. $target');
      } on SocketException {
        throw ProviderRetry(
            provider,
            DateTime.now().toUtc().add(const Duration(seconds: 30)),
            'Network unavailable. $target');
      } on http.ClientException {
        throw ProviderRetry(
            provider,
            DateTime.now().toUtc().add(const Duration(seconds: 30)),
            'Transport unavailable. $target');
      }
      _next = DateTime.now().add(interval);
      final diagnostics = httpDiagnostics(uri,
          statusCode: response.statusCode,
          contentType: response.headers['content-type']);
      if (response.statusCode == 429 || response.statusCode >= 500) {
        final retry = response.headers['retry-after'];
        final seconds = retry == null ? null : int.tryParse(retry);
        final at = seconds != null
            ? DateTime.now().toUtc().add(Duration(seconds: seconds))
            : retry == null
                ? DateTime.now().toUtc().add(const Duration(seconds: 30))
                : HttpDate.parse(retry).toUtc();
        _blockedUntil = at;
        throw ProviderRetry(provider, at, 'Provider returned $diagnostics');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Failure(FailureCode.unavailable,
            '$provider authentication or quota authorization required. $diagnostics');
      }
      if (response.statusCode == 404) {
        throw Failure(
            FailureCode.notFound, '$provider object not found. $diagnostics');
      }
      if (response.statusCode != 200) {
        throw Failure(
            FailureCode.unavailable, '$provider returned $diagnostics');
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw Failure(FailureCode.unavailable,
            '$provider returned invalid JSON. $diagnostics');
      }
      if (decoded is! Map) {
        throw Failure(FailureCode.unavailable,
            '$provider returned a malformed response. $diagnostics');
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      done.complete();
    }
  }
}
