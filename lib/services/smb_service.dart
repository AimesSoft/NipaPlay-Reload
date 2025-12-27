import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smb_connect/smb_connect.dart';

import 'package:nipaplay/services/smb2_native_service.dart';

class SMBConnection {
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final String domain;
  final bool isConnected;

  const SMBConnection({
    required this.name,
    required this.host,
    this.port = 445,
    required this.username,
    required this.password,
    this.domain = '',
    this.isConnected = false,
  });

  SMBConnection copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? domain,
    bool? isConnected,
  }) {
    return SMBConnection(
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'domain': domain,
      'isConnected': isConnected,
    };
  }

  factory SMBConnection.fromJson(Map<String, dynamic> json) {
    return SMBConnection(
      name: json['name'] ?? '',
      host: json['host'] ?? '',
      port: json['port'] is int
          ? json['port'] as int
          : int.tryParse(json['port']?.toString() ?? '') ?? 445,
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      domain: json['domain'] ?? '',
      isConnected: json['isConnected'] ?? false,
    );
  }
}

class SMBFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final bool isShare;

  const SMBFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.isShare = false,
  });
}

class SMBService {
  static const String _connectionsKey = 'smb_connections';
  static const Set<String> _videoExtensions = {
    '264',
    '265',
    '3g2',
    'mp4',
    'mp4v',
    'mkv',
    'mk3d',
    'avi',
    'divx',
    'mov',
    'qt',
    'wmv',
    'asf',
    'flv',
    'f4v',
    'webm',
    'm4v',
    'ts',
    'trp',
    'tp',
    'm2t',
    'm2ts',
    'mts',
    'mpg',
    'mpeg',
    'mpe',
    'm2p',
    'm2v',
    'm1v',
    'mpv',
    'mp2v',
    '3gp',
    '3gpp',
    'amv',
    'rmvb',
    'rm',
    'ogv',
    'ogm',
    'ogx',
    'ivf',
    'mjpg',
    'mjpeg',
    'h264',
    'h265',
    'hevc',
    'avc',
    'mxf',
    'gxf',
    'drc',
    'dvr-ms',
    'wtv',
    'nut',
    'nsv',
    'fli',
    'flc',
    'roq',
    'bik',
    'smk',
    'tod',
    'dv',
    'vob',
    'y4m',
    'yuv',
  };
  static const Set<String> _playlistExtensions = {
    'm3u8',
    'm3u',
    'pls',
  };

  SMBService._();
  static final SMBService instance = SMBService._();

  final List<SMBConnection> _connections = [];

  List<SMBConnection> get connections => List.unmodifiable(_connections);

  Future<void> initialize() async {
    await _loadConnections();
  }

  Future<void> _loadConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_connectionsKey);
      if (savedJson == null) return;
      final List<dynamic> decoded = json.decode(savedJson);
      _connections
        ..clear()
        ..addAll(decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => _normalizeConnection(SMBConnection.fromJson(e))));
    } catch (e) {
      print('加载SMB连接失败: $e');
    }
  }

  Future<void> _saveConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _connectionsKey,
        json.encode(_connections.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      print('保存SMB连接失败: $e');
    }
  }

  Future<bool> addConnection(SMBConnection connection) async {
    final normalized = _normalizeConnection(connection);
    final success = await _testConnection(normalized);
    if (success) {
      _connections.add(normalized.copyWith(isConnected: true));
      await _saveConnections();
    }
    return success;
  }

  Future<bool> updateConnection(
    String originalName,
    SMBConnection updatedConnection,
  ) async {
    final normalized = _normalizeConnection(updatedConnection);
    final success = await _testConnection(normalized);
    if (!success) {
      return false;
    }

    final index = _connections.indexWhere((conn) => conn.name == originalName);
    if (index == -1) {
      _connections.add(normalized.copyWith(isConnected: true));
    } else {
      _connections[index] = normalized.copyWith(isConnected: true);
    }
    await _saveConnections();
    return true;
  }

  Future<void> removeConnection(String name) async {
    _connections.removeWhere((conn) => conn.name == name);
    await _saveConnections();
  }

  Future<void> updateConnectionStatus(String name) async {
    final index = _connections.indexWhere((conn) => conn.name == name);
    if (index == -1) return;
    final normalized = _connections[index];
    final success = await _testConnection(normalized);
    _connections[index] = normalized.copyWith(isConnected: success);
    await _saveConnections();
  }

  SMBConnection? getConnection(String name) {
    try {
      return _connections.firstWhere((element) => element.name == name);
    } catch (_) {
      return null;
    }
  }

  Future<List<SMBFileEntry>> listDirectory(
    SMBConnection connection,
    String path,
  ) async {
    final normalizedConnection = _normalizeConnection(connection);

    if (Smb2NativeService.instance.isSupported) {
      try {
        final files = await Smb2NativeService.instance.listDirectory(
          normalizedConnection,
          path,
        );
        return files
            .where((entry) => entry.isDirectory || isPlayableFile(entry.name))
            .toList();
      } catch (e) {
        debugPrint('libsmb2 列目录失败，回退 smb_connect: $e');
      }
    }

    final client = await _createClient(normalizedConnection);
    try {
      if (path.isEmpty || path == '/' || path == '\\') {
        final shares = await client.listShares();
        return shares
            .where((share) => share.isDirectory())
            .map(
              (share) => SMBFileEntry(
                name: share.name,
                path: _normalizePath(share.path),
                isDirectory: true,
                isShare: true,
              ),
            )
            .toList();
      }

      final normalizedPath = _normalizePath(path);
      final directoryFile =
          await client.file(normalizedPath.endsWith('/') ? normalizedPath : '$normalizedPath/');
      final files = await client.listFiles(directoryFile);

      return files
          .map(
            (file) => SMBFileEntry(
              name: file.name,
              path: _normalizePath(file.path),
              isDirectory: file.isDirectory(),
              size: file.size > 0 ? file.size : null,
            ),
          )
          .where((entry) => entry.isDirectory || isPlayableFile(entry.name))
          .toList();
    } finally {
      await client.close();
    }
  }

  Future<bool> _testConnection(SMBConnection connection) async {
    if (Smb2NativeService.instance.isSupported) {
      try {
        await Smb2NativeService.instance.listDirectory(connection, '/');
        return true;
      } catch (e) {
        print('测试SMB连接失败(libsmb2): $e');
        return false;
      }
    }

    SmbConnect? client;
    try {
      client = await _createClient(connection);
      await client.listShares();
      return true;
    } catch (e) {
      print('测试SMB连接失败: $e');
      return false;
    } finally {
      await client?.close();
    }
  }

  Future<SmbConnect> _createClient(SMBConnection connection) {
    return SmbConnect.connectAuth(
      host: connection.host,
      username: connection.username,
      password: connection.password,
      domain: connection.domain,
      debugPrint: false,
    );
  }

  SMBConnection _normalizeConnection(SMBConnection connection) {
    var trimmedHost = connection.host.trim();
    var port = connection.port;
    final parsedHostPort = _tryParseHostPort(trimmedHost);
    if (parsedHostPort != null) {
      trimmedHost = parsedHostPort.$1;
      port = parsedHostPort.$2;
    }
    if (port <= 0 || port > 65535) {
      port = 445;
    }
    final normalizedName =
        connection.name.trim().isEmpty ? trimmedHost : connection.name.trim();
    return connection.copyWith(
      name: normalizedName,
      host: trimmedHost,
      port: port,
      username: connection.username.trim(),
      password: connection.password,
      domain: connection.domain.trim(),
    );
  }

  (String, int)? _tryParseHostPort(String rawHost) {
    final trimmed = rawHost.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    // Bracketed IPv6: [fe80::1]:445
    final bracketMatch = RegExp(r'^\[([^\]]+)\]:(\d{1,5})$').firstMatch(trimmed);
    if (bracketMatch != null) {
      final host = bracketMatch.group(1) ?? '';
      final port = int.tryParse(bracketMatch.group(2) ?? '');
      if (host.isNotEmpty && port != null) {
        return (host, port);
      }
      return null;
    }

    // IPv4/hostname: host:445 (avoid parsing plain IPv6)
    final parts = trimmed.split(':');
    if (parts.length != 2) {
      return null;
    }
    final host = parts.first.trim();
    final port = int.tryParse(parts.last.trim());
    if (host.isEmpty || port == null) {
      return null;
    }
    return (host, port);
  }

  String buildFileUrl(SMBConnection connection, String smbPath) {
    final normalized = _normalizeConnection(connection);
    final normalizedPath = _normalizePath(smbPath);
    final encodedSegments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');

    final hasAuth =
        normalized.username.isNotEmpty || normalized.password.isNotEmpty;
    final uri = Uri(
      scheme: 'smb',
      host: normalized.host,
      port: normalized.port,
      path: '/$encodedSegments',
      userInfo: hasAuth
          ? '${Uri.encodeComponent(normalized.username)}:${Uri.encodeComponent(normalized.password)}'
          : null,
    );
    return uri.toString();
  }

  String _normalizePath(String rawPath) {
    if (rawPath.isEmpty) {
      return '/';
    }
    var normalized = rawPath.replaceAll('\\', '/');
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    // Remove duplicated slashes
    normalized = normalized.replaceAll(RegExp(r'/{2,}'), '/');
    return normalized;
  }

  bool isVideoFile(String filename) {
    final name = filename.toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return false;
    }
    final extension = name.substring(dotIndex + 1);
    if (_videoExtensions.contains(extension)) {
      return true;
    }
    const urlLikeExtensions = {
      'com',
      'cn',
      'org',
      'net',
      'me',
      'cc',
      'tv',
      'co',
      'xyz',
    };
    return urlLikeExtensions.contains(extension);
  }

  bool isPlayableFile(String filename) {
    final lower = filename.toLowerCase();
    final dotIndex = lower.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == lower.length - 1) {
      return false;
    }
    final extension = lower.substring(dotIndex + 1);
    if (_playlistExtensions.contains(extension)) {
      return true;
    }
    return isVideoFile(filename);
  }
}
