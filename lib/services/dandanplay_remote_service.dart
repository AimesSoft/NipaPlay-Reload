import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/models/dandanplay_remote_model.dart';

class DandanplayRemoteService {
  DandanplayRemoteService._internal();

  static final DandanplayRemoteService instance =
      DandanplayRemoteService._internal();

  static const _baseUrlKey = 'dandanplay_remote_base_url';
  static const _tokenKey = 'dandanplay_remote_api_token';
  static const _tokenRequiredKey = 'dandanplay_remote_token_required';

  final List<ValueChanged<bool>> _connectionListeners = [];
  http.Client? _client;

  bool _isConnected = false;
  String? _baseUrl;
  String? _apiToken;
  bool _tokenRequired = false;
  DateTime? _lastSyncedAt;
  String? _lastError;
  List<DandanplayRemoteEpisode> _cachedEpisodes = [];
  bool _isRefreshing = false;

  bool get isConnected => _isConnected;
  String? get serverUrl => _baseUrl;
  bool get tokenRequired => _tokenRequired;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  List<DandanplayRemoteEpisode> get cachedEpisodes =>
      List.unmodifiable(_cachedEpisodes);

  Future<void> loadSavedSettings({bool backgroundRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final savedBase = prefs.getString(_baseUrlKey);
    final savedToken = prefs.getString(_tokenKey);
    final savedTokenRequired = prefs.getBool(_tokenRequiredKey) ?? false;

    if (savedBase == null || savedBase.isEmpty) {
      _baseUrl = null;
      _apiToken = null;
      _tokenRequired = false;
      _isConnected = false;
      return;
    }

    _baseUrl = savedBase;
    _apiToken = savedToken;
    _tokenRequired = savedTokenRequired;

    Future<void> refreshTask() async {
      try {
        await refreshLibrary(force: true);
        _isConnected = true;
        _lastError = null;
        _notifyConnectionState(true);
      } catch (e) {
        _isConnected = false;
        _lastError = e.toString();
      }
    }

    if (backgroundRefresh) {
      unawaited(refreshTask());
    } else {
      await refreshTask();
    }
  }

  Future<bool> connect(String baseUrl, {String? token}) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final trimmedToken = token?.trim();

    final welcome = await _fetchWelcome(normalizedUrl);
    if (welcome.tokenRequired &&
        (trimmedToken == null || trimmedToken.isEmpty)) {
      throw Exception('该服务器已启用API密钥验证，请输入API密钥');
    }

    _baseUrl = normalizedUrl;
    _apiToken = (trimmedToken?.isEmpty ?? true) ? null : trimmedToken;
    _tokenRequired = welcome.tokenRequired;

    await _persistSettings();

    try {
      await refreshLibrary(force: true);
      _isConnected = true;
      _lastError = null;
      _notifyConnectionState(true);
      return true;
    } catch (e) {
      _isConnected = false;
      _lastError = e.toString();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _cachedEpisodes = [];
    _lastSyncedAt = null;
    _baseUrl = null;
    _apiToken = null;
    _tokenRequired = false;
    _lastError = null;
    _client?.close();
    _client = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_baseUrlKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_tokenRequiredKey);

    _notifyConnectionState(false);
  }

  Future<List<DandanplayRemoteEpisode>> refreshLibrary(
      {bool force = false}) async {
    if (_baseUrl == null || _baseUrl!.isEmpty) {
      throw Exception('尚未配置弹弹play远程访问地址');
    }
    if (_isRefreshing && !force) {
      return _cachedEpisodes;
    }

    if (!force && _cachedEpisodes.isNotEmpty && _lastSyncedAt != null) {
      final diff = DateTime.now().difference(_lastSyncedAt!);
      if (diff.inSeconds < 10) {
        return _cachedEpisodes;
      }
    }

    _isRefreshing = true;
    try {
      final response = await _getClient()
          .get(
            _buildUri('/api/v1/library'),
            headers: _buildHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        throw Exception('API密钥无效或缺失，无法访问该服务器');
      }

      if (response.statusCode != 200) {
        throw Exception('访问远程媒体库失败: HTTP ${response.statusCode}');
      }

      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        throw Exception('服务器返回了未知的数据结构');
      }

      _cachedEpisodes = decoded
          .whereType<Map<String, dynamic>>()
          .map(DandanplayRemoteEpisode.fromJson)
          .toList()
        ..sort((a, b) {
          final aTime =
              a.lastPlay ?? a.created ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime =
              b.lastPlay ?? b.created ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
      _lastSyncedAt = DateTime.now();
      _lastError = null;
      return _cachedEpisodes;
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }

  void addConnectionStateListener(ValueChanged<bool> listener) {
    if (_connectionListeners.contains(listener)) return;
    _connectionListeners.add(listener);
  }

  void removeConnectionStateListener(ValueChanged<bool> listener) {
    _connectionListeners.remove(listener);
  }

  String? buildImageUrl(String hash) {
    if (_baseUrl == null || hash.isEmpty) return null;
    return _appendToken('$_baseUrl/api/v1/image/$hash');
  }

  String? buildEpisodeStreamUrl({String? hash, String? entryId}) {
    if (_baseUrl == null) return null;
    if (hash != null && hash.isNotEmpty) {
      return _appendToken('$_baseUrl/api/v1/stream/$hash');
    }
    if (entryId != null && entryId.isNotEmpty) {
      return _appendToken('$_baseUrl/api/v1/stream/id/$entryId');
    }
    return null;
  }

  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    final resolved = _baseUrl!;
    final uri = Uri.parse('$resolved$path');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      ...queryParameters,
    });
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'NipaPlay/1.0',
    };

    if (_apiToken?.isNotEmpty == true) {
      headers['Authorization'] = 'Bearer ${_apiToken!}';
    }

    return headers;
  }

  http.Client _getClient() {
    _client ??= http.Client();
    return _client!;
  }

  Future<_WelcomeInfo> _fetchWelcome(String baseUrl) async {
    final response = await _getClient()
        .get(Uri.parse('$baseUrl/api/v1/welcome'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('无法连接到弹弹play远程服务 (HTTP ${response.statusCode})');
    }

    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('远程服务返回了无效的欢迎信息');
    }

    final tokenRequired = decoded['tokenRequired'] as bool? ?? false;
    final version = decoded['version']?.toString() ?? 'unknown';
    return _WelcomeInfo(version: version, tokenRequired: tokenRequired);
  }

  String _normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_baseUrl?.isNotEmpty == true) {
      await prefs.setString(_baseUrlKey, _baseUrl!);
    }
    if (_apiToken?.isNotEmpty == true) {
      await prefs.setString(_tokenKey, _apiToken!);
    } else {
      await prefs.remove(_tokenKey);
    }
    await prefs.setBool(_tokenRequiredKey, _tokenRequired);
  }

  String _appendToken(String url) {
    if (_apiToken?.isEmpty ?? true) {
      return url;
    }
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}token=${Uri.encodeQueryComponent(_apiToken!)}';
  }

  void _notifyConnectionState(bool connected) {
    for (final listener
        in List<ValueChanged<bool>>.from(_connectionListeners)) {
      try {
        listener(connected);
      } catch (_) {}
    }
  }
}

class _WelcomeInfo {
  const _WelcomeInfo({required this.version, required this.tokenRequired});

  final String version;
  final bool tokenRequired;
}
