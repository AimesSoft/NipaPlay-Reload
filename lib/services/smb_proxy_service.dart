import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:smb_connect/smb_connect.dart';

import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/smb2_native_service.dart';

class SMBProxyService {
  static const String _portKey = 'smb_proxy_port';
  static const int _defaultPort = 33221;

  SMBProxyService._();

  static final SMBProxyService instance = SMBProxyService._();

  HttpServer? _server;
  int _port = 0;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int get port => _port;

  Future<void>? _initializing;

  Future<void> initialize() async {
    if (kIsWeb) return;
    final pending = _initializing ??= _initialize();
    try {
      await pending;
    } finally {
      if (identical(_initializing, pending)) _initializing = null;
    }
  }

  /// 回前台自愈入口：仅在代理自认运行中时校验端口并就地重启，
  /// 不负责把从未启动过的代理拉起。
  Future<void> ensureAliveIfRunning() async {
    if (kIsWeb || !_isRunning) return;
    await initialize();
  }

  /// 探测本机监听是否真的可连（HTTP GET /health 且返回 ok）。
  ///
  /// iOS 后台挂起会回收 shelf 的监听 socket，而 Dart 侧 `_isRunning` 仍是
  /// true；沿用旧状态会把 `smb://` 解析成已失效的回环端口（Connection
  /// refused）。用 HTTP 探测自己的 health 路由，同时排除端口被占用的场景。
  Future<bool> _listenerAlive() async {
    final port = _port;
    if (port <= 0) return false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final request = await client
          .get(InternetAddress.loopbackIPv4.address, port, '/smb/health')
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200 && body.trim() == 'ok';
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _initialize() async {
    if (kIsWeb) {
      return;
    }
    if (_isRunning && await _listenerAlive()) return;
    if (_isRunning) {
      debugPrint(
        'SMBProxyService: 本地代理端口 $_port 已失效（多为后台挂起被系统回收），'
        '就地重启；优先复用已保存端口，保持已生成 URL 有效',
      );
      await _teardown();
    }

    await SMBService.instance.initialize();

    final router = Router()
      ..add('GET', '/smb/stream', _handleStream)
      ..add('HEAD', '/smb/stream', _handleStreamHead)
      ..get('/smb/health', (Request request) => Response.ok('ok'));

    final handler = const Pipeline().addHandler(router.call);

    final prefs = await SharedPreferences.getInstance();
    final savedPort = prefs.getInt(_portKey);

    final portsToTry = <int>[];
    void addPort(int? value) {
      if (value == null) return;
      if (portsToTry.contains(value)) return;
      portsToTry.add(value);
    }

    addPort(savedPort);
    addPort(_defaultPort);
    addPort(0);

    Object? lastError;
    for (final candidatePort in portsToTry) {
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.loopbackIPv4,
          candidatePort,
        );
        _port = _server!.port;
        _isRunning = true;
        try {
          await prefs.setInt(_portKey, _port);
        } catch (error) {
          debugPrint('SMB proxy port preference could not be saved: $error');
        }
        return;
      } catch (e) {
        lastError = e;
      }
    }

    throw StateError('SMBProxyService failed to start: $lastError');
  }

  Future<void> stop() async {
    await _initializing;
    await _teardown();
  }

  Future<void> _teardown() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _port = 0;
    _isRunning = false;
  }

  /// 测试专用：只关闭底层监听 socket，保留“运行中”状态标记，
  /// 复现 iOS 后台挂起回收端口后的现场（状态仍是运行中，端口不可连）。
  @visibleForTesting
  Future<void> simulateListenerReclaimedForTest() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }

  String buildStreamUrl(SMBConnection connection, String smbPath) {
    if (!_isRunning)
      throw StateError(
          'SMB proxy must be initialized before building a stream URL');
    final normalizedConnection =
        SMBService.instance.getConnection(connection.name) ?? connection;
    final connName = normalizedConnection.name.trim();
    final normalizedPath = _normalizeSmbPath(smbPath);

    final resolvedPort = _port > 0 ? _port : _defaultPort;
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: resolvedPort,
      path: '/smb/stream',
      queryParameters: {
        'conn': connName,
        'path': normalizedPath,
      },
    ).toString();
  }

  Future<Response> _handleStream(Request request) {
    return _handleStreamInternal(request, headOnly: false);
  }

  Future<Response> _handleStreamHead(Request request) {
    return _handleStreamInternal(request, headOnly: true);
  }

  Future<Response> _handleStreamInternal(
    Request request, {
    required bool headOnly,
  }) async {
    final connName = request.url.queryParameters['conn']?.trim();
    final rawPath = request.url.queryParameters['path']?.trim();
    if (connName == null ||
        connName.isEmpty ||
        rawPath == null ||
        rawPath.isEmpty) {
      return Response(HttpStatus.badRequest, body: 'Missing conn or path');
    }

    final resolved = SMBService.instance.getConnection(connName);
    if (resolved == null) {
      return Response(HttpStatus.notFound, body: 'SMB connection not found');
    }
    final connection = SMBService.instance.effectiveConnection(resolved);

    final smbPath = _stripTrailingSlash(_normalizeSmbPath(rawPath));

    if (Smb2NativeService.instance.isSupported) {
      try {
        final stat = await Smb2NativeService.instance.stat(connection, smbPath);
        if (stat.isDirectory) {
          return Response(HttpStatus.badRequest, body: 'Path is a directory');
        }

        final totalLength = stat.size;
        final contentType = _determineContentType(p.basename(smbPath));

        final rangeHeader = request.headers['range'];
        if (rangeHeader != null) {
          final range = _parseRangeHeader(rangeHeader, totalLength);
          if (range == null) {
            return Response(
              HttpStatus.requestedRangeNotSatisfiable,
              headers: {
                'Content-Range': 'bytes */$totalLength',
              },
            );
          }

          final start = range.start;
          final endExclusive = range.endExclusive;
          final endInclusive = endExclusive - 1;
          final chunkSize = endExclusive - start;

          final headers = <String, String>{
            'Content-Type': contentType,
            'Content-Length': '$chunkSize',
            'Accept-Ranges': 'bytes',
            'Content-Range': 'bytes $start-$endInclusive/$totalLength',
            'Cache-Control': 'no-cache',
          };

          if (headOnly) {
            return Response(HttpStatus.partialContent, headers: headers);
          }

          final stream = Smb2NativeService.instance.openReadStream(
            connection,
            smbPath,
            start: start,
            endExclusive: endExclusive,
          );

          return Response(
            HttpStatus.partialContent,
            body: stream,
            headers: headers,
          );
        }

        final headers = <String, String>{
          'Content-Type': contentType,
          'Content-Length': '$totalLength',
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'no-cache',
        };

        if (headOnly) {
          return Response(HttpStatus.ok, headers: headers);
        }

        final stream = Smb2NativeService.instance.openReadStream(
          connection,
          smbPath,
          start: 0,
          endExclusive: totalLength,
        );

        return Response.ok(
          stream,
          headers: headers,
        );
      } catch (e) {
        return Response.internalServerError(body: 'SMB stream error: $e');
      }
    }

    SmbConnect? client;
    try {
      client = await SmbConnect.connectAuth(
        host: connection.host,
        username: connection.username,
        password: connection.password,
        domain: connection.domain,
        debugPrint: false,
      );

      final smbFile = await client.file(smbPath);
      if (!smbFile.isExists) {
        await client.close();
        return Response.notFound('File not found');
      }
      if (smbFile.isDirectory()) {
        await client.close();
        return Response(HttpStatus.badRequest, body: 'Path is a directory');
      }

      final totalLength = smbFile.size;
      final contentType = _determineContentType(smbFile.name);

      final rangeHeader = request.headers['range'];
      if (rangeHeader != null) {
        final range = _parseRangeHeader(rangeHeader, totalLength);
        if (range == null) {
          await client.close();
          return Response(
            HttpStatus.requestedRangeNotSatisfiable,
            headers: {
              'Content-Range': 'bytes */$totalLength',
            },
          );
        }

        final start = range.start;
        final endExclusive = range.endExclusive;
        final endInclusive = endExclusive - 1;
        final chunkSize = endExclusive - start;

        final headers = <String, String>{
          'Content-Type': contentType,
          'Content-Length': '$chunkSize',
          'Accept-Ranges': 'bytes',
          'Content-Range': 'bytes $start-$endInclusive/$totalLength',
          'Cache-Control': 'no-cache',
        };

        if (headOnly) {
          await client.close();
          return Response(HttpStatus.partialContent, headers: headers);
        }

        final smbStream = await client.openRead(smbFile, start, endExclusive);
        final stream = _wrapStreamAndCloseClient(client, smbStream);
        client = null;

        return Response(
          HttpStatus.partialContent,
          body: stream,
          headers: headers,
        );
      }

      final headers = <String, String>{
        'Content-Type': contentType,
        'Content-Length': '$totalLength',
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
      };

      if (headOnly) {
        await client.close();
        return Response(HttpStatus.ok, headers: headers);
      }

      final smbStream = await client.openRead(smbFile);
      final stream = _wrapStreamAndCloseClient(client, smbStream);
      client = null;

      return Response.ok(
        stream,
        headers: headers,
      );
    } catch (e) {
      return Response.internalServerError(body: 'SMB stream error: $e');
    } finally {
      if (client != null) {
        try {
          await client.close();
        } catch (_) {
          // ignore
        }
      }
    }
  }

  Stream<List<int>> _wrapStreamAndCloseClient(
    SmbConnect client,
    Stream<Uint8List> smbStream,
  ) async* {
    try {
      await for (final chunk in smbStream) {
        yield chunk;
      }
    } finally {
      try {
        await client.close();
      } catch (_) {
        // ignore
      }
    }
  }

  String _normalizeSmbPath(String rawPath) {
    if (rawPath.isEmpty) {
      return '/';
    }
    var normalized = rawPath.replaceAll('\\', '/');
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    normalized = normalized.replaceAll(RegExp(r'/{2,}'), '/');
    return normalized;
  }

  String _stripTrailingSlash(String value) {
    if (value.length <= 1) {
      return value;
    }
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  String _determineContentType(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.mp4':
      case '.m4v':
        return 'video/mp4';
      case '.mkv':
        return 'video/x-matroska';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      case '.flv':
        return 'video/x-flv';
      case '.ts':
      case '.mpeg':
      case '.mpg':
        return 'video/mpeg';
      case '.webm':
        return 'video/webm';
      default:
        return 'application/octet-stream';
    }
  }

  _HttpRange? _parseRangeHeader(String rangeHeader, int totalLength) {
    if (totalLength <= 0) {
      return null;
    }
    if (!rangeHeader.startsWith('bytes=')) {
      return null;
    }

    final rangeSpec = rangeHeader.substring('bytes='.length);
    final firstRange = rangeSpec.split(',').first.trim();
    final match = RegExp(r'^(\d*)-(\d*)$').firstMatch(firstRange);
    if (match == null) {
      return null;
    }

    final startStr = match.group(1) ?? '';
    final endStr = match.group(2) ?? '';
    if (startStr.isEmpty && endStr.isEmpty) {
      return null;
    }

    int start;
    int endInclusive;

    if (startStr.isEmpty) {
      final suffixLength = int.tryParse(endStr);
      if (suffixLength == null || suffixLength <= 0) {
        return null;
      }
      if (suffixLength >= totalLength) {
        start = 0;
      } else {
        start = totalLength - suffixLength;
      }
      endInclusive = totalLength - 1;
    } else {
      start = int.tryParse(startStr) ?? -1;
      if (start < 0 || start >= totalLength) {
        return null;
      }

      if (endStr.isEmpty) {
        endInclusive = totalLength - 1;
      } else {
        endInclusive = int.tryParse(endStr) ?? -1;
        if (endInclusive < start) {
          return null;
        }
        if (endInclusive >= totalLength) {
          endInclusive = totalLength - 1;
        }
      }
    }

    final endExclusive = endInclusive + 1;
    return _HttpRange(start: start, endExclusive: endExclusive);
  }
}

class _HttpRange {
  final int start;
  final int endExclusive;

  const _HttpRange({
    required this.start,
    required this.endExclusive,
  });
}
