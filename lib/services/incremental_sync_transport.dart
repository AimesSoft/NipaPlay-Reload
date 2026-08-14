import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:xml/xml.dart';

abstract class IncrementalSyncTransport {
  Future<void> ensureDirectory(String path);

  Future<List<String>> listFileNames(String path);

  Future<Uint8List?> read(String path);

  Future<void> write(String path, Uint8List bytes, {bool atomic = false});
}

class WebDavSyncException implements Exception {
  const WebDavSyncException({
    required this.operation,
    required this.path,
    this.statusCode,
    required this.message,
  });

  final String operation;
  final String path;
  final int? statusCode;
  final String message;

  @override
  String toString() {
    final status = statusCode == null ? '' : '（HTTP $statusCode）';
    return 'WebDAV $operation失败$status：$message\n路径：$path';
  }
}

class WebDavIncrementalSyncTransport implements IncrementalSyncTransport {
  static const int _maximumAttempts = 3;
  static const Duration _providerRateLimitCooldown = Duration(minutes: 30);
  static final Map<String, DateTime> _rateLimitedUntilByServer = {};
  static const String _propfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:displayname/>
    <D:resourcetype/>
  </D:prop>
</D:propfind>''';
  static const List<_PropfindVariant> _propfindVariants = [
    _PropfindVariant(
      contentType: 'text/xml; charset="utf-8"',
      includeBody: true,
    ),
    _PropfindVariant(
      contentType: 'text/xml; charset="utf-8"',
      includeBody: false,
    ),
    _PropfindVariant(
      contentType: 'application/xml',
      includeBody: true,
    ),
  ];

  WebDavIncrementalSyncTransport({
    required String serverUrl,
    required String username,
    required String password,
  }) : this._withClient(webdav.newClient(
          serverUrl.trim(),
          user: username.trim(),
          password: password,
          debug: false,
        ));

  @visibleForTesting
  WebDavIncrementalSyncTransport.withClient(webdav.Client client)
      : this._withClient(client);

  WebDavIncrementalSyncTransport._withClient(this._client) {
    _client.setHeaders({
      'accept-charset': 'utf-8',
      // Keep this aligned with the WebDAV browser. Some hosted gateways apply
      // different compatibility rules based on the client identifier.
      'user-agent': 'WebDAVFS/3.0 (NipaPlay)',
    });
    _client.setConnectTimeout(15000);
    _client.setSendTimeout(60000);
    _client.setReceiveTimeout(60000);
  }

  final webdav.Client _client;

  @override
  Future<void> ensureDirectory(String path) async {
    // Some WebDAV gateways return 503 instead of the expected 405 when MKCOL
    // targets an existing collection. Probe first and only create after a
    // definitive 404 response.
    try {
      await _runWithRetry<void>(
        operation: '检查同步目录',
        path: path,
        request: () async {
          await _propfind(path, depth: '0');
        },
      );
      return;
    } on WebDavSyncException catch (error) {
      if (error.statusCode != 404) rethrow;
    }

    await _runWithRetry<void>(
      operation: '创建同步目录',
      path: path,
      request: () => _client.mkdirAll(path),
    );
  }

  @override
  Future<List<String>> listFileNames(String path) async {
    final responseBody = await _runWithRetry(
      operation: '读取同步目录',
      path: path,
      request: () => _propfind(path, depth: '1'),
    );
    final names = _parseFileNames(responseBody, path);
    final staleManifestTemps = names
        .where((name) => name.startsWith('manifest.version.tmp-'))
        .toList();
    for (final name in staleManifestTemps) {
      final temporaryPath = _joinPath(path, name);
      try {
        await _deleteDirect(temporaryPath);
        debugPrint('已清理遗留的 WebDAV 同步临时文件: $temporaryPath');
      } on DioException catch (error) {
        // Cleanup must not block sync. No new temporary manifest files are
        // created, so an incompatible DELETE implementation cannot cause
        // unbounded growth anymore.
        debugPrint(
          '清理 WebDAV 同步临时文件失败 '
          '(HTTP ${error.response?.statusCode ?? 'unknown'}): $temporaryPath',
        );
      }
    }
    return names.where((name) => !staleManifestTemps.contains(name)).toList();
  }

  @override
  Future<Uint8List?> read(String path) async {
    try {
      final bytes = await _runWithRetry(
        operation: '下载同步文件',
        path: path,
        request: () => _readDirect(path),
      );
      return bytes;
    } on WebDavSyncException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> write(
    String path,
    Uint8List bytes, {
    bool atomic = false,
  }) async {
    if (!atomic) {
      await _runWithRetry<void>(
        operation: '上传同步文件',
        path: path,
        request: () => _writeDirect(path, bytes),
      );
      return;
    }

    // PUT is a complete WebDAV resource replacement. The previous
    // PUT-temp/MOVE strategy left an orphan on servers with partial MOVE or
    // DELETE support and could grow the directory indefinitely. Manifest
    // concurrency is handled by re-reading and merging its immutable patch
    // index immediately before this publication.
    await _runWithRetry<void>(
      operation: '上传同步索引',
      path: path,
      request: () => _writeDirect(path, bytes),
    );
  }

  /// `webdav_client` performs an unconditional OPTIONS request before every
  /// GET and PUT, and PUT also repeats parent MKCOL. Several WebDAV gateways
  /// rate-limit those probes with HTTP 503. The sync layer has already
  /// validated/created its root directory, so use the client's authenticated
  /// request pipeline directly for file traffic.
  Future<String> _propfind(String path, {required String depth}) async {
    _throwIfRateLimited(path);
    DioException? lastError;
    final directoryPath = _asDirectoryPath(path);
    for (final variant in _propfindVariants) {
      final bodyBytes = variant.includeBody ? utf8.encode(_propfindBody) : null;
      try {
        final response = await _client.c.req<String>(
          _client,
          'PROPFIND',
          directoryPath,
          data: bodyBytes,
          optionsHandler: (options) {
            options.responseType = ResponseType.plain;
            options.headers?['depth'] = depth;
            options.headers?['accept'] = 'application/xml,text/xml,*/*';
            options.headers?['accept-charset'] = 'utf-8';
            options.headers?['accept-encoding'] = 'identity';
            options.headers?['connection'] = 'close';
            options.headers?['content-type'] = variant.contentType;
            if (bodyBytes != null) {
              options.headers?['content-length'] = bodyBytes.length;
            } else {
              options.headers?.remove('content-length');
            }
          },
        );
        if (const {200, 207}.contains(response.statusCode)) {
          return response.data ?? '';
        }
        final error = _responseError(response);
        if (_isProviderRateLimit(error)) {
          _recordRateLimit();
          throw error;
        }
        if ((response.statusCode ?? 0) >= 500) throw error;
        if (const {401, 403, 404}.contains(response.statusCode)) throw error;
        lastError = error;
      } on DioException catch (error) {
        if (_isProviderRateLimit(error)) {
          _recordRateLimit();
          rethrow;
        }
        if ((error.response?.statusCode ?? 0) >= 500) rethrow;
        if (const {401, 403, 404}.contains(error.response?.statusCode)) {
          rethrow;
        }
        lastError = error;
      }
    }
    throw lastError ??
        DioException(
          requestOptions: RequestOptions(path: directoryPath),
          type: DioExceptionType.unknown,
          error: '所有 PROPFIND 兼容请求均失败',
        );
  }

  List<String> _parseFileNames(String xml, String requestedPath) {
    final document = XmlDocument.parse(xml);
    final normalizedRequestedPath = _normalizePath(requestedPath);
    final names = <String>[];
    for (final response in document.descendants.whereType<XmlElement>().where(
          (element) => element.name.local.toLowerCase() == 'response',
        )) {
      final descendants = response.descendants.whereType<XmlElement>();
      final hrefElement = descendants.cast<XmlElement?>().firstWhere(
            (element) => element?.name.local.toLowerCase() == 'href',
            orElse: () => null,
          );
      if (hrefElement == null) continue;
      final hrefPath = Uri.tryParse(hrefElement.innerText.trim())?.path ??
          hrefElement.innerText.trim();
      final normalizedHref = _normalizePath(hrefPath);
      if (normalizedHref == normalizedRequestedPath ||
          normalizedHref.endsWith(normalizedRequestedPath)) {
        continue;
      }
      final isDirectory = descendants.any(
        (element) => element.name.local.toLowerCase() == 'collection',
      );
      if (isDirectory) continue;

      final segments = hrefPath.split('/').where((part) => part.isNotEmpty);
      if (segments.isEmpty) continue;
      final encodedName = segments.last;
      String name;
      try {
        name = Uri.decodeComponent(encodedName);
      } catch (_) {
        name = encodedName;
      }
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    return names;
  }

  String _asDirectoryPath(String path) => path.endsWith('/') ? path : '$path/';

  String _joinPath(String directory, String name) =>
      '${directory.endsWith('/') ? directory.substring(0, directory.length - 1) : directory}/$name';

  String _normalizePath(String path) {
    final decoded = Uri.decodeFull(path);
    return decoded.length > 1 && decoded.endsWith('/')
        ? decoded.substring(0, decoded.length - 1)
        : decoded;
  }

  Future<Uint8List> _readDirect(String path) async {
    _throwIfRateLimited(path);
    final response = await _client.c.req<dynamic>(
      _client,
      'GET',
      path,
      optionsHandler: (options) => options.responseType = ResponseType.bytes,
    );
    if (response.statusCode != 200) {
      final error = _responseError(response);
      if (_isProviderRateLimit(error)) _recordRateLimit();
      throw error;
    }
    final data = response.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      error: 'WebDAV GET 返回了非二进制响应',
    );
  }

  Future<void> _writeDirect(String path, Uint8List bytes) async {
    _throwIfRateLimited(path);
    final response = await _client.c.req<dynamic>(
      _client,
      'PUT',
      path,
      data: bytes,
      optionsHandler: (options) {
        options.headers?['content-length'] = bytes.length;
        options.headers?['content-type'] = 'application/octet-stream';
      },
    );
    if (!const {200, 201, 204}.contains(response.statusCode)) {
      final error = _responseError(response);
      if (_isProviderRateLimit(error)) _recordRateLimit();
      throw error;
    }
  }

  Future<void> _deleteDirect(String path) async {
    _throwIfRateLimited(path);
    final response = await _client.c.req<dynamic>(_client, 'DELETE', path);
    if (!const {200, 202, 204, 404}.contains(response.statusCode)) {
      final error = _responseError(response);
      if (_isProviderRateLimit(error)) _recordRateLimit();
      throw error;
    }
  }

  DioException _responseError(Response<dynamic> response) => DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: response.statusMessage,
      );

  Future<T> _runWithRetry<T>({
    required String operation,
    required String path,
    required Future<T> Function() request,
  }) async {
    DioException? lastError;
    for (var attempt = 1; attempt <= _maximumAttempts; attempt++) {
      try {
        return await request();
      } on DioException catch (error) {
        lastError = error;
        if (_isProviderRateLimit(error)) _recordRateLimit();
        if (!_isRetryable(error) || attempt == _maximumAttempts) {
          throw _readableException(operation, path, error);
        }
        debugPrint(
          'WebDAV $operation收到临时错误 '
          '(HTTP ${error.response?.statusCode ?? 'unknown'})，'
          '将在第 ${attempt + 1} 次尝试中重试',
        );
        await Future<void>.delayed(
          Duration(milliseconds: 600 * attempt * attempt),
        );
      }
    }
    throw _readableException(operation, path, lastError!);
  }

  bool _isRetryable(DioException error) {
    if (_isProviderRateLimit(error)) return false;
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return const {408, 425, 429, 500, 502, 503, 504}.contains(statusCode);
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError =>
        true,
      _ => false,
    };
  }

  WebDavSyncException _readableException(
    String operation,
    String path,
    DioException error,
  ) {
    final statusCode = error.response?.statusCode;
    final message = switch (statusCode) {
      401 => '身份验证失败，请检查用户名和密码',
      403 => '服务器拒绝访问，请检查账号和目录权限',
      404 => '远端路径不存在',
      429 => '服务器请求过于频繁，请稍后重试',
      503 when _isProviderRateLimit(error) =>
        '坚果云已因请求过于频繁临时限制该账号，请至少等待 30 分钟后重试',
      502 || 503 || 504 => '服务器暂时不可用，请稍后重试',
      _
          when error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout =>
        '连接服务器超时，请检查网络或服务器地址',
      _ when error.type == DioExceptionType.connectionError =>
        '无法连接服务器，请检查网络、地址和 TLS 证书',
      _ => _responseDetail(error),
    };
    return WebDavSyncException(
      operation: operation,
      path: path,
      statusCode: statusCode,
      message: message,
    );
  }

  String _responseDetail(DioException error) {
    final statusMessage = error.response?.statusMessage?.trim();
    if (statusMessage != null && statusMessage.isNotEmpty) {
      return statusMessage;
    }
    final detail = error.message?.trim();
    if (detail != null && detail.isNotEmpty) return detail;
    return '服务器返回了无法识别的响应';
  }

  bool _isProviderRateLimit(DioException error) {
    if (error.response?.statusCode != 503) return false;
    final data = error.response?.data;
    final body = switch (data) {
      String value => value,
      Uint8List value => utf8.decode(value, allowMalformed: true),
      List<int> value => utf8.decode(value, allowMalformed: true),
      _ => data?.toString() ?? '',
    };
    final normalized = body.toLowerCase();
    return normalized.contains('blockedtemporarily') ||
        normalized.contains('too many requests are received recently');
  }

  void _recordRateLimit() {
    _rateLimitedUntilByServer[_client.uri] =
        DateTime.now().add(_providerRateLimitCooldown);
  }

  void _throwIfRateLimited(String path) {
    final until = _rateLimitedUntilByServer[_client.uri];
    if (until == null || !DateTime.now().isBefore(until)) return;
    throw DioException(
      requestOptions: RequestOptions(path: path),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        statusCode: 503,
        data: 'BlockedTemporarily: Too many requests are received recently',
      ),
      type: DioExceptionType.badResponse,
      error: 'BlockedTemporarily: Too many requests are received recently',
    );
  }
}

class _PropfindVariant {
  const _PropfindVariant({
    required this.contentType,
    required this.includeBody,
  });

  final String contentType;
  final bool includeBody;
}
