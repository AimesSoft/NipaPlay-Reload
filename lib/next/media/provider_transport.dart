import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';

import 'metadata_provider.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_file_migration.dart';
import 'package:nipaplay/security/secret_redactor.dart';

abstract interface class MetadataTransport {
  Future<JsonMap> request(String path,
      {Map<String, String> query = const {}, JsonMap? body});
}

final class VaultCredentialResolver implements CredentialResolver {
  VaultCredentialResolver(this.root, {CredentialStore? store})
      : store = store ?? CredentialStore.instance;
  final Directory root;
  final CredentialStore store;
  Future<void> initialize() => migrateCredentialFiles(root, store);
  @override
  Future<String> resolve(CredentialRef ref) async {
    String? secret;
    final file = File('${root.path}/credentials.json');
    if (await file.exists()) {
      final values = jsonDecode(await file.readAsString()) as Map;
      // Keep using the old value if migration failed, including non-desktop.
      if (values[ref.key] is String) secret = values[ref.key] as String;
    }
    secret ??= await store.vault.read(ref);
    if (secret == null || secret.isEmpty) {
      throw Failure(FailureCode.unavailable, '$ref is not configured.');
    }
    SecretRedactor.remember(ref, secret);
    return secret;
  }
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
        _headers = headers,
        _privateQuery = privateQuery;
  final String provider;
  final Uri baseUri;
  final http.Client _client;
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
      final uri = baseUri.resolve(path).replace(
          queryParameters: {...query, ...?await _privateQuery?.call()});
      final http.Response response;
      try {
        response = await (body == null
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 15));
      } on TimeoutException {
        throw ProviderRetry(
            provider,
            DateTime.now().toUtc().add(const Duration(seconds: 30)),
            'Request timed out.');
      } on SocketException {
        throw ProviderRetry(
            provider,
            DateTime.now().toUtc().add(const Duration(seconds: 30)),
            'Network unavailable.');
      } on http.ClientException {
        throw ProviderRetry(
            provider,
            DateTime.now().toUtc().add(const Duration(seconds: 30)),
            'Transport unavailable.');
      }
      _next = DateTime.now().add(interval);
      if (response.statusCode == 429 || response.statusCode >= 500) {
        final retry = response.headers['retry-after'];
        final seconds = retry == null ? null : int.tryParse(retry);
        final at = seconds != null
            ? DateTime.now().toUtc().add(Duration(seconds: seconds))
            : retry == null
                ? DateTime.now().toUtc().add(const Duration(seconds: 30))
                : HttpDate.parse(retry).toUtc();
        _blockedUntil = at;
        throw ProviderRetry(
            provider, at, 'Provider returned HTTP ${response.statusCode}.');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Failure(FailureCode.unavailable,
            '$provider authentication or quota authorization required.');
      }
      if (response.statusCode == 404) {
        throw Failure(FailureCode.notFound, '$provider object not found.');
      }
      if (response.statusCode != 200) {
        throw Failure(FailureCode.unavailable,
            '$provider returned HTTP ${response.statusCode}.');
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw Failure(
            FailureCode.unavailable, '$provider returned invalid JSON.');
      }
      if (decoded is! Map) {
        throw Failure(FailureCode.unavailable,
            '$provider returned a malformed response.');
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      done.complete();
    }
  }
}
