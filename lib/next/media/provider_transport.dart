import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';

import 'metadata_provider.dart';

abstract interface class MetadataTransport {
  Future<JsonMap> request(String path,
      {Map<String, String> query = const {}, JsonMap? body});
}

final class FileCredentialResolver implements CredentialResolver {
  FileCredentialResolver(Directory nextRoot)
      : _file = File('${nextRoot.path}/credentials.json');
  final File _file;

  Future<void> initialize() async {
    await _file.parent.create(recursive: true);
    if (!await _file.exists()) {
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString('');
      await _restrict(temporary);
      await temporary.writeAsString('{}', flush: true);
      await temporary.rename(_file.path);
    }
    await _restrict(_file);
  }

  Future<void> _restrict(File file) async {
    if (Platform.isWindows) {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''$ErrorActionPreference = 'Stop';
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User;
$acl = [System.Security.AccessControl.FileSecurity]::new();
$acl.SetOwner($sid);
$acl.SetAccessRuleProtection($true, $false);
$rule = [System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow');
$acl.SetAccessRule($rule);
Set-Acl -LiteralPath $env:NIPAPLAY_CREDENTIAL_PATH -AclObject $acl;'''
      ], environment: {
        'NIPAPLAY_CREDENTIAL_PATH': file.path
      });
      if (result.exitCode != 0) {
        throw const Failure(FailureCode.unavailable,
            'Cannot restrict credential file permissions.');
      }
      return;
    }
    final result = await Process.run('chmod', ['600', file.path]);
    if (result.exitCode != 0) {
      throw const Failure(FailureCode.unavailable,
          'Cannot restrict credential file permissions.');
    }
  }

  @override
  Future<String> resolve(CredentialRef ref) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await _file.readAsString());
    } on FormatException {
      throw const Failure(
          FailureCode.unavailable, 'Credential file contains invalid JSON.');
    }
    if (decoded is! Map) {
      throw const Failure(
          FailureCode.unavailable, 'Credential file must contain an object.');
    }
    final values = decoded;
    final secret = values[ref.id];
    if (secret is! String || secret.isEmpty) {
      throw Failure(FailureCode.unavailable,
          'Credential reference ${ref.id} is not configured.');
    }
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
