import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';

class SharedRemoteLibraryProvider extends ChangeNotifier {
  static const String _hostsPrefsKey = 'shared_remote_hosts';
  static const String _activeHostIdKey = 'shared_remote_active_host';

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
  List<SharedRemoteAnimeSummary> get animeSummaries => List.unmodifiable(_animeSummaries);
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  bool get hasActiveHost => _activeHostId != null && _hosts.any((h) => h.id == _activeHostId);

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
    final host = SharedRemoteHost(id: id, displayName: displayName, baseUrl: normalizedUrl);
    _hosts.add(host);
    _activeHostId = id;
    await _persistHosts();
    notifyListeners();
    await refreshLibrary();
    return host;
  }

  Future<void> removeHost(String hostId) async {
    _hosts.removeWhere((host) => host.id == hostId);
    if (_activeHostId == hostId) {
      _activeHostId = _hosts.isNotEmpty ? _hosts.first.id : null;
      _animeSummaries = [];
      _episodeCache.clear();
    }
    await _persistHosts();
    notifyListeners();
    if (_activeHostId != null) {
      await refreshLibrary();
    }
  }

  Future<void> setActiveHost(String hostId) async {
    if (_activeHostId == hostId) return;
    if (!_hosts.any((host) => host.id == hostId)) return;
    _activeHostId = hostId;
    _animeSummaries = [];
    _episodeCache.clear();
    await _persistHosts();
    notifyListeners();
    await refreshLibrary();
  }

  Future<void> refreshLibrary() async {
    final host = activeHost;
    if (host == null) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/share/animes');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final payload = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final items = (payload['items'] ?? payload['data'] ?? []) as List<dynamic>;
      _animeSummaries = items
          .map((item) => SharedRemoteAnimeSummary.fromJson(item as Map<String, dynamic>))
          .toList();
      _animeSummaries.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      _episodeCache.clear();
      _updateHostStatus(host.id, isOnline: true, lastError: null);
    } catch (e) {
      _errorMessage = '同步远程媒体库失败: $e';
      _updateHostStatus(host.id, isOnline: false, lastError: e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
      await _persistHosts();
    }
  }

  Future<List<SharedRemoteEpisode>> loadAnimeEpisodes(int animeId, {bool force = false}) async {
    if (!force && _episodeCache.containsKey(animeId)) {
      return _episodeCache[animeId]!;
    }

    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程媒体库');
    }

    final uri = Uri.parse('${host.baseUrl}/api/media/local/share/animes/$animeId');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final payload = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final episodes = (payload['data']?['episodes'] ?? payload['episodes'] ?? []) as List<dynamic>;
    final episodeList = episodes
        .map((episode) => SharedRemoteEpisode.fromJson(episode as Map<String, dynamic>))
        .toList();
    _episodeCache[animeId] = episodeList;

    // 如果返回包含 anime 信息，但 summary 还没更新，则更新一下卡片显示
    final data = payload['data']?['anime'] ?? payload['anime'];
    if (data is Map<String, dynamic>) {
      final summaryIndex = _animeSummaries.indexWhere((element) => element.animeId == animeId);
      if (summaryIndex != -1 && data['lastWatchTime'] != null) {
        final updatedSummary = SharedRemoteAnimeSummary.fromJson({
          'animeId': animeId,
          'name': data['name'] ?? _animeSummaries[summaryIndex].name,
          'nameCn': data['nameCn'] ?? _animeSummaries[summaryIndex].nameCn,
          'summary': data['summary'] ?? _animeSummaries[summaryIndex].summary,
          'imageUrl': data['imageUrl'] ?? _animeSummaries[summaryIndex].imageUrl,
          'lastWatchTime': data['lastWatchTime'],
          'episodeCount': data['episodeCount'] ?? episodeList.length,
          'hasMissingFiles': data['hasMissingFiles'] ?? false,
        });
        _animeSummaries[summaryIndex] = updatedSummary;
        notifyListeners();
      }
    }

    return episodeList;
  }

  Uri buildStreamUri(SharedRemoteEpisode episode) {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程媒体库');
    }
    return Uri.parse(host.baseUrl).resolve(episode.streamPath.startsWith('/')
        ? episode.streamPath.substring(1)
        : episode.streamPath);
  }

  WatchHistoryItem buildWatchHistoryItem({
    required SharedRemoteAnimeSummary anime,
    required SharedRemoteEpisode episode,
  }) {
    final streamUri = buildStreamUri(episode).toString();
    return WatchHistoryItem(
      filePath: streamUri,
      animeName: anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name,
      episodeTitle: episode.title,
      episodeId: episode.episodeId,
      animeId: episode.animeId ?? anime.animeId,
      watchProgress: episode.progress ?? 0,
      lastPosition: 0,
      duration: episode.duration ?? 0,
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
      episodeId: episode.shareId.hashCode,
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
      await refreshLibrary();
    }
    await _persistHosts();
    notifyListeners();
  }

  String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
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

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
