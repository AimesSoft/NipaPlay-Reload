import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class SingleInstanceMessage {
  final bool focus;
  final String? filePath;

  const SingleInstanceMessage({
    this.focus = false,
    this.filePath,
  });
}

typedef SingleInstanceMessageHandler = FutureOr<void> Function(
  SingleInstanceMessage message,
);

class SingleInstanceService {
  static const String _appId = 'nipaplay';
  static const int _protocolVersion = 1;
  static const String _lockFileName = 'nipaplay_instance.lock';
  static const String _infoFileName = 'nipaplay_instance.json';
  static const Duration _connectTimeout = Duration(milliseconds: 300);
  static const Duration _retryDelay = Duration(milliseconds: 150);
  static const int _maxNotifyAttempts = 6;

  // ignore: unused_field
  static RandomAccessFile? _lockFile;
  // ignore: unused_field
  static ServerSocket? _server;
  static String? _token;
  static SingleInstanceMessageHandler? _handler;
  static final List<SingleInstanceMessage> _pendingMessages = [];

  static Future<bool> ensureSingleInstance({
    String? launchFilePath,
  }) async {
    if (kIsWeb) {
      return true;
    }

    final lockPath = _lockFilePath();
    final infoPath = _infoFilePath();

    final lockHandle = await File(lockPath).open(mode: FileMode.append);
    try {
      await lockHandle.lock(FileLock.exclusive);
      _lockFile = lockHandle;
      await _startServer(infoPath);
      return true;
    } on FileSystemException {
      await lockHandle.close();
      await _notifyExistingInstance(infoPath, launchFilePath);
      return false;
    } catch (e) {
      await lockHandle.close();
      debugPrint('[SingleInstance] Failed to create lock: $e');
      return true;
    }
  }

  static void registerMessageHandler(SingleInstanceMessageHandler handler) {
    _handler = handler;
    if (_pendingMessages.isEmpty) {
      return;
    }
    final pending = List<SingleInstanceMessage>.from(_pendingMessages);
    _pendingMessages.clear();
    for (final message in pending) {
      unawaited(_dispatch(message));
    }
  }

  static Future<void> _startServer(String infoPath) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _token = _generateToken();
    final info = <String, dynamic>{
      'app': _appId,
      'version': _protocolVersion,
      'port': server.port,
      'token': _token,
      'pid': pid,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await File(infoPath).writeAsString(jsonEncode(info), flush: true);

    server.listen(
      (socket) => unawaited(_handleClient(socket)),
      onError: (error) {
        debugPrint('[SingleInstance] Listen failed: $error');
      },
    );
  }

  static Future<void> _handleClient(Socket socket) async {
    try {
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(_connectTimeout);
      final message = _parseMessage(line);
      if (message == null) {
        socket.writeln('INVALID');
        return;
      }
      unawaited(_dispatch(message));
      socket.writeln('OK');
    } catch (e) {
      debugPrint('[SingleInstance] Failed to handle request: $e');
    } finally {
      try {
        await socket.flush();
      } catch (_) {}
      await socket.close();
    }
  }

  static SingleInstanceMessage? _parseMessage(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['app'] != _appId ||
          decoded['version'] != _protocolVersion ||
          decoded['token'] != _token) {
        return null;
      }
      final focus = decoded['focus'] == true;
      final filePath = decoded['filePath'];
      return SingleInstanceMessage(
        focus: focus,
        filePath: filePath is String && filePath.isNotEmpty ? filePath : null,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _dispatch(SingleInstanceMessage message) async {
    final handler = _handler;
    if (handler == null) {
      _pendingMessages.add(message);
      return;
    }
    await handler(message);
  }

  static Future<void> _notifyExistingInstance(
    String infoPath,
    String? launchFilePath,
  ) async {
    for (var attempt = 0; attempt < _maxNotifyAttempts; attempt++) {
      final info = await _readInfo(infoPath);
      if (info == null) {
        await Future.delayed(_retryDelay);
        continue;
      }
      final ok = await _sendMessage(
        info.port,
        info.token,
        launchFilePath,
      );
      if (ok) {
        return;
      }
      await Future.delayed(_retryDelay);
    }
  }

  static Future<_InstanceInfo?> _readInfo(String infoPath) async {
    try {
      final content = await File(infoPath).readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['app'] != _appId ||
          decoded['version'] != _protocolVersion) {
        return null;
      }
      final portValue = decoded['port'];
      final tokenValue = decoded['token'];
      if (portValue is! num || tokenValue is! String) {
        return null;
      }
      final port = portValue.toInt();
      if (port <= 0 || port > 65535) {
        return null;
      }
      return _InstanceInfo(
        port: port,
        token: tokenValue,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _sendMessage(
    int port,
    String token,
    String? launchFilePath,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: _connectTimeout,
      );
      final payload = <String, dynamic>{
        'app': _appId,
        'version': _protocolVersion,
        'token': token,
        'focus': true,
        'filePath': launchFilePath,
      };
      socket.writeln(jsonEncode(payload));
      final response = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(_connectTimeout);
      return response.trim() == 'OK';
    } catch (_) {
      return false;
    } finally {
      if (socket != null) {
        try {
          await socket.flush();
        } catch (_) {}
        await socket.close();
      }
    }
  }

  static String _lockFilePath() {
    final root = Directory.systemTemp.path;
    return path.join(root, _lockFileName);
  }

  static String _infoFilePath() {
    final root = Directory.systemTemp.path;
    return path.join(root, _infoFileName);
  }

  static String _generateToken() {
    return '$pid-${DateTime.now().microsecondsSinceEpoch}';
  }
}

class _InstanceInfo {
  final int port;
  final String token;

  const _InstanceInfo({
    required this.port,
    required this.token,
  });
}
