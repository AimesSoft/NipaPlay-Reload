import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/stored_credential.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/credential_authority.dart';
import 'dart:convert';
import '../next/state/change_history.dart';
import 'address_probe.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smb_connect/smb_connect.dart';
import 'package:uuid/uuid.dart';

import 'package:nipaplay/services/process_memory_cache.dart';
import 'package:nipaplay/services/smb2_native_service.dart';
import 'package:nipaplay/utils/network_address_utils.dart';

class SMBConnection {
  final String id;
  final String name;

  /// 内网主机（原 `host` 字段）。可为空——内网与公网至少填一个。
  final String host;
  final int port;

  /// 公网主机。可为空——内网与公网至少填一个。
  final String wanHost;
  final int wanPort;
  final String username;
  final String? credentialOrigin;
  String get credentialAuthority => credentialAuthorityOf([
        if (host.trim().isNotEmpty) 'smb://${host.toLowerCase()}:$port',
        if (wanHost.trim().isNotEmpty) 'smb://${wanHost.toLowerCase()}:$wanPort',
      ]);
  final StoredCredential _password;
  String get password => _password.value ?? '';
  Future<bool> hasPassword() => _password.exists();
  bool get passwordIsResolved => _password.ref == null || _password.value != null;
  StoredCredential? retainPassword(String edited, {required String original}) =>
      edited == original ? _password : null;
  Future<void> resolvePassword() async {
    if (!credentialAuthorityCovers(credentialOrigin, credentialAuthority)) {
      throw StateError('credential_origin_changed');
    }
    await _password.resolve();
  }
  final String domain;
  final bool isConnected;

  SMBConnection({
    String? id,
    required this.name,
    required this.host,
    this.port = 445,
    this.wanHost = '',
    this.wanPort = 445,
    required this.username,
    required String password,
    StoredCredential? storedPassword,
    this.credentialOrigin,
    this.domain = '',
    this.isConnected = false,
  }) : _password = storedPassword ?? StoredCredential(password),
       id = id?.trim().isNotEmpty == true ? id!.trim() : const Uuid().v4();

  SMBConnection copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? wanHost,
    int? wanPort,
    String? username,
    String? password,
    String? domain,
    bool? isConnected,
    String? credentialOrigin,
  }) {
    return SMBConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      wanHost: wanHost ?? this.wanHost,
      wanPort: wanPort ?? this.wanPort,
      username: username ?? this.username,
      password: password ?? this.password,
      storedPassword: password == null ? _password : null,
      domain: domain ?? this.domain,
      isConnected: isConnected ?? this.isConnected,
      credentialOrigin: credentialOrigin ?? this.credentialOrigin,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'wanHost': wanHost,
      'wanPort': wanPort,
      'username': username,
      'password': _password.toJson(),
      'domain': domain,
      'isConnected': isConnected,
      if (credentialOrigin != null) 'credentialOrigin': credentialOrigin,
    };
  }

  factory SMBConnection.fromJson(Map<String, dynamic> json) {
    final savedId = json['id']?.toString().trim();
    final rawHost = (json['host'] ?? '').toString();
    final rawPort = json['port'] is int
        ? json['port'] as int
        : int.tryParse(json['port']?.toString() ?? '') ?? 445;
    final hasWanKey = json.containsKey('wanHost');

    var host = rawHost;
    var port = rawPort;
    var wanHost = (json['wanHost'] ?? '').toString();
    var wanPort = json['wanPort'] is int
        ? json['wanPort'] as int
        : int.tryParse(json['wanPort']?.toString() ?? '') ?? 445;

    // 旧数据迁移：原本只有单一 `host`/`port`，未记录 `wanHost`。
    // 按私有 IP 自动归类：私有地址保留为内网，其余迁移为公网。
    if (!hasWanKey && rawHost.trim().isNotEmpty) {
      if (NetworkAddressUtils.isPrivateHost(rawHost)) {
        host = rawHost;
        port = rawPort;
        wanHost = '';
        wanPort = 445;
      } else {
        host = '';
        port = 445;
        wanHost = rawHost;
        wanPort = rawPort;
      }
    }

    // 纯公网连接（host 为空）把公网地址纳入 id 种子，避免同用户名的不同
    // 公网连接派生出相同 id，导致按 id 解析媒体路径时错配到另一个连接。
    // 旧数据 host 恒非空，沿用原种子保证升级后 id 不变。
    final idSeed = rawHost.trim().isNotEmpty
        ? 'nipaplay:smb:$rawHost|$rawPort|'
              '${json['domain'] ?? ''}|${json['username'] ?? ''}'
        : 'nipaplay:smb:wan:$wanHost|$wanPort|'
              '${json['domain'] ?? ''}|${json['username'] ?? ''}';

    return SMBConnection(
      id: savedId?.isNotEmpty == true
          ? savedId
          : credentialReference(json['password'])?.key ??
          const Uuid().v5(
              '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
              idSeed,
            ),
      name: json['name'] ?? '',
      host: host,
      port: port <= 0 ? 445 : port,
      wanHost: wanHost,
      wanPort: wanPort <= 0 ? 445 : wanPort,
      username: json['username'] ?? '',
      password: '',
      storedPassword: StoredCredential.fromJson(json['password'],
          CredentialStore.itemRef('smb_connections', json)),
      domain: json['domain'] ?? '',
      isConnected: json['isConnected'] ?? false,
      credentialOrigin: json['credentialOrigin'] as String?,
    );
  }

  /// 是否配置了内网地址。
  bool get hasLan => host.trim().isNotEmpty;

  /// 是否配置了公网地址。
  bool get hasWan => wanHost.trim().isNotEmpty;
}

class SMBFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final bool isShare;
  final DateTime? lastModified;

  const SMBFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.isShare = false,
    this.lastModified,
  });
}

typedef _SMBDirectoryCacheKey = ({
  String name,
  String host,
  int port,
  String username,
  String password,
  String domain,
  String path,
});

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

  /// 每个连接当前优先使用的地址。true 表示优先公网，false/缺省表示优先内网。
  final Map<String, bool> _preferWanById = {};

  /// 每个连接最近一次内网/公网地址的连通性检测结果，供库管理界面展示。
  final Map<String, ({bool lan, bool wan})> _addressReachabilityById = {};
  final ProcessMemoryListCache<_SMBDirectoryCacheKey, SMBFileEntry>
      _directoryCache =
      ProcessMemoryListCache<_SMBDirectoryCacheKey, SMBFileEntry>();

  List<SMBConnection> get connections => List.unmodifiable(_connections);

  /// 记录（并供后续读取）某连接优先使用的地址；true 表示优先公网。
  void setPreferredAddress(String connectionId, {required bool useWan}) {
    if (connectionId.trim().isEmpty) return;
    _preferWanById[connectionId] = useWan;
  }

  /// 某连接最近一次内网/公网地址的连通性检测结果。
  ///
  /// 返回 `null` 表示尚未检测过；`lan`/`wan` 分别表示对应地址是否可达。
  ({bool lan, bool wan})? lastAddressReachability(String connectionId) {
    final id = connectionId.trim();
    if (id.isEmpty) return null;
    return _addressReachabilityById[id];
  }

  /// 返回一个已将 `host`/`port` 替换为当前优选地址的连接副本。
  ///
  /// 规则：两个地址都配置时按优选结果选择（缺省优先内网）；只配置一个时
  /// 直接使用该地址；都没有则原样返回。
  SMBConnection effectiveConnection(SMBConnection connection) {
    final normalized = _normalizeConnection(connection);
    final hasLan = normalized.host.trim().isNotEmpty;
    final hasWan = normalized.wanHost.trim().isNotEmpty;
    if (hasLan && hasWan) {
      return (_preferWanById[normalized.id] ?? false)
          ? normalized.copyWith(host: normalized.wanHost, port: normalized.wanPort)
          : normalized;
    }
    if (hasLan) return normalized;
    if (hasWan) {
      return normalized.copyWith(host: normalized.wanHost, port: normalized.wanPort);
    }
    return normalized;
  }

  Future<void> initialize() async {
    await _loadConnections();
    observeChanges(initializing: true);
  }

  void observeChanges({bool initializing = false}) {
    final record = initializing ? BodyChanges.seed : BodyChanges.observe;
    record('source:smb', [
      for (final c in _connections) {
        'id': 'smb:${c.id}', 'type': 'smb', 'name': c.name,
        'url': 'smb://${c.host}:${c.port}', 'username': c.username,
        'connected': c.isConnected,
      }
    ]);
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
      await CredentialStore.instance.write(prefs, _connectionsKey,
        json.encode(_connections.map((e) => e.toJson()).toList()),
      );
      observeChanges();
    } catch (e) {
      print('保存SMB连接失败: $e');
    }
  }

  Future<bool> addConnection(SMBConnection connection) async {
    final normalized = _normalizeConnection(connection);
    final success = await _testAddresses(normalized);
    if (success) {
      _connections.add(normalized.copyWith(isConnected: true));
      clearDirectoryCache(connectionName: normalized.name);
      await _saveConnections();
    }
    return success;
  }

  /// Save configuration before the user supplies a login secret.
  Future<void> configureConnection(SMBConnection connection) async {
    final normalized = _normalizeConnection(connection);
    final index = _connections.indexWhere((item) => item.id == normalized.id);
    final replacement = [..._connections];
    if (index < 0) {
      replacement.add(normalized);
    } else {
      replacement[index] = normalized;
    }
    await CredentialStore.instance.write(
        await SharedPreferences.getInstance(),
        _connectionsKey,
        jsonEncode(replacement.map((e) => e.toJson()).toList()));
    _connections
      ..clear()
      ..addAll(replacement);
    observeChanges();
    clearDirectoryCache();
  }

  Future<void> persistConnections() async {
    await CredentialStore.instance.write(
        await SharedPreferences.getInstance(),
        _connectionsKey,
        jsonEncode(_connections.map((c) => c.toJson()).toList()));
    observeChanges();
  }

  Future<bool> updateConnection(
    String originalName,
    SMBConnection updatedConnection,
  ) async {
    final normalized = _normalizeConnection(updatedConnection);
    final success = await _testAddresses(normalized);
    if (!success) {
      return false;
    }

    final index = _connections.indexWhere((conn) => conn.name == originalName);
    if (index == -1) {
      _connections.add(normalized.copyWith(isConnected: true));
    } else {
      _connections[index] = normalized.copyWith(isConnected: true);
    }
    clearDirectoryCache(connectionName: originalName);
    if (normalized.name != originalName) {
      clearDirectoryCache(connectionName: normalized.name);
    }
    await _saveConnections();
    return true;
  }

  Future<void> removeConnection(String name) async {
    _connections.removeWhere((conn) => conn.name == name);
    clearDirectoryCache(connectionName: name);
    await _saveConnections();
  }

  /// 校验连接的内网/公网地址可达性，并更新优选地址。
  ///
  /// 供启动阶段的后台可达性检测与连接保存流程复用。
  Future<bool> testConnection(SMBConnection connection) {
    return _testAddresses(connection);
  }

  Future<void> updateConnectionStatus(String name) async {
    final index = _connections.indexWhere((conn) => conn.name == name);
    if (index == -1) return;
    final normalized = _connections[index];
    final success = await _testAddresses(normalized);
    _connections[index] = normalized.copyWith(isConnected: success);
    clearDirectoryCache(connectionName: name);
    await _saveConnections();
  }

  /// 分别探测内网与公网地址；只配置一个时只探测该地址，两个都配置时
  /// 并行探测，避免一侧不可达时还要等完它的超时才轮到另一侧。
  ///
  /// 内网可用则优先内网；仅公网可用时才优先公网；都失败则保留内网为默认。
  Future<bool> _testAddresses(SMBConnection connection) async {
    final normalized = _normalizeConnection(connection);
    final hasLan = normalized.host.trim().isNotEmpty;
    final hasWan = normalized.wanHost.trim().isNotEmpty;

    Future<bool> probe(String role, SMBConnection target, String address) async {
      final note = _SmbProbeNote();
      final clock = Stopwatch()..start();
      var ok = false;
      try {
        ok = await _testConnection(target, note);
      } finally {
        AddressProbes.report(AddressProbe(
          sourceId: 'smb:${normalized.id}',
          role: role,
          address: address,
          at: DateTime.now().toUtc(),
          reachable: ok,
          latencyMs: clock.elapsedMilliseconds,
          errorCode: ok ? null : classifyFailure(note.error),
        ));
      }
      return ok;
    }

    final results = await Future.wait([
      hasLan
          ? probe('lan', normalized.copyWith(wanHost: '', wanPort: 445),
              'smb://${normalized.host}:${normalized.port}')
          : Future<bool>.value(false),
      hasWan
          ? probe(
              'wan',
              normalized.copyWith(
                host: normalized.wanHost,
                port: normalized.wanPort,
                wanHost: '',
                wanPort: 445,
              ),
              'smb://${normalized.wanHost}:${normalized.wanPort}')
          : Future<bool>.value(false),
    ]);

    final lanSuccess = results[0];
    final wanSuccess = results[1];

    _preferWanById[normalized.id] = !lanSuccess && wanSuccess;
    _addressReachabilityById[normalized.id] =
        (lan: lanSuccess, wan: wanSuccess);
    return lanSuccess || wanSuccess;
  }

  SMBConnection? getConnection(String name) {
    try {
      return _connections.firstWhere((element) => element.name == name);
    } catch (_) {
      return null;
    }
  }

  SMBConnection? getConnectionByIdOrName(String reference) {
    try {
      return _connections.firstWhere(
        (connection) =>
            connection.id == reference || connection.name == reference,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<SMBFileEntry>> listDirectory(
    SMBConnection connection,
    String path, {
    bool forceRefresh = false,
  }) async {
    final files = await _listDirectoryAllCached(
      connection,
      path,
      forceRefresh: forceRefresh,
    );
    return files
        .where((entry) => entry.isDirectory || isPlayableFile(entry.name))
        .toList();
  }

  Future<List<SMBFileEntry>> listDirectoryAll(
    SMBConnection connection,
    String path, {
    bool forceRefresh = false,
  }) {
    return _listDirectoryAllCached(
      connection,
      path,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<SMBFileEntry>> _listDirectoryAllCached(
    SMBConnection connection,
    String path, {
    bool forceRefresh = false,
  }) async {
    await connection.resolvePassword();
    final normalizedConnection = effectiveConnection(connection);
    final normalizedPath = _normalizePath(path);
    final key = (
      name: normalizedConnection.name,
      host: normalizedConnection.host,
      port: normalizedConnection.port,
      username: normalizedConnection.username,
      password: normalizedConnection.password,
      domain: normalizedConnection.domain,
      path: normalizedPath,
    );
    return _directoryCache.getOrLoad(
      key,
      () => _fetchDirectoryAll(normalizedConnection, normalizedPath),
      forceRefresh: forceRefresh,
    );
  }

  Future<List<SMBFileEntry>> _fetchDirectoryAll(
    SMBConnection normalizedConnection,
    String normalizedPath,
  ) async {
    if (Smb2NativeService.instance.isSupported) {
      try {
        return await Smb2NativeService.instance.listDirectory(
          normalizedConnection,
          normalizedPath,
        );
      } catch (e) {
        debugPrint('libsmb2 列目录失败，回退 smb_connect: $e');
      }
    }

    final client = await _createClient(normalizedConnection);
    try {
      if (normalizedPath == '/') {
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

      final directoryFile = await client.file(
          normalizedPath.endsWith('/') ? normalizedPath : '$normalizedPath/');
      final files = await client.listFiles(directoryFile);

      return files
          .map(
            (file) => SMBFileEntry(
              name: file.name,
              path: _normalizePath(file.path),
              isDirectory: file.isDirectory(),
              size: file.size > 0 ? file.size : null,
              lastModified: file.lastModified == 0
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(file.lastModified,
                      isUtc: true),
            ),
          )
          .toList();
    } finally {
      await client.close();
    }
  }

  void clearDirectoryCache({String? connectionName}) {
    final normalizedName = connectionName?.trim();
    if (normalizedName == null || normalizedName.isEmpty) {
      _directoryCache.clear();
      return;
    }
    _directoryCache.removeWhere((key) => key.name == normalizedName);
  }

  Future<bool> _testConnection(SMBConnection connection,
      [_SmbProbeNote? note]) async {
    try {
      await connection.resolvePassword();
    } catch (e) {
      note?.error = e;
      rethrow;
    }
    if (Smb2NativeService.instance.isSupported) {
      try {
        await Smb2NativeService.instance.listDirectory(connection, '/');
        return true;
      } catch (e) {
        note?.error = e;
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
      note?.error = e;
      print('测试SMB连接失败: $e');
      return false;
    } finally {
      await client?.close();
    }
  }

  Future<SmbConnect> _createClient(SMBConnection connection) async {
    await connection.resolvePassword();
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

    var trimmedWanHost = connection.wanHost.trim();
    var wanPort = connection.wanPort;
    final parsedWanHostPort = _tryParseHostPort(trimmedWanHost);
    if (parsedWanHostPort != null) {
      trimmedWanHost = parsedWanHostPort.$1;
      wanPort = parsedWanHostPort.$2;
    }
    if (wanPort <= 0 || wanPort > 65535) {
      wanPort = 445;
    }

    final fallbackName = trimmedHost.isNotEmpty ? trimmedHost : trimmedWanHost;
    final normalizedName =
        connection.name.trim().isEmpty ? fallbackName : connection.name.trim();
    return connection.copyWith(
      name: normalizedName,
      host: trimmedHost,
      port: port,
      wanHost: trimmedWanHost,
      wanPort: wanPort,
      username: connection.username.trim(),
      domain: connection.domain.trim(),
    );
  }

  (String, int)? _tryParseHostPort(String rawHost) {
    final trimmed = rawHost.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    // Bracketed IPv6: [fe80::1]:445
    final bracketMatch =
        RegExp(r'^\[([^\]]+)\]:(\d{1,5})$').firstMatch(trimmed);
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
    if (!connection.passwordIsResolved) throw StateError('credential_not_loaded');
    final normalized = effectiveConnection(connection);
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

/// Carries the last failure of one address probe back to its caller.
class _SmbProbeNote {
  Object? error;
}
