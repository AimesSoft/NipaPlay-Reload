import 'media_server_playback.dart';
import 'watch_history_model.dart';

enum PlaybackSourceKind {
  localLibrary,
  localFile,
  sharedRemoteAnime,
  sharedRemoteDirectory,
  webDav,
  smb,
  dandanplayRemote,
  jellyfin,
  emby,
  networkStream,
}

class PlaybackDetailEpisode {
  const PlaybackDetailEpisode({
    required this.id,
    required this.videoPath,
    required this.title,
    this.subtitle,
    this.animeId,
    this.episodeId,
    this.historyItem,
    this.actualPlayUrl,
    this.playbackSession,
    this.progress,
  });

  final String id;
  final String videoPath;
  final String title;
  final String? subtitle;
  final int? animeId;
  final int? episodeId;
  final WatchHistoryItem? historyItem;
  final String? actualPlayUrl;
  final PlaybackSession? playbackSession;
  final double? progress;
}

typedef PlaybackDetailEpisodeLoader = Future<List<PlaybackDetailEpisode>>
    Function();

/// Keeps one playlist snapshot per active playback source and coalesces
/// concurrent loads. Failed loads are not cached, so the end-of-playback
/// check can retry if background preloading failed temporarily.
class PlaybackPlaylistCache {
  String? _sourceKey;
  List<PlaybackDetailEpisode>? _episodes;
  Future<List<PlaybackDetailEpisode>>? _pendingLoad;
  int _generation = 0;

  Future<List<PlaybackDetailEpisode>> load({
    required String sourceKey,
    required PlaybackDetailEpisodeLoader loader,
  }) async {
    if (_sourceKey != sourceKey) {
      invalidate();
      _sourceKey = sourceKey;
    }

    final cached = _episodes;
    if (cached != null) return cached;

    final pending = _pendingLoad;
    if (pending != null) return pending;

    final loadGeneration = _generation;
    late final Future<List<PlaybackDetailEpisode>> loadFuture;
    loadFuture = Future<List<PlaybackDetailEpisode>>.sync(loader).then(
      (episodes) {
        final snapshot = List<PlaybackDetailEpisode>.unmodifiable(episodes);
        if (_generation == loadGeneration && _sourceKey == sourceKey) {
          _episodes = snapshot;
        }
        return snapshot;
      },
    );
    _pendingLoad = loadFuture;

    try {
      return await loadFuture;
    } finally {
      if (identical(_pendingLoad, loadFuture)) {
        _pendingLoad = null;
      }
    }
  }

  void invalidate() {
    _generation++;
    _sourceKey = null;
    _episodes = null;
    _pendingLoad = null;
  }
}

class PlaybackPlaylist {
  const PlaybackPlaylist._();

  static PlaybackDetailEpisode? next(
    List<PlaybackDetailEpisode> episodes,
    String currentPath, {
    bool Function(String candidate, String current)? isSamePath,
  }) {
    final matches = isSamePath ?? (candidate, current) => candidate == current;
    final currentIndex = episodes.indexWhere(
      (episode) => matches(episode.videoPath, currentPath),
    );
    if (currentIndex < 0 || currentIndex >= episodes.length - 1) return null;
    return episodes[currentIndex + 1];
  }
}

class PlaybackDetailContext {
  const PlaybackDetailContext({
    required this.sourceKind,
    required this.sourceLabel,
    required this.sourceKey,
    required this.title,
    required this.isIdentified,
    required this.episodeLoader,
    this.subtitle,
    this.summary,
    this.imageUrl,
    this.animeId,
  });

  final PlaybackSourceKind sourceKind;
  final String sourceLabel;
  final String sourceKey;
  final String title;
  final String? subtitle;
  final String? summary;
  final String? imageUrl;
  final int? animeId;
  final bool isIdentified;
  final PlaybackDetailEpisodeLoader episodeLoader;

  String get displayTitle => isIdentified ? title : '未识别';

  bool get usesLocalLibraryDetail =>
      sourceKind == PlaybackSourceKind.localLibrary &&
      animeId != null &&
      animeId! > 0;

  PlaybackDetailContext withAnimeMatch({
    required int animeId,
    String? title,
  }) {
    assert(animeId > 0);
    final matchedTitle = title?.trim();
    final isLocalFile = sourceKind == PlaybackSourceKind.localFile;

    return PlaybackDetailContext(
      sourceKind: isLocalFile ? PlaybackSourceKind.localLibrary : sourceKind,
      sourceLabel: isLocalFile ? '本地媒体库' : sourceLabel,
      sourceKey: '$sourceKey:anime:$animeId',
      title: matchedTitle?.isNotEmpty == true ? matchedTitle! : this.title,
      subtitle: subtitle,
      summary: summary,
      imageUrl: imageUrl,
      animeId: animeId,
      isIdentified: true,
      episodeLoader: episodeLoader,
    );
  }
}
