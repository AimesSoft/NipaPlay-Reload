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
