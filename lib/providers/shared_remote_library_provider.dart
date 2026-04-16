import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';

import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';

class SharedRemoteLibraryProvider extends ChangeNotifier {
  static const String _hostsPrefsKey = 'shared_remote_hosts';
  static const String _activeHostIdKey = 'shared_remote_active_host';
  static const String _managementUnsupportedMessage =
      '远程端暂不支持“库管理”共享，请更新对方 NipaPlay。';
  static const Set<String> _playableRemoteExtensions = {
    '.mp4',
    '.m4v',
    '.mkv',
    '.mov',
    '.avi',
    '.flv',
    '.ts',
    '.mpeg',
    '.mpg',
    '.webm',
    '.mp3',
    '.flac',
    '.aac',
    '.wav',
  };

  SharedRemoteLibraryProvider() {
    _loadPersistedHosts();
  }

  final List<SharedRemoteHost> _hosts = [];
  String? _activeHostId;
  List<SharedRemoteAnimeSummary> _animeSummaries = [];
  final Map<int, List<SharedRemoteEpisode>> _episodeCache = {};
  bool _isLoading = false;
  String? _errorMessage;
  bool _isInitializing = true;
  bool _autoRefreshPaused = false;
  DateTime? _lastRefreshFailureAt;

  List<SharedRemoteScannedFolder> _scannedFolders = [];
  List<WebDAVConnection> _webdavConnections = [];
  List<SMBConnection> _smbConnections = [];

  SharedRemoteScanStatus? _scanStatus;
  bool _isManagementLoading = false;
  String? _managementErrorMessage;

  List<SharedRemoteHost> get hosts => List.unmodifiable(_hosts);
  String? get activeHostId => _activeHostId;
  SharedRemoteHost? get activeHost {
    if (_activeHostId == null) return null;
    try {
      return _hosts.firstWhere((host) => host.id == _activeHostId);
    } catch (_) {
      return null;
    }
  }

  List<SharedRemoteAnimeSummary> get animeSummaries =>
      List.unmodifiable(_animeSummaries);
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  bool get hasActiveHost =>
      _activeHostId != null && _hosts.any((h) => h.id == _activeHostId);
  bool get hasReachableActiveHost => activeHost?.isOnline == true;

  List<SharedRemoteScannedFolder> get scannedFolders =>
      List.unmodifiable(_scannedFolders);
  List<WebDAVConnection> get webdavConnections =>
      List.unmodifiable(_webdavConnections);
  List<SMBConnection> get smbConnections => List.unmodifiable(_smbConnections);

  SharedRemoteScanStatus? get scanStatus => _scanStatus;
  bool get isManagementLoading => _isManagementLoading;
  String? get managementErrorMessage => _managementErrorMessage;

  Future<void> _loadPersistedHosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawHosts = prefs.getString(_hostsPrefsKey);
      final savedActiveHost = prefs.getString(_activeHostIdKey);
      if (rawHosts != null && rawHosts.isNotEmpty) {
        final storedHosts = SharedRemoteHost.decodeList(rawHosts);
        _hosts
          ..clear()
          ..addAll(storedHosts);
      }
      if (savedActiveHost != null &&
          _hosts.any((element) => element.id == savedActiveHost)) {
        _activeHostId = savedActiveHost;
      }

      // Web Remote Auto-Discovery
      if (kIsWeb) {
        final candidate =
            await WebRemoteAccessService.resolveCandidateBaseUrl();
        if (candidate != null) {
          final existingIndex =
              _hosts.indexWhere((h) => h.baseUrl == candidate);
          if (existingIndex == -1) {
            final id = 'web-origin-${candidate.hashCode}';
            final host = SharedRemoteHost(
              id: id,
              displayName: 'NipaPlay Server (Auto)',
              baseUrl: candidate,
              isOnline: true,
            );
            _hosts.insert(0, host);
            if (_activeHostId == null) {
              _activeHostId = id;
            }
          } else {
            // Ensure it's active if no other host is selected
            if (_activeHostId == null) {
              _activeHostId = _hosts[existingIndex].id;
            }
          }
        }
      }
    } catch (e) {
      _errorMessage = '加载远程媒体库配置失败: $e';
    } finally {
      _isInitializing = false;
      notifyListeners();
      if (_activeHostId != null) {
        refreshLibrary();
      }
    }
  }

  Future<void> _persistHosts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostsPrefsKey, SharedRemoteHost.encodeList(_hosts));
    if (_activeHostId != null) {
      await prefs.setString(_activeHostIdKey, _activeHostId!);
    } else {
      await prefs.remove(_activeHostIdKey);
    }
  }

  Future<SharedRemoteHost> addHost({
    required String displayName,
    required String baseUrl,
  }) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final host = SharedRemoteHost(
        id: id, displayName: displayName, baseUrl: normalizedUrl);
    _hosts.add(host);
    _activeHostId = id;
    await _persistHosts();
    notifyListeners();
    await refreshLibrary(userInitiated: true);
    return host;
  }

  Future<void> removeHost(String hostId) async {
    _hosts.removeWhere((host) => host.id == hostId);
    if (_activeHostId == hostId) {
      _activeHostId = _hosts.isNotEmpty ? _hosts.first.id : null;
      _animeSummaries = [];
      _episodeCache.clear();
      _scannedFolders = [];
      _scanStatus = null;
      _managementErrorMessage = null;
    }
    await _persistHosts();
    notifyListeners();
    if (_activeHostId != null) {
      await refreshLibrary(userInitiated: true);
    }
  }

  Future<void> setActiveHost(String hostId) async {
    if (_activeHostId == hostId) return;
    if (!_hosts.any((host) => host.id == hostId)) return;
    _activeHostId = hostId;
    _animeSummaries = [];
    _episodeCache.clear();
    _scannedFolders = [];
    _scanStatus = null;
    _managementErrorMessage = null;
    await _persistHosts();
    notifyListeners();
    await refreshLibrary(userInitiated: true);
  }

  Future<void> refreshLibrary({bool userInitiated = false}) async {
    final host = activeHost;
    if (host == null) {
      return;
    }

    if (userInitiated) {
      _autoRefreshPaused = false;
      _lastRefreshFailureAt = null;
    } else if (_autoRefreshPaused) {
      final message = _lastRefreshFailureAt != null
          ? '⏳ [共享媒体] 自动刷新已暂停（上次失败 ${_lastRefreshFailureAt!.toLocal()}），等待手动刷新'
          : '⏳ [共享媒体] 自动刷新已暂停，等待手动刷新';
      debugPrint(message);
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/share/animes');
      debugPrint('📡 [共享媒体] 开始请求: $uri');
      debugPrint('📡 [共享媒体] 主机信息: ${host.displayName} (${host.baseUrl})');

      final response =
          await _sendGetRequest(uri, timeout: const Duration(seconds: 10));

      debugPrint('📡 [共享媒体] 响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint(
            '❌ [共享媒体] HTTP错误: ${response.statusCode}, body: ${response.body}');
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final items =
          (payload['items'] ?? payload['data'] ?? []) as List<dynamic>;

      debugPrint('✅ [共享媒体] 成功获取 ${items.length} 个番剧');

      _animeSummaries = items
          .map((item) =>
              SharedRemoteAnimeSummary.fromJson(item as Map<String, dynamic>))
          .toList();
      _animeSummaries
          .sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      _episodeCache.clear();
      _updateHostStatus(host.id, isOnline: true, lastError: null);
      _autoRefreshPaused = false;
      _lastRefreshFailureAt = null;
    } catch (e, stackTrace) {
      debugPrint('❌ [共享媒体] 请求失败: $e');
      debugPrint('❌ [共享媒体] 错误类型: ${e.runtimeType}');
      if (e is TimeoutException) {
        debugPrint('ℹ️ [共享媒体] 请求超时，已暂停自动刷新等待手动重试');
      } else {
        debugPrint('❌ [共享媒体] 堆栈跟踪:\n$stackTrace');
      }

      String friendlyError;
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        if (e.toString().contains('No route to host') ||
            e.toString().contains('errno = 65')) {
          friendlyError = '无法连接到主机 ${host.baseUrl}\n错误详情: $e';
          debugPrint('🔍 [共享媒体诊断] 网络路由问题，可能原因：');
          debugPrint('  1. 设备不在同一局域网');
          debugPrint('  2. 主机IP变更了');
          debugPrint('  3. 防火墙阻止连接');
        } else if (e.toString().contains('Connection refused')) {
          friendlyError = '连接被拒绝，请确认主机已开启远程访问服务';
          debugPrint('🔍 [共享媒体诊断] 端口拒绝连接，可能原因：');
          debugPrint('  1. 远程访问服务未启动');
          debugPrint('  2. 端口号错误');
        } else if (e.toString().contains('timed out') ||
            e.toString().contains('TimeoutException')) {
          friendlyError = '连接超时，请检查网络连接或主机是否在线';
          debugPrint('🔍 [共享媒体诊断] 连接超时，可能原因：');
          debugPrint('  1. 网络延迟过高');
          debugPrint('  2. 主机负载过高');
          debugPrint('  3. 主机未响应');
        } else {
          friendlyError = '网络连接失败: $e';
        }
      } else if (e.toString().contains('HTTP')) {
        friendlyError = '服务器响应错误: $e';
      } else {
        friendlyError = '同步失败: $e';
      }
      _animeSummaries = [];
      _episodeCache.clear();
      _errorMessage = friendlyError;
      _updateHostStatus(host.id, isOnline: false, lastError: e.toString());
      if (!userInitiated) {
        _autoRefreshPaused = true;
        _lastRefreshFailureAt = DateTime.now();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
      await _persistHosts();
    }
  }

  Future<List<SharedRemoteEpisode>> loadAnimeEpisodes(int animeId,
      {bool force = false}) async {
    if (!force && _episodeCache.containsKey(animeId)) {
      return _episodeCache[animeId]!;
    }

    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程媒体库');
    }

    try {
      final uri =
          Uri.parse('${host.baseUrl}/api/media/local/share/animes/$animeId');
      debugPrint('📡 [剧集加载] 请求: $uri');

      final response =
          await _sendGetRequest(uri, timeout: const Duration(seconds: 10));

      debugPrint('📡 [剧集加载] 响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('❌ [剧集加载] HTTP错误: ${response.statusCode}');
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final episodes = (payload['data']?['episodes'] ??
          payload['episodes'] ??
          []) as List<dynamic>;
      final episodeList = episodes
          .map((episode) =>
              SharedRemoteEpisode.fromJson(episode as Map<String, dynamic>))
          .toList();

      debugPrint('✅ [剧集加载] 成功获取 ${episodeList.length} 集');

      _episodeCache[animeId] = episodeList;

      // 如果返回包含 anime 信息，但 summary 还没更新，则更新一下卡片显示
      final data = payload['data']?['anime'] ?? payload['anime'];
      if (data is Map<String, dynamic>) {
        final summaryIndex =
            _animeSummaries.indexWhere((element) => element.animeId == animeId);
        if (summaryIndex != -1 && data['lastWatchTime'] != null) {
          final updatedSummary = SharedRemoteAnimeSummary.fromJson({
            'animeId': animeId,
            'name': data['name'] ?? _animeSummaries[summaryIndex].name,
            'nameCn': data['nameCn'] ?? _animeSummaries[summaryIndex].nameCn,
            'summary': data['summary'] ?? _animeSummaries[summaryIndex].summary,
            'imageUrl':
                data['imageUrl'] ?? _animeSummaries[summaryIndex].imageUrl,
            'lastWatchTime': data['lastWatchTime'],
            'episodeCount': data['episodeCount'] ?? episodeList.length,
            'hasMissingFiles': data['hasMissingFiles'] ?? false,
          });
          _animeSummaries[summaryIndex] = updatedSummary;
          notifyListeners();
        }
      }

      return episodeList;
    } catch (e, stackTrace) {
      debugPrint('❌ [剧集加载] 失败: $e');
      debugPrint('❌ [剧集加载] 错误类型: ${e.runtimeType}');
      debugPrint('❌ [剧集加载] 堆栈:\n$stackTrace');

      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        if (e.toString().contains('No route to host') ||
            e.toString().contains('errno = 65')) {
          throw Exception('无法连接到主机，请检查网络连接\n详情: $e');
        } else if (e.toString().contains('Connection refused')) {
          throw Exception('连接被拒绝，主机服务可能未启动\n详情: $e');
        } else if (e.toString().contains('timed out') ||
            e.toString().contains('TimeoutException')) {
          throw Exception('连接超时，请检查网络或主机状态\n详情: $e');
        }
      }
      rethrow;
    }
  }

  Future<http.Response> _sendGetRequest(Uri uri,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final sanitizedUri = _sanitizeUri(uri);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (!kIsWeb) 'User-Agent': 'NipaPlay/1.0',
    };

    final authHeader = _buildBasicAuthHeader(uri);
    if (authHeader != null) {
      headers['Authorization'] = authHeader;
    }

    final client = _createClient(uri);
    try {
      return await client.get(sanitizedUri, headers: headers).timeout(timeout,
          onTimeout: () {
        throw TimeoutException('请求超时');
      });
    } finally {
      client.close();
    }
  }

  Future<http.Response> _sendPostRequest(
    Uri uri, {
    Map<String, dynamic>? jsonBody,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sanitizedUri = _sanitizeUri(uri);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (!kIsWeb) 'User-Agent': 'NipaPlay/1.0',
      'Content-Type': 'application/json; charset=utf-8',
    };

    final authHeader = _buildBasicAuthHeader(uri);
    if (authHeader != null) {
      headers['Authorization'] = authHeader;
    }

    final client = _createClient(uri);
    try {
      return await client
          .post(
        sanitizedUri,
        headers: headers,
        body: json.encode(jsonBody ?? const <String, dynamic>{}),
      )
          .timeout(timeout, onTimeout: () {
        throw TimeoutException('请求超时');
      });
    } finally {
      client.close();
    }
  }

  Future<http.Response> _sendDeleteRequest(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sanitizedUri = _sanitizeUri(uri);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (!kIsWeb) 'User-Agent': 'NipaPlay/1.0',
    };

    final authHeader = _buildBasicAuthHeader(uri);
    if (authHeader != null) {
      headers['Authorization'] = authHeader;
    }

    final client = _createClient(uri);
    try {
      return await client
          .delete(sanitizedUri, headers: headers)
          .timeout(timeout, onTimeout: () {
        throw TimeoutException('请求超时');
      });
    } finally {
      client.close();
    }
  }

  Uri _sanitizeUri(Uri source) {
    return Uri(
      scheme: source.scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      path: source.path,
      query: source.hasQuery ? source.query : null,
      fragment: source.fragment.isEmpty ? null : source.fragment,
    );
  }

  String? _buildBasicAuthHeader(Uri uri) {
    if (uri.userInfo.isEmpty) {
      return null;
    }

    final separatorIndex = uri.userInfo.indexOf(':');
    String username;
    String password;
    if (separatorIndex >= 0) {
      username = uri.userInfo.substring(0, separatorIndex);
      password = uri.userInfo.substring(separatorIndex + 1);
    } else {
      username = uri.userInfo;
      password = '';
    }

    username = Uri.decodeComponent(username);
    password = Uri.decodeComponent(password);

    return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }

  http.Client _createClient(Uri uri) {
    if (kIsWeb) {
      return http.Client();
    }
    return IOClient(_createHttpClient(uri));
  }

  HttpClient _createHttpClient(Uri uri) {
    final httpClient = HttpClient();
    httpClient.userAgent = 'NipaPlay/1.0';
    httpClient.autoUncompress = false;
    if (_shouldBypassProxy(uri.host)) {
      httpClient.findProxy = (_) => 'DIRECT';
    }
    return httpClient;
  }

  bool _shouldBypassProxy(String host) {
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
        if (ip.isLoopback) {
          return true;
        }
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

  Uri buildStreamUri(SharedRemoteEpisode episode) {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程媒体库');
    }
    final streamPath = episode.streamPath.trim();
    if (streamPath.isEmpty) {
      throw Exception('该剧集缺少可用的播放地址');
    }
    final resolved = Uri.parse(host.baseUrl).resolve(
      streamPath.startsWith('/') ? streamPath.substring(1) : streamPath,
    );
    if (kIsWeb &&
        resolved.isAbsolute &&
        (resolved.scheme == 'http' || resolved.scheme == 'https')) {
      return WebRemoteAccessService.proxyUri(resolved);
    }
    return resolved;
  }

  WatchHistoryItem buildWatchHistoryItem({
    required SharedRemoteAnimeSummary anime,
    required SharedRemoteEpisode episode,
  }) {
    final streamUri = buildStreamUri(episode).toString();
    final int duration = episode.duration ?? 0;
    final int initialPosition = episode.lastPosition ?? 0;
    double initialProgress = episode.progress ?? 0;
    if (initialProgress <= 0 && duration > 0 && initialPosition > 0) {
      initialProgress = (initialPosition / duration).clamp(0.0, 1.0);
    }
    return WatchHistoryItem(
      filePath: streamUri,
      animeName: anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name,
      episodeTitle: episode.title,
      episodeId: episode.episodeId,
      animeId: episode.animeId ?? anime.animeId,
      watchProgress: initialProgress,
      lastPosition: initialPosition,
      duration: duration,
      lastWatchTime: episode.lastWatchTime ?? DateTime.now(),
      thumbnailPath: anime.imageUrl,
      isFromScan: false,
      videoHash: episode.videoHash,
    );
  }

  PlayableItem buildPlayableItem({
    required SharedRemoteAnimeSummary anime,
    required SharedRemoteEpisode episode,
  }) {
    final watchItem = buildWatchHistoryItem(anime: anime, episode: episode);
    return PlayableItem(
      videoPath: watchItem.filePath,
      title: watchItem.animeName,
      subtitle: episode.title,
      animeId: anime.animeId,
      episodeId: episode.episodeId ?? episode.shareId.hashCode,
      historyItem: watchItem,
      actualPlayUrl: watchItem.filePath,
    );
  }

  Future<void> renameHost(String hostId, String newName) async {
    final index = _hosts.indexWhere((host) => host.id == hostId);
    if (index == -1) return;
    _hosts[index] = _hosts[index].copyWith(displayName: newName);
    await _persistHosts();
    notifyListeners();
  }

  Future<void> updateHostUrl(String hostId, String newUrl) async {
    final index = _hosts.indexWhere((host) => host.id == hostId);
    if (index == -1) return;
    final normalized = _normalizeBaseUrl(newUrl);
    _hosts[index] = _hosts[index].copyWith(baseUrl: normalized);
    if (_activeHostId == hostId) {
      await refreshLibrary(userInitiated: true);
    }
    await _persistHosts();
    notifyListeners();
  }

  String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (normalized.isEmpty) return normalized;

    final hasScheme = normalized.contains('://');
    if (!hasScheme) {
      normalized = 'http://$normalized';
    }

    // 先去掉末尾斜杠，避免 Uri.parse 解析 path 导致的歧义。
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    try {
      final uri = Uri.parse(normalized);

      // 用户未显式指定端口时：若是局域网/本机地址，则默认走 NipaPlay 远程访问默认端口 1180。
      if (!uri.hasPort &&
          uri.scheme == 'http' &&
          _shouldBypassProxy(uri.host)) {
        normalized = uri.replace(port: 1180).toString();
      }
    } catch (_) {
      // 若解析失败，保留原始输入（上层会在请求时给出错误提示）
    }

    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized;
  }

  void _updateHostStatus(String hostId, {bool? isOnline, String? lastError}) {
    final index = _hosts.indexWhere((host) => host.id == hostId);
    if (index == -1) return;
    final current = _hosts[index];
    _hosts[index] = current.copyWith(
      isOnline: isOnline ?? current.isOnline,
      lastConnectedAt: DateTime.now(),
      lastError: lastError,
    );
  }

  Future<void> refreshManagement({bool userInitiated = false}) async {
    final host = activeHost;
    if (host == null) {
      return;
    }

    _isManagementLoading = true;
    _managementErrorMessage = null;
    notifyListeners();

    try {
      final foldersUri =
          Uri.parse('${host.baseUrl}/api/media/local/manage/folders');
      final response = await _sendGetRequest(foldersUri,
          timeout: const Duration(seconds: 10));

      if (response.statusCode == HttpStatus.notFound) {
        _scannedFolders = [];
        _webdavConnections = [];
        _smbConnections = [];
        _scanStatus = null;
        if (kIsWeb) {
          MediaSourceUtils.updateRemoteWebDavConnections(_webdavConnections);
        }
        _managementErrorMessage = _managementUnsupportedMessage;
        _updateHostStatus(host.id, isOnline: true, lastError: null);
        return;
      }

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final bool success = payloadMap['success'] as bool? ?? true;
      if (!success) {
        _managementErrorMessage = payloadMap['message'] as String? ?? '远程端返回失败';
        return;
      }

      final data = payloadMap['data'];

      // Parse Folders
      final foldersRaw = data is Map<String, dynamic>
          ? data['folders']
          : payloadMap['folders'];

      final folders = <SharedRemoteScannedFolder>[];
      if (foldersRaw is List) {
        for (final item in foldersRaw) {
          if (item is Map<String, dynamic>) {
            folders.add(SharedRemoteScannedFolder.fromJson(item));
          } else if (item is Map) {
            folders.add(SharedRemoteScannedFolder.fromJson(
                item.cast<String, dynamic>()));
          }
        }
      }
      _scannedFolders = folders;

      // Parse WebDAV
      final webdavRaw = data is Map<String, dynamic> ? data['webdav'] : null;
      final webdav = <WebDAVConnection>[];
      if (webdavRaw is List) {
        for (final item in webdavRaw) {
          if (item is Map<String, dynamic>) {
            webdav.add(WebDAVConnection.fromJson(item));
          }
        }
      }
      _webdavConnections = webdav;

      // Parse SMB
      final smbRaw = data is Map<String, dynamic> ? data['smb'] : null;
      final smb = <SMBConnection>[];
      if (smbRaw is List) {
        for (final item in smbRaw) {
          if (item is Map<String, dynamic>) {
            smb.add(SMBConnection.fromJson(item));
          }
        }
      }
      _smbConnections = smb;
      if (kIsWeb) {
        MediaSourceUtils.updateRemoteWebDavConnections(_webdavConnections);
      }

      await refreshScanStatus(showLoading: false);
      _updateHostStatus(host.id, isOnline: true, lastError: null);
    } catch (e) {
      _scannedFolders = [];
      _webdavConnections = [];
      _smbConnections = [];
      _scanStatus = null;
      if (kIsWeb) {
        MediaSourceUtils.updateRemoteWebDavConnections(_webdavConnections);
      }
      _managementErrorMessage = _buildManagementFriendlyError(e, host);
      _updateHostStatus(host.id, isOnline: false, lastError: e.toString());
    } finally {
      _isManagementLoading = false;
      notifyListeners();
      await _persistHosts();
    }
  }

  Future<void> refreshScanStatus({bool showLoading = true}) async {
    final host = activeHost;
    if (host == null) {
      return;
    }

    if (showLoading) {
      _isManagementLoading = true;
      notifyListeners();
    }

    try {
      final statusUri =
          Uri.parse('${host.baseUrl}/api/media/local/manage/scan/status');
      final response =
          await _sendGetRequest(statusUri, timeout: const Duration(seconds: 5));

      if (response.statusCode == HttpStatus.notFound) {
        _scanStatus = null;
        _managementErrorMessage ??= _managementUnsupportedMessage;
        _updateHostStatus(host.id, isOnline: true, lastError: null);
        return;
      }

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final bool success = payloadMap['success'] as bool? ?? true;
      if (!success) {
        _managementErrorMessage = payloadMap['message'] as String? ?? '远程端返回失败';
        return;
      }

      final data = payloadMap['data'];
      if (data is Map<String, dynamic>) {
        _scanStatus = SharedRemoteScanStatus.fromJson(data);
      } else if (payloadMap.isNotEmpty) {
        _scanStatus = SharedRemoteScanStatus.fromJson(payloadMap);
      } else {
        _scanStatus = null;
      }

      _updateHostStatus(host.id, isOnline: true, lastError: null);
    } catch (e) {
      _scanStatus = null;
      _managementErrorMessage ??= _buildManagementFriendlyError(e, host);
      _updateHostStatus(host.id, isOnline: false, lastError: e.toString());
    } finally {
      if (showLoading) {
        _isManagementLoading = false;
      }
      notifyListeners();
      if (showLoading) {
        await _persistHosts();
      }
    }
  }

  Future<List<SharedRemoteFileEntry>> browseRemoteDirectory(
      String directoryPath) async {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程主机');
    }

    final sanitizedPath = directoryPath.trim();
    if (sanitizedPath.isEmpty) {
      throw Exception('目录路径为空');
    }

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/browse')
          .replace(queryParameters: {'path': sanitizedPath});
      final response =
          await _sendGetRequest(uri, timeout: const Duration(seconds: 10));

      if (response.statusCode == HttpStatus.notFound) {
        String? apiMessage;
        try {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            apiMessage = decoded['message'] as String?;
          } else if (decoded is Map) {
            apiMessage = decoded['message']?.toString();
          }
        } catch (_) {
          apiMessage = null;
        }

        final message = apiMessage != null && apiMessage.trim().isNotEmpty
            ? apiMessage
            : _managementUnsupportedMessage;
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      if (response.statusCode != HttpStatus.ok) {
        String? apiMessage;
        try {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            apiMessage = decoded['message'] as String?;
          } else if (decoded is Map) {
            apiMessage = decoded['message']?.toString();
          }
        } catch (_) {
          apiMessage = null;
        }

        final message = apiMessage != null && apiMessage.trim().isNotEmpty
            ? apiMessage
            : 'HTTP ${response.statusCode}';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final bool success = payloadMap['success'] as bool? ?? true;
      if (!success) {
        final message = payloadMap['message'] as String? ?? '远程端返回失败';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final data = payloadMap['data'];
      final entriesRaw = data is Map<String, dynamic>
          ? data['entries']
          : payloadMap['entries'];

      final entries = <SharedRemoteFileEntry>[];
      if (entriesRaw is List) {
        for (final item in entriesRaw) {
          if (item is Map<String, dynamic>) {
            entries.add(SharedRemoteFileEntry.fromJson(item));
          } else if (item is Map) {
            entries.add(
              SharedRemoteFileEntry.fromJson(item.cast<String, dynamic>()),
            );
          }
        }
      }

      if (_managementErrorMessage != null) {
        _managementErrorMessage = null;
        notifyListeners();
      }

      return entries;
    } catch (e) {
      final existing = _managementErrorMessage;
      final rawMessage = e.toString();
      final friendly = existing != null && existing.trim().isNotEmpty
          ? existing
          : (rawMessage.contains(_managementUnsupportedMessage)
              ? _managementUnsupportedMessage
              : _buildManagementFriendlyError(e, host));
      _managementErrorMessage = friendly;
      notifyListeners();
      rethrow;
    }
  }

  Future<List<WebDAVFile>> listRemoteWebDAVDirectory({
    required String name,
    required String path,
  }) async {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程主机');
    }

    final sanitizedName = name.trim();
    if (sanitizedName.isEmpty) {
      throw Exception('WebDAV 连接名称为空');
    }

    try {
      final uri =
          Uri.parse('${host.baseUrl}/api/media/local/manage/webdav/list')
              .replace(queryParameters: {'name': sanitizedName, 'path': path});
      final response =
          await _sendGetRequest(uri, timeout: const Duration(seconds: 15));

      if (response.statusCode != HttpStatus.ok) {
        String? apiMessage;
        try {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            apiMessage = decoded['message'] as String?;
          } else if (decoded is Map) {
            apiMessage = decoded['message']?.toString();
          }
        } catch (_) {
          apiMessage = null;
        }
        final message = apiMessage != null && apiMessage.trim().isNotEmpty
            ? apiMessage
            : 'HTTP ${response.statusCode}';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final bool success = payloadMap['success'] as bool? ?? true;
      if (!success) {
        final message = payloadMap['message'] as String? ?? '远程端返回失败';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final data = payloadMap['data'];
      final entriesRaw = data is Map<String, dynamic>
          ? data['entries']
          : payloadMap['entries'];

      int? parseInt(dynamic value) {
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value);
        return null;
      }

      DateTime? parseDate(dynamic value) {
        if (value is String) {
          return DateTime.tryParse(value);
        }
        return null;
      }

      final entries = <WebDAVFile>[];
      if (entriesRaw is List) {
        for (final item in entriesRaw) {
          final Map<String, dynamic>? map = item is Map<String, dynamic>
              ? item
              : (item is Map ? item.cast<String, dynamic>() : null);
          if (map == null) continue;
          entries.add(WebDAVFile(
            name: map['name'] as String? ?? '',
            path: map['path'] as String? ?? '',
            isDirectory: map['isDirectory'] == true,
            size: parseInt(map['size']),
            lastModified: parseDate(map['lastModified']),
          ));
        }
      }

      if (_managementErrorMessage != null) {
        _managementErrorMessage = null;
        notifyListeners();
      }

      return entries;
    } catch (e) {
      final existing = _managementErrorMessage;
      final rawMessage = e.toString();
      final friendly = existing != null && existing.trim().isNotEmpty
          ? existing
          : _buildManagementFriendlyError(e, host);
      _managementErrorMessage = friendly;
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> testWebDAVConnection({
    String? name,
    WebDAVConnection? connection,
  }) async {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程主机');
    }

    if ((name == null || name.trim().isEmpty) && connection == null) {
      throw Exception('WebDAV 连接参数为空');
    }

    try {
      Uri uri = Uri.parse('${host.baseUrl}/api/media/local/manage/webdav/test');
      http.Response response;
      if (connection != null) {
        response = await _sendPostRequest(
          uri,
          jsonBody: connection.toJson(),
          timeout: const Duration(seconds: 15),
        );
      } else {
        uri = uri.replace(queryParameters: {'name': name!.trim()});
        response = await _sendPostRequest(
          uri,
          timeout: const Duration(seconds: 15),
        );
      }

      if (response.statusCode != HttpStatus.ok) {
        String? apiMessage;
        try {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            apiMessage = decoded['message'] as String?;
          } else if (decoded is Map) {
            apiMessage = decoded['message']?.toString();
          }
        } catch (_) {
          apiMessage = null;
        }
        final message = apiMessage != null && apiMessage.trim().isNotEmpty
            ? apiMessage
            : 'HTTP ${response.statusCode}';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final data = payloadMap['data'];
      final bool connected = data is Map<String, dynamic>
          ? data['isConnected'] == true
          : payloadMap['isConnected'] == true;
      if (name != null && name.trim().isNotEmpty) {
        await refreshManagement(userInitiated: true);
      }
      if (_managementErrorMessage != null) {
        _managementErrorMessage = null;
        notifyListeners();
      }
      return connected;
    } catch (e) {
      _managementErrorMessage = _buildManagementFriendlyError(e, host);
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, int>> scanRemoteWebDAVFolder({
    required String name,
    required String path,
  }) async {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程主机');
    }

    final sanitizedName = name.trim();
    if (sanitizedName.isEmpty) {
      throw Exception('WebDAV 连接名称为空');
    }

    try {
      final uri =
          Uri.parse('${host.baseUrl}/api/media/local/manage/webdav/scan');
      final response = await _sendPostRequest(
        uri,
        jsonBody: {'name': sanitizedName, 'path': path},
        timeout: const Duration(seconds: 60),
      );

      if (response.statusCode != HttpStatus.ok) {
        String? apiMessage;
        try {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            apiMessage = decoded['message'] as String?;
          } else if (decoded is Map) {
            apiMessage = decoded['message']?.toString();
          }
        } catch (_) {
          apiMessage = null;
        }
        final message = apiMessage != null && apiMessage.trim().isNotEmpty
            ? apiMessage
            : 'HTTP ${response.statusCode}';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final data = payloadMap['data'];
      int readInt(dynamic value) {
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value) ?? 0;
        return 0;
      }

      return {
        'total': readInt(
            data is Map<String, dynamic> ? data['total'] : payloadMap['total']),
        'matched': readInt(data is Map<String, dynamic>
            ? data['matched']
            : payloadMap['matched']),
        'failed': readInt(data is Map<String, dynamic>
            ? data['failed']
            : payloadMap['failed']),
      };
    } catch (e) {
      _managementErrorMessage = _buildManagementFriendlyError(e, host);
      notifyListeners();
      rethrow;
    }
  }

  Future<List<SMBFileEntry>> listRemoteSMBDirectory({
    required String name,
    required String path,
  }) async {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程主机');
    }

    final sanitizedName = name.trim();
    if (sanitizedName.isEmpty) {
      throw Exception('SMB 连接名称为空');
    }

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/smb/list')
          .replace(queryParameters: {'name': sanitizedName, 'path': path});
      final response =
          await _sendGetRequest(uri, timeout: const Duration(seconds: 15));

      if (response.statusCode != HttpStatus.ok) {
        String? apiMessage;
        try {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            apiMessage = decoded['message'] as String?;
          } else if (decoded is Map) {
            apiMessage = decoded['message']?.toString();
          }
        } catch (_) {
          apiMessage = null;
        }
        final message = apiMessage != null && apiMessage.trim().isNotEmpty
            ? apiMessage
            : 'HTTP ${response.statusCode}';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final bool success = payloadMap['success'] as bool? ?? true;
      if (!success) {
        final message = payloadMap['message'] as String? ?? '远程端返回失败';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final data = payloadMap['data'];
      final entriesRaw = data is Map<String, dynamic>
          ? data['entries']
          : payloadMap['entries'];

      int? parseInt(dynamic value) {
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value);
        return null;
      }

      final entries = <SMBFileEntry>[];
      if (entriesRaw is List) {
        for (final item in entriesRaw) {
          final Map<String, dynamic>? map = item is Map<String, dynamic>
              ? item
              : (item is Map ? item.cast<String, dynamic>() : null);
          if (map == null) continue;
          entries.add(SMBFileEntry(
            name: map['name'] as String? ?? '',
            path: map['path'] as String? ?? '',
            isDirectory: map['isDirectory'] == true,
            size: parseInt(map['size']),
            isShare: map['isShare'] == true,
          ));
        }
      }

      if (_managementErrorMessage != null) {
        _managementErrorMessage = null;
        notifyListeners();
      }

      return entries;
    } catch (e) {
      final existing = _managementErrorMessage;
      final friendly = existing != null && existing.trim().isNotEmpty
          ? existing
          : _buildManagementFriendlyError(e, host);
      _managementErrorMessage = friendly;
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> testSMBConnection(String name) async {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程主机');
    }

    final sanitizedName = name.trim();
    if (sanitizedName.isEmpty) {
      throw Exception('SMB 连接名称为空');
    }

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/smb/test')
          .replace(queryParameters: {'name': sanitizedName});
      final response =
          await _sendPostRequest(uri, timeout: const Duration(seconds: 15));

      if (response.statusCode != HttpStatus.ok) {
        String? apiMessage;
        try {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            apiMessage = decoded['message'] as String?;
          } else if (decoded is Map) {
            apiMessage = decoded['message']?.toString();
          }
        } catch (_) {
          apiMessage = null;
        }
        final message = apiMessage != null && apiMessage.trim().isNotEmpty
            ? apiMessage
            : 'HTTP ${response.statusCode}';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final data = payloadMap['data'];
      final bool connected = data is Map<String, dynamic>
          ? data['isConnected'] == true
          : payloadMap['isConnected'] == true;
      await refreshManagement(userInitiated: true);
      if (_managementErrorMessage != null) {
        _managementErrorMessage = null;
        notifyListeners();
      }
      return connected;
    } catch (e) {
      _managementErrorMessage = _buildManagementFriendlyError(e, host);
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, int>> scanRemoteSMBFolder({
    required String name,
    required String path,
  }) async {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程主机');
    }

    final sanitizedName = name.trim();
    if (sanitizedName.isEmpty) {
      throw Exception('SMB 连接名称为空');
    }

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/smb/scan');
      final response = await _sendPostRequest(
        uri,
        jsonBody: {'name': sanitizedName, 'path': path},
        timeout: const Duration(seconds: 60),
      );

      if (response.statusCode != HttpStatus.ok) {
        String? apiMessage;
        try {
          final decoded = json.decode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            apiMessage = decoded['message'] as String?;
          } else if (decoded is Map) {
            apiMessage = decoded['message']?.toString();
          }
        } catch (_) {
          apiMessage = null;
        }
        final message = apiMessage != null && apiMessage.trim().isNotEmpty
            ? apiMessage
            : 'HTTP ${response.statusCode}';
        _managementErrorMessage = message;
        notifyListeners();
        throw Exception(message);
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final data = payloadMap['data'];
      int readInt(dynamic value) {
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value) ?? 0;
        return 0;
      }

      return {
        'total': readInt(
            data is Map<String, dynamic> ? data['total'] : payloadMap['total']),
        'matched': readInt(data is Map<String, dynamic>
            ? data['matched']
            : payloadMap['matched']),
        'failed': readInt(data is Map<String, dynamic>
            ? data['failed']
            : payloadMap['failed']),
      };
    } catch (e) {
      _managementErrorMessage = _buildManagementFriendlyError(e, host);
      notifyListeners();
      rethrow;
    }
  }

  Uri buildRemoteFileStreamUri(String filePath) {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程主机');
    }
    if (!isRemoteFilePathPlayable(filePath)) {
      throw Exception('该文件不是可播放媒体');
    }
    return Uri.parse('${host.baseUrl}/api/media/local/manage/stream')
        .replace(queryParameters: {'path': filePath});
  }

  bool isRemoteFilePlayable(SharedRemoteFileEntry entry) {
    if (entry.isDirectory) {
      return false;
    }
    final candidate =
        entry.name.trim().isNotEmpty ? entry.name.trim() : entry.path.trim();
    return isRemoteFilePathPlayable(candidate);
  }

  bool isRemoteFilePathPlayable(String filePath) {
    final target = filePath.trim();
    if (target.isEmpty) {
      return false;
    }
    final extension = p.extension(target).toLowerCase();
    return _playableRemoteExtensions.contains(extension);
  }

  Future<void> addRemoteFolder({
    required String folderPath,
    bool scan = true,
    bool skipPreviouslyMatchedUnwatched = false,
  }) async {
    final host = activeHost;
    if (host == null) {
      _managementErrorMessage = '未选择远程主机';
      notifyListeners();
      return;
    }

    final sanitized = folderPath.trim();
    if (sanitized.isEmpty) {
      _managementErrorMessage = '请输入文件夹路径';
      notifyListeners();
      return;
    }

    _isManagementLoading = true;
    _managementErrorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/folders');
      final response = await _sendPostRequest(
        uri,
        jsonBody: {
          'path': sanitized,
          'scan': scan,
          'skipPreviouslyMatchedUnwatched': skipPreviouslyMatchedUnwatched,
        },
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode == HttpStatus.notFound) {
        _managementErrorMessage = _managementUnsupportedMessage;
        _updateHostStatus(host.id, isOnline: true, lastError: null);
        return;
      }

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final bool success = payloadMap['success'] as bool? ?? false;
      if (!success) {
        _managementErrorMessage = payloadMap['message'] as String? ?? '远程端返回失败';
        return;
      }

      final data = payloadMap['data'];
      final foldersRaw = data is Map<String, dynamic>
          ? data['folders']
          : payloadMap['folders'];

      final folders = <SharedRemoteScannedFolder>[];
      if (foldersRaw is List) {
        for (final item in foldersRaw) {
          if (item is Map<String, dynamic>) {
            folders.add(SharedRemoteScannedFolder.fromJson(item));
          } else if (item is Map) {
            folders.add(SharedRemoteScannedFolder.fromJson(
                item.cast<String, dynamic>()));
          }
        }
      }
      if (folders.isNotEmpty) {
        _scannedFolders = folders;
      }

      await refreshScanStatus(showLoading: false);
      _updateHostStatus(host.id, isOnline: true, lastError: null);
    } catch (e) {
      _managementErrorMessage = _buildManagementFriendlyError(e, host);
      _updateHostStatus(host.id, isOnline: false, lastError: e.toString());
    } finally {
      _isManagementLoading = false;
      notifyListeners();
      await _persistHosts();
    }
  }

  Future<void> removeRemoteFolder(String folderPath) async {
    final host = activeHost;
    if (host == null) {
      _managementErrorMessage = '未选择远程主机';
      notifyListeners();
      return;
    }

    final sanitized = folderPath.trim();
    if (sanitized.isEmpty) {
      _managementErrorMessage = '文件夹路径为空';
      notifyListeners();
      return;
    }

    _isManagementLoading = true;
    _managementErrorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/folders')
          .replace(queryParameters: {'path': sanitized});
      final response =
          await _sendDeleteRequest(uri, timeout: const Duration(seconds: 10));

      if (response.statusCode == HttpStatus.notFound) {
        _managementErrorMessage = _managementUnsupportedMessage;
        _updateHostStatus(host.id, isOnline: true, lastError: null);
        return;
      }

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final bool success = payloadMap['success'] as bool? ?? false;
      if (!success) {
        _managementErrorMessage = payloadMap['message'] as String? ?? '远程端返回失败';
        return;
      }

      final data = payloadMap['data'];
      final foldersRaw = data is Map<String, dynamic>
          ? data['folders']
          : payloadMap['folders'];

      final folders = <SharedRemoteScannedFolder>[];
      if (foldersRaw is List) {
        for (final item in foldersRaw) {
          if (item is Map<String, dynamic>) {
            folders.add(SharedRemoteScannedFolder.fromJson(item));
          } else if (item is Map) {
            folders.add(SharedRemoteScannedFolder.fromJson(
                item.cast<String, dynamic>()));
          }
        }
      }
      _scannedFolders = folders;

      await refreshScanStatus(showLoading: false);
      _updateHostStatus(host.id, isOnline: true, lastError: null);
    } catch (e) {
      _managementErrorMessage = _buildManagementFriendlyError(e, host);
      _updateHostStatus(host.id, isOnline: false, lastError: e.toString());
    } finally {
      _isManagementLoading = false;
      notifyListeners();
      await _persistHosts();
    }
  }

  Future<void> rescanRemoteAll(
      {bool skipPreviouslyMatchedUnwatched = true}) async {
    final host = activeHost;
    if (host == null) {
      _managementErrorMessage = '未选择远程主机';
      notifyListeners();
      return;
    }

    _isManagementLoading = true;
    _managementErrorMessage = null;
    notifyListeners();

    try {
      final uri =
          Uri.parse('${host.baseUrl}/api/media/local/manage/scan/rescan');
      final response = await _sendPostRequest(
        uri,
        jsonBody: {
          'skipPreviouslyMatchedUnwatched': skipPreviouslyMatchedUnwatched,
        },
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode == HttpStatus.notFound) {
        _managementErrorMessage = _managementUnsupportedMessage;
        _updateHostStatus(host.id, isOnline: true, lastError: null);
        return;
      }

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload = json.decode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> payloadMap =
          payload is Map<String, dynamic> ? payload : <String, dynamic>{};
      final bool success = payloadMap['success'] as bool? ?? false;
      if (!success) {
        _managementErrorMessage = payloadMap['message'] as String? ?? '远程端返回失败';
        return;
      }

      await refreshScanStatus(showLoading: false);
      _updateHostStatus(host.id, isOnline: true, lastError: null);
    } catch (e) {
      _managementErrorMessage = _buildManagementFriendlyError(e, host);
      _updateHostStatus(host.id, isOnline: false, lastError: e.toString());
    } finally {
      _isManagementLoading = false;
      notifyListeners();
      await _persistHosts();
    }
  }

  Future<int> cleanupMissingRemoteFolders() async {
    final host = activeHost;
    if (host == null) {
      _managementErrorMessage = '未选择远程主机';
      notifyListeners();
      return 0;
    }

    final missingPaths = _scannedFolders
        .where((folder) => !folder.exists && folder.path.trim().isNotEmpty)
        .map((folder) => folder.path.trim())
        .toList();
    if (missingPaths.isEmpty) {
      _managementErrorMessage = null;
      notifyListeners();
      return 0;
    }

    int removedCount = 0;
    for (final path in missingPaths) {
      await removeRemoteFolder(path);
      if (_managementErrorMessage != null &&
          _managementErrorMessage!.isNotEmpty) {
        break;
      }
      removedCount++;
    }
    return removedCount;
  }

  // --- WebDAV Methods ---

  Future<void> addWebDAVConnection(WebDAVConnection connection) async {
    final host = activeHost;
    if (host == null) return;

    _isManagementLoading = true;
    notifyListeners();

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/webdav');
      final response =
          await _sendPostRequest(uri, jsonBody: connection.toJson());

      if (response.statusCode != 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(body['message'] ?? 'Failed to add WebDAV');
      }

      await refreshManagement(userInitiated: true);
    } catch (e) {
      _managementErrorMessage = e.toString();
    } finally {
      _isManagementLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeWebDAVConnection(String name) async {
    final host = activeHost;
    if (host == null) return;

    _isManagementLoading = true;
    notifyListeners();

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/webdav')
          .replace(queryParameters: {'name': name});
      final response = await _sendDeleteRequest(uri);

      if (response.statusCode != 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(body['message'] ?? 'Failed to remove WebDAV');
      }

      await refreshManagement(userInitiated: true);
    } catch (e) {
      _managementErrorMessage = e.toString();
    } finally {
      _isManagementLoading = false;
      notifyListeners();
    }
  }

  // --- SMB Methods ---

  Future<void> addSMBConnection(SMBConnection connection) async {
    final host = activeHost;
    if (host == null) return;

    _isManagementLoading = true;
    notifyListeners();

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/smb');
      final response =
          await _sendPostRequest(uri, jsonBody: connection.toJson());

      if (response.statusCode != 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(body['message'] ?? 'Failed to add SMB');
      }

      await refreshManagement(userInitiated: true);
    } catch (e) {
      _managementErrorMessage = e.toString();
    } finally {
      _isManagementLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeSMBConnection(String name) async {
    final host = activeHost;
    if (host == null) return;

    _isManagementLoading = true;
    notifyListeners();

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/manage/smb')
          .replace(queryParameters: {'name': name});
      final response = await _sendDeleteRequest(uri);

      if (response.statusCode != 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(body['message'] ?? 'Failed to remove SMB');
      }

      await refreshManagement(userInitiated: true);
    } catch (e) {
      _managementErrorMessage = e.toString();
    } finally {
      _isManagementLoading = false;
      notifyListeners();
    }
  }

  String _buildManagementFriendlyError(Object e, SharedRemoteHost host) {
    if (e is TimeoutException) {
      return '连接超时，请检查网络或主机是否在线';
    }

    final message = e.toString();
    if (message.contains('SocketException') || message.contains('Connection')) {
      if (message.contains('No route to host') ||
          message.contains('errno = 65')) {
        return '无法连接到主机 ${host.baseUrl}\n错误详情: $e';
      }
      if (message.contains('Connection refused')) {
        return '连接被拒绝，请确认主机已开启远程访问服务';
      }
      if (message.contains('timed out') ||
          message.contains('TimeoutException')) {
        return '连接超时，请检查网络连接或主机是否在线';
      }
      return '网络连接失败: $e';
    }

    if (message.contains('HTTP')) {
      return '服务器响应错误: $e';
    }

    return '同步失败: $e';
  }

  void clearManagementError() {
    _managementErrorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
