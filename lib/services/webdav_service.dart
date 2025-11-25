import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:xml/xml.dart';

class WebDAVConnection {
  final String name;
  final String url;
  final String username;
  final String password;
  final bool isConnected;

  WebDAVConnection({
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    this.isConnected = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'username': username,
      'password': password,
      'isConnected': isConnected,
    };
  }

  factory WebDAVConnection.fromJson(Map<String, dynamic> json) {
    return WebDAVConnection(
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      isConnected: json['isConnected'] ?? false,
    );
  }

  WebDAVConnection copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    bool? isConnected,
  }) {
    return WebDAVConnection(
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class WebDAVFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? lastModified;

  WebDAVFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.lastModified,
  });
}

class WebDAVService {
  static const String _connectionsKey = 'webdav_connections';
  static const String _userAgent = 'WebDAVFS/3.0 (NipaPlay)';
  static const int _defaultTimeoutMs = 15000;
  static const String _legacyPropfindRequestBody = '''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:resourcetype/>
  </D:prop>
</D:propfind>''';
  static const List<_PropfindVariant> _propfindVariants = [
    _PropfindVariant(
      depth: '1',
      contentType: 'text/xml; charset="utf-8"',
      includeBody: true,
    ),
    _PropfindVariant(
      depth: '0',
      contentType: 'text/xml; charset="utf-8"',
      includeBody: true,
    ),
    _PropfindVariant(
      depth: '1',
      contentType: 'text/xml; charset="utf-8"',
      includeBody: false,
    ),
    _PropfindVariant(
      depth: '1',
      contentType: 'application/xml',
      includeBody: true,
    ),
    _PropfindVariant(
      depth: '0',
      contentType: 'application/xml',
      includeBody: true,
    ),
  ];
  static const List<String> _commonDavPathSuffixes = [
    '/dav',
    '/dav/',
    '/webdav',
    '/webdav/',
  ];

  static WebDAVService? _instance;

  static WebDAVService get instance {
    _instance ??= WebDAVService._();
    return _instance!;
  }

  WebDAVService._();

  List<WebDAVConnection> _connections = [];

  List<WebDAVConnection> get connections => List.unmodifiable(_connections);

  Future<void> initialize() async {
    await _loadConnections();
  }

  Future<void> _loadConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final connectionsJson = prefs.getString(_connectionsKey);
      if (connectionsJson != null) {
        final List<dynamic> decoded = json.decode(connectionsJson);
        _connections = decoded
            .map((e) => _normalizeConnection(WebDAVConnection.fromJson(e)))
            .toList();
      }
    } catch (e) {
      print('加载WebDAV连接失败: $e');
    }
  }

  Future<void> _saveConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final connectionsJson =
          json.encode(_connections.map((e) => e.toJson()).toList());
      await prefs.setString(_connectionsKey, connectionsJson);
    } catch (e) {
      print('保存WebDAV连接失败: $e');
    }
  }

  Future<bool> addConnection(WebDAVConnection connection) async {
    final normalized = _normalizeConnection(connection);
    try {
      final validated = await _validateConnection(normalized);
      if (validated == null) {
        return false;
      }
      _connections.add(validated.copyWith(isConnected: true));
      await _saveConnections();
      return true;
    } catch (e) {
      print('添加WebDAV连接失败: $e');
      return false;
    }
  }

  Future<void> removeConnection(String name) async {
    _connections.removeWhere((conn) => conn.name == name);
    await _saveConnections();
  }

  Future<bool> testConnection(WebDAVConnection connection) async {
    final normalized = _normalizeConnection(connection);
    final validated = await _validateConnection(normalized);
    return validated != null;
  }

  Future<WebDAVConnection?> _validateConnection(
    WebDAVConnection connection,
  ) async {
    final triedUrls = <String>{};
    final pending = <WebDAVConnection>[connection];

    while (pending.isNotEmpty) {
      var current = pending.removeAt(0);
      final trimmedUrl = current.url.trim();
      if (trimmedUrl.isEmpty) {
        continue;
      }

      if (!triedUrls.add(trimmedUrl)) {
        continue;
      }

      if (trimmedUrl != current.url) {
        current = current.copyWith(url: trimmedUrl);
      }

      try {
        final client = _createClient(current);
        await _pingClient(client);
        await client.readDir('/');
        return current;
      } on DioException catch (e) {
        if (_isAuthorizationFailure(e)) {
          final authMsg = _buildAuthorizationErrorMessage(current);
          print(authMsg);
          if (pending.isNotEmpty) {
            continue;
          }
          return null;
        }

        final downgraded = _maybeDowngradeToHttp(e, current);
        if (downgraded != null && !triedUrls.contains(downgraded.url)) {
          pending.add(downgraded);
          continue;
        }

        if (_shouldTryCommonDavPaths(e, current)) {
          final candidates = _buildCommonDavConnections(current)
              .where((candidate) => !triedUrls.contains(candidate.url))
              .toList();
          if (candidates.isNotEmpty) {
            print('🔎 PROPFIND 405，尝试常见WebDAV子路径: ${candidates.map((c) => c.url).join(', ')}');
            pending.addAll(candidates);
            continue;
          }
        }

        if (_shouldFallbackOnDioException(e)) {
          print('🔁 webdav_client 连接测试失败 (状态码: ${e.response?.statusCode ?? 'unknown'})，尝试兼容模式...');
          final fallbackConnection = await _legacyTestConnection(current);
          if (fallbackConnection != null) {
            return fallbackConnection;
          }
          return null;
        }

        print('❌ WebDAV连接测试失败: $e');
        print('📍 堆栈: ${e.stackTrace}');
        return null;
      } catch (e, stackTrace) {
        print('❌ WebDAV连接测试失败: $e');
        print('📍 堆栈: $stackTrace');
        final fallbackConnection = await _legacyTestConnection(current);
        if (fallbackConnection != null) {
          return fallbackConnection;
        }
        return null;
      }
    }

    print('⚠️ WebDAV连接测试已尝试所有候选URL，但均失败');
    return null;
  }

  Future<List<WebDAVFile>> listDirectory(
      WebDAVConnection connection, String path) async {
    final normalizedConnection = _normalizeConnection(connection);
    final normalizedPath = _normalizeDirectoryPath(path);
    final client = _createClient(normalizedConnection);

    try {
      final remoteFiles = await client.readDir(normalizedPath);
      final result = <WebDAVFile>[];

      for (final remote in remoteFiles) {
        final converted = _toWebDAVFile(remote, normalizedPath);
        if (converted == null) {
          continue;
        }
        if (converted.isDirectory || isVideoFile(converted.name)) {
          result.add(converted);
        }
      }

      return result;
    } on DioException catch (e) {
      if (_shouldFallbackOnDioException(e)) {
        print('🔁 webdav_client 列目录失败 (状态码: ${e.response?.statusCode ?? 'unknown'})，尝试兼容模式...');
        return await _legacyListDirectory(normalizedConnection, normalizedPath);
      }
      print('❌ 获取WebDAV目录内容失败: $e');
      print('📍 堆栈: ${e.stackTrace}');
      rethrow;
    } catch (e, stackTrace) {
      print('❌ 获取WebDAV目录内容失败: $e');
      print('📍 堆栈: $stackTrace');
      return await _legacyListDirectory(normalizedConnection, normalizedPath);
    }
  }

  bool isVideoFile(String filename) {
    final lower = filename.toLowerCase();
    final dotIndex = lower.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == lower.length - 1) {
      return false;
    }
    final extension = lower.substring(dotIndex + 1);
    const supportedExtensions = {
      'mp4',
      'mkv',
      'avi',
      'mov',
      'wmv',
      'flv',
      'webm',
      'm4v',
    };
    return supportedExtensions.contains(extension);
  }

  String getFileUrl(WebDAVConnection connection, String filePath) {
    final normalizedConnection = _normalizeConnection(connection);
    final trimmedPath = filePath.trim();
    if (_isFullyQualifiedUrl(trimmedPath)) {
      return trimmedPath;
    }

    final baseUri = Uri.parse(normalizedConnection.url);
    final combinedPath = _buildServerRelativePath(baseUri.path, trimmedPath);
    final hasAuth = normalizedConnection.username.isNotEmpty ||
        normalizedConnection.password.isNotEmpty;

    final uri = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: combinedPath,
      userInfo: hasAuth
          ? '${Uri.encodeComponent(normalizedConnection.username)}:${Uri.encodeComponent(normalizedConnection.password)}'
          : null,
    );

    return uri.toString();
  }

  Future<void> updateConnectionStatus(String name) async {
    final index = _connections.indexWhere((conn) => conn.name == name);
    if (index == -1) {
      return;
    }
    final normalized = _normalizeConnection(_connections[index]);
    final validated = await _validateConnection(normalized);
    final isConnected = validated != null;
    final updatedConnection = (validated ?? normalized).copyWith(
      isConnected: isConnected,
    );
    _connections[index] = updatedConnection;
    await _saveConnections();
  }

  WebDAVConnection? getConnection(String name) {
    try {
      return _connections.firstWhere((conn) => conn.name == name);
    } catch (_) {
      return null;
    }
  }

  webdav.Client _createClient(WebDAVConnection connection) {
    final client = webdav.newClient(
      connection.url,
      user: connection.username,
      password: connection.password,
      debug: false,
    );
    client.setHeaders({
      'accept-charset': 'utf-8',
      'user-agent': _userAgent,
    });
    client.setConnectTimeout(_defaultTimeoutMs);
    client.setSendTimeout(_defaultTimeoutMs);
    client.setReceiveTimeout(_defaultTimeoutMs);
    return client;
  }

  Future<void> _pingClient(webdav.Client client) async {
    try {
      await client.ping();
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 405 || statusCode == 501) {
        print('⚠️ WebDAV服务器不支持OPTIONS (状态码: $statusCode)，跳过该错误');
        return;
      }
      rethrow;
    }
  }

  bool _shouldFallbackOnDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 405 || statusCode == 501) {
      return true;
    }
    final message = (e.message ?? e.error?.toString() ?? '').toLowerCase();
    if (message.contains('method not allowed')) {
      return true;
    }
    final statusMessage = e.response?.statusMessage?.toLowerCase() ?? '';
    return statusMessage.contains('method not allowed');
  }

  bool _isAuthorizationFailure(DioException e) {
    final statusCode = e.response?.statusCode;
    return statusCode == 401 || statusCode == 403;
  }

  String _buildAuthorizationErrorMessage(WebDAVConnection connection) {
    final hasUsername = connection.username.trim().isNotEmpty;
    final hasPassword = connection.password.isNotEmpty;
    if (hasUsername || hasPassword) {
      return '❌ WebDAV服务器拒绝了提供的用户名或密码，请确认凭证正确后重试 (401/403)';
    }
    return '⚠️ WebDAV服务器要求身份验证，但当前连接未填写用户名或密码，请在连接设置中提供凭证';
  }

  WebDAVConnection? _maybeDowngradeToHttp(
    DioException e,
    WebDAVConnection connection,
  ) {
    if (!_looksLikeTlsProtocolMismatch(e)) {
      return null;
    }

    Uri? uri;
    try {
      uri = Uri.parse(connection.url);
    } catch (_) {
      return null;
    }

    if (uri.scheme.toLowerCase() != 'https') {
      return null;
    }

    final downgradedUri = uri.replace(scheme: 'http');
    final downgradedConnection = connection.copyWith(url: downgradedUri.toString());
    print('⚙️ 检测到HTTPS握手失败 (${e.error ?? e.message})，自动降级为HTTP: ${downgradedConnection.url}');
    return downgradedConnection;
  }

  bool _looksLikeTlsProtocolMismatch(DioException e) {
    final buffer = StringBuffer();
    if (e.message != null) {
      buffer.write(e.message);
      buffer.write(' ');
    }
    if (e.error != null) {
      buffer.write(e.error.toString());
    }
    final lowered = buffer.toString().toLowerCase();
    if (lowered.isEmpty) {
      return false;
    }
    return lowered.contains('wrong version number');
  }

  bool _shouldTryCommonDavPaths(
    DioException e,
    WebDAVConnection connection,
  ) {
    if (e.response?.statusCode != 405) {
      return false;
    }
    final uri = Uri.tryParse(connection.url);
    if (uri == null) {
      return false;
    }
    final normalizedPath = uri.path.isEmpty ? '/' : uri.path;
    return normalizedPath == '/' || normalizedPath.isEmpty;
  }

  List<WebDAVConnection> _buildCommonDavConnections(
      WebDAVConnection connection) {
    final urls = _buildCommonDavUrls(connection.url);
    if (urls.isEmpty) {
      return const [];
    }
    return urls.map((url) => connection.copyWith(url: url)).toList();
  }

  List<String> _buildCommonDavUrls(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) {
      return const [];
    }
    final normalizedPath = uri.path.isEmpty ? '/' : uri.path;
    if (normalizedPath != '/') {
      return const [];
    }

    final result = <String>[];
    for (final suffix in _commonDavPathSuffixes) {
      final candidatePath = _ensureLeadingSlash(suffix);
      final candidateUri = uri.replace(path: candidatePath);
      final candidate = candidateUri.toString();
      if (!result.contains(candidate)) {
        result.add(candidate);
      }
    }
    return result;
  }

  String _ensureLeadingSlash(String value) {
    if (value.isEmpty) {
      return '/';
    }
    return value.startsWith('/') ? value : '/$value';
  }

  Future<WebDAVConnection?> _legacyTestConnection(
      WebDAVConnection connection) async {
    try {
      final trimmedUrl = connection.url.trim();
      final normalizedUrl = _normalizeUrl(trimmedUrl);

      final urlsToTry = <String>[];
      void addUrl(String value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) {
          return;
        }
        if (!urlsToTry.contains(trimmed)) {
          urlsToTry.add(trimmed);
        }
      }

      addUrl(trimmedUrl);
      if (normalizedUrl.isNotEmpty && normalizedUrl != trimmedUrl) {
        print('🔧 自动调整WebDAV地址为目录格式: $normalizedUrl');
      }
      addUrl(normalizedUrl);

      final heuristicsBase = normalizedUrl.isNotEmpty ? normalizedUrl : trimmedUrl;
      final heuristicUrls = _buildCommonDavUrls(heuristicsBase)
          .where((candidate) => !urlsToTry.contains(candidate))
          .toList();
      final heuristicSet = heuristicUrls.toSet();
      if (heuristicUrls.isNotEmpty) {
        print('🔎 已自动添加常见WebDAV子路径候选: ${heuristicUrls.join(', ')}');
        urlsToTry.addAll(heuristicUrls);
      }

      if (urlsToTry.isEmpty) {
        print('❌ URL格式错误: 地址为空');
        return null;
      }

      final username = connection.username.trim();
      final password = connection.password;

      for (var index = 0; index < urlsToTry.length; index++) {
        final currentUrl = urlsToTry[index];
        if (index == 0) {
          print('🔍 测试WebDAV连接: $currentUrl');
        } else if (heuristicSet.contains(currentUrl)) {
          print('🔁 尝试常见WebDAV路径: $currentUrl');
        } else {
          print('🔁 尝试使用规范化地址: $currentUrl');
        }

        final outcome = await _legacyAttemptConnection(
          baseConnection: connection,
          url: currentUrl,
          username: username,
          password: password,
        );

        if (outcome == _LegacyAttemptOutcome.success) {
          if (heuristicSet.contains(currentUrl)) {
            print('ℹ️ 常见WebDAV路径尝试成功');
          } else if (index > 0) {
            print('ℹ️ 使用规范化地址完成连接测试');
          }
          return connection.copyWith(url: currentUrl);
        }

        if (outcome == _LegacyAttemptOutcome.fatal) {
          print('❌ WebDAV连接失败 (已终止尝试)');
          return null;
        }
      }

      print('❌ WebDAV连接失败，所有尝试均未成功');
      return null;
    } catch (e, stackTrace) {
      print('❌ 兼容模式测试WebDAV连接异常: $e');
      print('📍 堆栈: $stackTrace');
      return null;
    }
  }

  Future<_LegacyAttemptOutcome> _legacyAttemptConnection({
    required WebDAVConnection baseConnection,
    required String url,
    required String username,
    required String password,
  }) async {
    Uri uri;
    try {
      uri = Uri.parse(url);
      print('✅ URL解析成功: ${uri.toString()}');
      print('  协议: ${uri.scheme}');
      print('  主机: ${uri.host}');
      print('  端口: ${uri.port}');
      print('  路径: ${uri.path}');
    } catch (e) {
      print('❌ URL格式错误: $e');
      return _LegacyAttemptOutcome.fatal;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      print('❌ 不支持的协议: ${uri.scheme}，仅支持 http 和 https');
      return _LegacyAttemptOutcome.fatal;
    }

    String? credentials;
    if (username.isNotEmpty || password.isNotEmpty) {
      credentials = base64Encode(utf8.encode('$username:$password'));
      print('🔐 认证信息已准备 (用户名: $username)');
    } else {
      print('ℹ️ 未提供认证信息，尝试匿名访问');
    }

    for (final variant in _propfindVariants) {
      final variantDescription = [
        'Depth=${variant.depth}',
        variant.includeBody ? '带请求体' : '空请求体',
        if (variant.contentType != null && variant.contentType!.isNotEmpty)
          'Content-Type=${variant.contentType}'
      ].join(', ');
      print('🧪 使用PROPFIND变体: $variantDescription');

      final headers = <String, String>{
        'User-Agent': _userAgent,
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Depth': variant.depth,
      };

      final request = http.Request('PROPFIND', uri);
      request.persistentConnection = false;

      if (variant.contentType != null && variant.contentType!.isNotEmpty) {
        headers['Content-Type'] = variant.contentType!;
      }

      if (credentials != null) {
        headers['Authorization'] = 'Basic $credentials';
      }

      request.headers.addAll(headers);
      if (variant.includeBody) {
        request.bodyBytes = utf8.encode(_legacyPropfindRequestBody);
      }

      try {
        print('📡 发送WebDAV PROPFIND请求...');
        final response = await _sendRequest(
          request,
          timeout: const Duration(seconds: 15),
        );

        print('📥 收到响应: ${response.statusCode}');
        print('📄 响应头: ${response.headers}');

        final isSuccess = response.statusCode == 207 ||
            response.statusCode == 200 ||
            response.statusCode == 301 ||
            response.statusCode == 302;

        if (isSuccess) {
          print('✅ WebDAV连接成功! (变体: $variantDescription)');
          return _LegacyAttemptOutcome.success;
        }

        if (response.statusCode == 401) {
          print('❌ 认证失败 (401)，请检查用户名和密码');
          return _LegacyAttemptOutcome.fatal;
        }

        if (response.statusCode == 403) {
          print('❌ 访问被拒绝 (403)，请检查权限设置');
          return _LegacyAttemptOutcome.fatal;
        }

        if (response.statusCode == 404) {
          print('❌ 路径不存在 (404)，请检查WebDAV路径');
          return _LegacyAttemptOutcome.fatal;
        }

        if (response.statusCode == 405) {
          print('⚠️ 方法不被允许 (405)，服务器可能不支持PROPFIND，尝试OPTIONS...');
          final fallbackConnection = baseConnection.copyWith(url: url);
          final optionsSuccess = await _legacyTestWithOptions(fallbackConnection);
          return optionsSuccess
              ? _LegacyAttemptOutcome.success
              : _LegacyAttemptOutcome.retry;
        }

        if (response.statusCode >= 500) {
          print('❌ 服务器错误 (${response.statusCode})，尝试其它PROPFIND变体...');
          continue;
        }

        print('❌ WebDAV连接失败 (状态码: ${response.statusCode})，尝试其它PROPFIND变体...');
      } catch (e) {
        print('❌ 发送PROPFIND请求失败: $e');
        if (e.toString().contains('FormatException')) {
          return _LegacyAttemptOutcome.fatal;
        }
        if (e.toString().contains('HandshakeException')) {
          return _LegacyAttemptOutcome.fatal;
        }
        return _LegacyAttemptOutcome.retry;
      }
    }

    return _LegacyAttemptOutcome.retry;
  }

  Future<bool> _legacyTestWithOptions(WebDAVConnection connection) async {
    try {
      print('🔄 尝试OPTIONS方法测试连接...');
      final uri = Uri.parse(connection.url);

      final headers = <String, String>{
        'User-Agent': _userAgent,
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
      };

      final username = connection.username.trim();
      final password = connection.password;
      if (username.isNotEmpty || password.isNotEmpty) {
        final credentials = base64Encode(utf8.encode('$username:$password'));
        headers['Authorization'] = 'Basic $credentials';
      }

      final request = http.Request('OPTIONS', uri);
      request.persistentConnection = false;
      request.headers.addAll(headers);

      final response = await _sendRequest(
        request,
        timeout: const Duration(seconds: 10),
      );

      print('📥 OPTIONS响应: ${response.statusCode}');
      print('📄 支持的方法: ${response.headers['allow'] ?? 'unknown'}');

      final isSuccess = response.statusCode == 200 || response.statusCode == 204;
      print(isSuccess ? '✅ OPTIONS连接成功!' : '❌ OPTIONS连接失败');

      return isSuccess;
    } catch (e) {
      print('❌ OPTIONS方法也失败: $e');
      return false;
    }
  }

  Future<List<WebDAVFile>> _legacyListDirectory(
    WebDAVConnection connection,
    String path,
  ) async {
    try {
      print('📂 使用兼容模式获取WebDAV目录内容: ${connection.name}:$path');

      Uri uri;
      if (path == '/' || path.isEmpty) {
        uri = Uri.parse(connection.url);
      } else if (path.startsWith('/')) {
        final baseUri = Uri.parse(connection.url);
        uri = Uri(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.port,
          path: path,
        );
      } else {
        uri = Uri.parse('${connection.url.replaceAll(RegExp(r'/$'), '')}/$path');
      }

      print('🔗 兼容模式请求URL: $uri');

      final request = http.Request('PROPFIND', uri);
      request.persistentConnection = false;
      final headers = <String, String>{
        'User-Agent': _userAgent,
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Depth': '1',
        'Content-Type': 'text/xml; charset="utf-8"',
      };

      final username = connection.username.trim();
      final password = connection.password;
      if (username.isNotEmpty || password.isNotEmpty) {
        final credentials = base64Encode(utf8.encode('$username:$password'));
        headers['Authorization'] = 'Basic $credentials';
      }

      request.headers.addAll(headers);

      request.bodyBytes = utf8.encode('''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:displayname/>
    <D:getcontentlength/>
    <D:getlastmodified/>
    <D:resourcetype/>
  </D:prop>
</D:propfind>''');

      print('📡 兼容模式发送PROPFIND请求...');
      final response = await _sendRequest(
        request,
        timeout: const Duration(seconds: 30),
      );
      final responseBody = response.body;

      print('📥 兼容模式响应: ${response.statusCode}');
      print('📄 响应体长度: ${responseBody.length}');

      if (responseBody.length < 2000) {
        print('📄 响应体内容: $responseBody');
      }

      if (response.statusCode != 207 && response.statusCode != 200) {
        print('❌ PROPFIND失败: ${response.statusCode}');
        throw Exception('WebDAV PROPFIND failed: ${response.statusCode}');
      }

      final files = _parseWebDAVResponse(responseBody, path);
      print('📁 兼容模式解析到 ${files.length} 个项目');

      return files;
    } catch (e, stackTrace) {
      print('❌ 兼容模式获取WebDAV目录内容失败: $e');
      print('📍 堆栈: $stackTrace');
      rethrow;
    }
  }

  List<WebDAVFile> _parseWebDAVResponse(String xmlResponse, String basePath) {
    final List<WebDAVFile> files = [];

    try {
      print('🔍 开始解析WebDAV响应...');
      print(
        '📄 原始XML前500字符: ${xmlResponse.substring(0, xmlResponse.length > 500 ? 500 : xmlResponse.length)}',
      );

      final document = XmlDocument.parse(xmlResponse);

      var responses = document.findAllElements('response');
      if (responses.isEmpty) {
        responses = document.findAllElements('d:response');
      }
      if (responses.isEmpty) {
        responses = document.findAllElements('D:response');
      }
      if (responses.isEmpty) {
        responses = document.descendants
            .where(
              (node) =>
                  node is XmlElement &&
                  (node.name.local.toLowerCase() == 'response'),
            )
            .cast<XmlElement>();
      }

      print('📋 找到 ${responses.length} 个response元素');

      if (responses.isEmpty) {
        print('⚠️ 未找到任何response元素，打印完整XML结构：');
        print('📄 完整XML: $xmlResponse');
        return files;
      }

      for (final response in responses) {
        try {
          var hrefElements = response.findElements('href');
          if (hrefElements.isEmpty) {
            hrefElements = response.findElements('d:href');
          }
          if (hrefElements.isEmpty) {
            hrefElements = response.findElements('D:href');
          }
          if (hrefElements.isEmpty) {
            hrefElements = response.descendants
                .where(
                  (node) =>
                      node is XmlElement &&
                      node.name.local.toLowerCase() == 'href',
                )
                .cast<XmlElement>();
          }

          if (hrefElements.isEmpty) {
            print('⚠️ 跳过：没有href元素');
            continue;
          }

          final href = hrefElements.first.text;
          final normalizedHref =
              href.endsWith('/') ? href.substring(0, href.length - 1) : href;
          final normalizedBasePath = basePath.endsWith('/')
              ? basePath.substring(0, basePath.length - 1)
              : basePath;

          if (normalizedHref == normalizedBasePath ||
              href == basePath ||
              href == '$basePath/') {
            continue;
          }

          var propstatElements = response.findElements('propstat');
          if (propstatElements.isEmpty) {
            propstatElements = response.findElements('d:propstat');
          }
          if (propstatElements.isEmpty) {
            propstatElements = response.findElements('D:propstat');
          }
          if (propstatElements.isEmpty) {
            propstatElements = response.descendants
                .where(
                  (node) =>
                      node is XmlElement &&
                      node.name.local.toLowerCase() == 'propstat',
                )
                .cast<XmlElement>();
          }

          if (propstatElements.isEmpty) {
            print('⚠️ 跳过：没有propstat元素');
            continue;
          }

          final propstat = propstatElements.first;

          var propElements = propstat.findElements('prop');
          if (propElements.isEmpty) {
            propElements = propstat.findElements('d:prop');
          }
          if (propElements.isEmpty) {
            propElements = propstat.findElements('D:prop');
          }
          if (propElements.isEmpty) {
            propElements = propstat.descendants
                .where(
                  (node) =>
                      node is XmlElement &&
                      node.name.local.toLowerCase() == 'prop',
                )
                .cast<XmlElement>();
          }

          if (propElements.isEmpty) {
            print('⚠️ 跳过：没有prop元素');
            continue;
          }

          final prop = propElements.first;

          var displayNameElements = prop.findElements('displayname');
          if (displayNameElements.isEmpty) {
            displayNameElements = prop.findElements('d:displayname');
          }
          if (displayNameElements.isEmpty) {
            displayNameElements = prop.findElements('D:displayname');
          }
          if (displayNameElements.isEmpty) {
            displayNameElements = prop.descendants
                .where(
                  (node) =>
                      node is XmlElement &&
                      node.name.local.toLowerCase() == 'displayname',
                )
                .cast<XmlElement>();
          }

          String displayName = '';
          if (displayNameElements.isNotEmpty) {
            displayName = displayNameElements.first.text;
          }

          if (displayName.isEmpty) {
            displayName = Uri.decodeComponent(
              href.split('/').where((s) => s.isNotEmpty).last,
            );
            if (displayName.isEmpty) {
              displayName = href;
            }
          }

          var resourceTypeElements = prop.findElements('resourcetype');
          if (resourceTypeElements.isEmpty) {
            resourceTypeElements = prop.findElements('d:resourcetype');
          }
          if (resourceTypeElements.isEmpty) {
            resourceTypeElements = prop.findElements('D:resourcetype');
          }
          if (resourceTypeElements.isEmpty) {
            resourceTypeElements = prop.descendants
                .where(
                  (node) =>
                      node is XmlElement &&
                      node.name.local.toLowerCase() == 'resourcetype',
                )
                .cast<XmlElement>();
          }

          bool isDirectory = false;
          if (resourceTypeElements.isNotEmpty) {
            final resourceType = resourceTypeElements.first;
            var collectionElements = resourceType.findElements('collection');
            if (collectionElements.isEmpty) {
              collectionElements = resourceType.findElements('d:collection');
            }
            if (collectionElements.isEmpty) {
              collectionElements = resourceType.findElements('D:collection');
            }
            if (collectionElements.isEmpty) {
              collectionElements = resourceType.descendants
                  .where(
                    (node) =>
                        node is XmlElement &&
                        node.name.local.toLowerCase() == 'collection',
                  )
                  .cast<XmlElement>();
            }
            isDirectory = collectionElements.isNotEmpty;
          }

          int? size;
          if (!isDirectory) {
            var contentLengthElements = prop.findElements('getcontentlength');
            if (contentLengthElements.isEmpty) {
              contentLengthElements = prop.findElements('d:getcontentlength');
            }
            if (contentLengthElements.isEmpty) {
              contentLengthElements = prop.findElements('D:getcontentlength');
            }
            if (contentLengthElements.isEmpty) {
              contentLengthElements = prop.descendants
                  .where(
                    (node) =>
                        node is XmlElement &&
                        node.name.local.toLowerCase() == 'getcontentlength',
                  )
                  .cast<XmlElement>();
            }

            if (contentLengthElements.isNotEmpty) {
              size = int.tryParse(contentLengthElements.first.text);
            }
          }

          DateTime? lastModified;
          var lastModifiedElements = prop.findElements('getlastmodified');
          if (lastModifiedElements.isEmpty) {
            lastModifiedElements = prop.findElements('d:getlastmodified');
          }
          if (lastModifiedElements.isEmpty) {
            lastModifiedElements = prop.findElements('D:getlastmodified');
          }
          if (lastModifiedElements.isEmpty) {
            lastModifiedElements = prop.descendants
                .where(
                  (node) =>
                      node is XmlElement &&
                      node.name.local.toLowerCase() == 'getlastmodified',
                )
                .cast<XmlElement>();
          }

          if (lastModifiedElements.isNotEmpty) {
            try {
              lastModified = HttpDate.parse(lastModifiedElements.first.text);
            } catch (e) {
              print('⚠️ 解析修改时间失败: $e');
            }
          }

          final webDavFile = WebDAVFile(
            name: displayName,
            path: href,
            isDirectory: isDirectory,
            size: size,
            lastModified: lastModified,
          );

          if (isDirectory || isVideoFile(displayName)) {
            files.add(webDavFile);
          }
        } catch (e) {
          print('❌ 解析单个response失败: $e');
          continue;
        }
      }

      print('📊 解析完成，共 ${files.length} 个有效项目');
    } catch (e) {
      print('❌ 解析WebDAV响应失败: $e');
      print('📄 完整XML: $xmlResponse');
    }

    return files;
  }

  Future<http.Response> _sendRequest(
    http.BaseRequest request, {
    Duration? timeout,
  }) async {
    final uri = request.url;
    final client = IOClient(_createHttpClient(uri));
    try {
      final future = client.send(request);
      final streamed = timeout == null ? await future : await future.timeout(timeout);
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  HttpClient _createHttpClient(Uri uri) {
    final httpClient = HttpClient();
    httpClient.userAgent = _userAgent;
    httpClient.autoUncompress = false;
    if (_shouldBypassProxy(uri)) {
      httpClient.findProxy = (_) => 'DIRECT';
    }
    return httpClient;
  }

  bool _shouldBypassProxy(Uri uri) {
    final host = uri.host;
    if (host.isEmpty) {
      return false;
    }

    if (host == 'localhost' || host == '127.0.0.1') {
      return true;
    }

    final ip = InternetAddress.tryParse(host);
    if (ip != null) {
      if (ip.type == InternetAddressType.IPv4) {
        final bytes = ip.rawAddress;
        if (bytes.length == 4) {
          final first = bytes[0];
          final second = bytes[1];
          if (first == 10) return true;
          if (first == 127) return true;
          if (first == 192 && second == 168) return true;
          if (first == 172 && second >= 16 && second <= 31) return true;
        }
      } else if (ip.type == InternetAddressType.IPv6) {
        if (ip.isLoopback) return true;
        final firstByte = ip.rawAddress.isNotEmpty ? ip.rawAddress[0] : 0;
        if (firstByte & 0xfe == 0xfc) {
          return true;
        }
      }
    } else {
      if (host.endsWith('.local')) {
        return true;
      }
    }

    return false;
  }

  WebDAVFile? _toWebDAVFile(webdav.File remoteFile, String fallbackBasePath) {
    final rawName = remoteFile.name?.trim() ?? '';
    final name =
        rawName.isNotEmpty ? rawName : _extractNameFromPath(remoteFile.path);
    if (name.isEmpty) {
      return null;
    }

    final isDirectory = remoteFile.isDir ?? false;
    var path = remoteFile.path?.trim() ?? '';
    if (path.isEmpty) {
      path = _buildChildPath(fallbackBasePath, name, isDirectory);
    } else {
      path = _normalizeFilePath(path, isDirectory);
    }

    return WebDAVFile(
      name: name,
      path: path,
      isDirectory: isDirectory,
      size: remoteFile.size,
      lastModified: remoteFile.mTime ?? remoteFile.cTime,
    );
  }

  String _buildChildPath(String parent, String childName, bool isDirectory) {
    final normalizedParent = _normalizeDirectoryPath(parent);
    final combined = '$normalizedParent$childName';
    return isDirectory
        ? _ensureTrailingSlash(combined)
        : _ensureNoTrailingSlash(combined);
  }

  String _normalizeDirectoryPath(String path) {
    var normalized = path.trim();
    if (normalized.isEmpty) {
      return '/';
    }
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    normalized = _collapseSlashes(normalized);
    return _ensureTrailingSlash(normalized);
  }

  String _normalizeFilePath(String path, bool isDirectory) {
    var normalized = path.trim();
    if (normalized.isEmpty) {
      normalized = '/';
    }
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    normalized = _collapseSlashes(normalized);
    return isDirectory
        ? _ensureTrailingSlash(normalized)
        : _ensureNoTrailingSlash(normalized);
  }

  String _ensureTrailingSlash(String value) {
    if (value == '/') {
      return value;
    }
    return value.endsWith('/') ? value : '$value/';
  }

  String _ensureNoTrailingSlash(String value) {
    if (value == '/') {
      return value;
    }
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  String _collapseSlashes(String value) {
    return value.replaceAll(RegExp(r'//+'), '/');
  }

  String _extractNameFromPath(String? path) {
    if (path == null || path.isEmpty) {
      return '';
    }
    final sanitized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final segments = sanitized.split('/');
    return segments.isNotEmpty ? segments.last : '';
  }

  String _buildServerRelativePath(String basePath, String relativePath) {
    final bool isDirectory = relativePath.trim().endsWith('/');
    var normalizedRelative = _normalizeFilePath(relativePath, isDirectory);
    final normalizedBase =
        _ensureTrailingSlash(_collapseSlashes(basePath.isEmpty ? '/' : basePath));

    if (normalizedRelative.startsWith(normalizedBase)) {
      return normalizedRelative;
    }

    if (normalizedRelative.startsWith('/')) {
      normalizedRelative = normalizedRelative.substring(1);
    }

    final combined = '$normalizedBase$normalizedRelative';
    final collapsed = _collapseSlashes(combined);
    return collapsed.startsWith('/') ? collapsed : '/$collapsed';
  }

  bool _isFullyQualifiedUrl(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  WebDAVConnection _normalizeConnection(WebDAVConnection connection) {
    final normalizedUrl = _normalizeUrl(connection.url);
    if (normalizedUrl == connection.url && connection.url.trim() == connection.url) {
      return connection;
    }
    return connection.copyWith(url: normalizedUrl);
  }

  String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    try {
      final uri = Uri.parse(trimmed);
      if (uri.scheme.isEmpty || uri.host.isEmpty) {
        return trimmed;
      }

      var normalizedUri = uri;
      if (uri.path.isEmpty) {
        normalizedUri = uri.replace(path: '/');
      } else if (!uri.path.endsWith('/')) {
        final segments = uri.pathSegments;
        final lastSegment = segments.isNotEmpty ? segments.last : '';
        final looksLikeFile =
            lastSegment.contains('.') && !lastSegment.startsWith('.');
        if (!looksLikeFile) {
          normalizedUri = uri.replace(path: '${uri.path}/');
        }
      }

      return normalizedUri.toString();
    } catch (_) {
      return trimmed;
    }
  }
}

enum _LegacyAttemptOutcome {
  success,
  retry,
  fatal,
}

class _PropfindVariant {
  final String depth;
  final String? contentType;
  final bool includeBody;

  const _PropfindVariant({
    required this.depth,
    this.contentType,
    this.includeBody = true,
  });
}
