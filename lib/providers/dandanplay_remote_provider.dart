import 'package:flutter/foundation.dart';

import 'package:nipaplay/models/dandanplay_remote_model.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';

class DandanplayRemoteProvider extends ChangeNotifier {
  DandanplayRemoteProvider() {
    _service.addConnectionStateListener(_handleConnectionChange);
  }

  final DandanplayRemoteService _service = DandanplayRemoteService.instance;

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _errorMessage;
  List<DandanplayRemoteEpisode> _episodes = [];
  List<DandanplayRemoteAnimeGroup> _animeGroups = [];

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isConnected => _service.isConnected;
  String? get serverUrl => _service.serverUrl;
  bool get tokenRequired => _service.tokenRequired;
  String? get errorMessage => _errorMessage ?? _service.lastError;
  DateTime? get lastSyncedAt => _service.lastSyncedAt;
  List<DandanplayRemoteEpisode> get episodes => List.unmodifiable(_episodes);
  List<DandanplayRemoteAnimeGroup> get animeGroups =>
      List.unmodifiable(_animeGroups);

  String? buildStreamUrlForEpisode(DandanplayRemoteEpisode episode) {
    final hash = episode.hash.isNotEmpty ? episode.hash : null;
    final entryId = episode.entryId.isNotEmpty ? episode.entryId : null;
    return _service.buildEpisodeStreamUrl(hash: hash, entryId: entryId);
  }

  String? buildImageUrl(String hash) {
    if (hash.isEmpty) return null;
    return _service.buildImageUrl(hash);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _setLoading(true);
    try {
      await _service.loadSavedSettings(backgroundRefresh: true);
      _episodes = _service.cachedEpisodes;
      _rebuildGroups();
    } finally {
      _isInitialized = true;
      _setLoading(false);
    }
  }

  Future<bool> connect(String baseUrl, {String? token}) async {
    _setLoading(true);
    try {
      final success = await _service.connect(baseUrl, token: token);
      _episodes = _service.cachedEpisodes;
      _rebuildGroups();
      _errorMessage = null;
      return success;
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> disconnect() async {
    _setLoading(true);
    try {
      await _service.disconnect();
      _episodes = [];
      _animeGroups = [];
      _errorMessage = null;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refresh() async {
    if (!_service.isConnected) {
      throw Exception('尚未连接到弹弹play远程服务');
    }
    _setLoading(true);
    try {
      _episodes = await _service.refreshLibrary(force: true);
      _rebuildGroups();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _handleConnectionChange(bool connected) {
    if (connected) {
      _episodes = _service.cachedEpisodes;
      _rebuildGroups();
      _errorMessage = null;
    } else {
      _episodes = [];
      _animeGroups = [];
      notifyListeners();
    }
  }

  void _rebuildGroups() {
    final Map<int?, List<DandanplayRemoteEpisode>> grouped = {};
    for (final episode in _episodes) {
      grouped.putIfAbsent(episode.animeId, () => []).add(episode);
    }

    final List<DandanplayRemoteAnimeGroup> groups = [];
    grouped.forEach((animeId, items) {
      items.sort((a, b) {
        final aTime =
            a.lastPlay ?? a.created ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.lastPlay ?? b.created ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });
      final latest = items.last;
      groups.add(DandanplayRemoteAnimeGroup(
        animeId: animeId,
        title: latest.animeTitle,
        episodes: List.unmodifiable(items),
        latestPlayTime: latest.lastPlay ?? latest.created,
      ));
    });

    groups.sort((a, b) {
      final aTime = a.latestPlayTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.latestPlayTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    _animeGroups = groups;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.removeConnectionStateListener(_handleConnectionChange);
    super.dispose();
  }
}
