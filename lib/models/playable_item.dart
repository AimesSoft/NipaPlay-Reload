import 'media_library_scope.dart';
import 'watch_history_model.dart';
import 'media_server_playback.dart';
import 'playback_detail_context.dart';

class PlayableItem {
  final MediaLibraryScope? mediaLibraryScope;
  final String videoPath;
  final String? title;
  final String? subtitle;
  final int? animeId;
  final int? episodeId;
  final WatchHistoryItem? historyItem;
  final String? actualPlayUrl;
  final PlaybackSession? playbackSession;
  final PlaybackDetailContext? detailContext;
  final String? mediaKey;

  PlayableItem({
    required this.videoPath,
    this.mediaLibraryScope,
    this.title,
    this.subtitle,
    this.animeId,
    this.episodeId,
    this.historyItem,
    this.actualPlayUrl,
    this.playbackSession,
    this.detailContext,
    this.mediaKey,
  });

  factory PlayableItem.fromDetailEpisode(
    PlaybackDetailEpisode episode, {
    required PlaybackDetailContext detailContext,
  }) {
    return PlayableItem(
      mediaLibraryScope: detailContext.mediaLibraryScope,
      videoPath: episode.videoPath,
      title: episode.title,
      subtitle: episode.subtitle,
      animeId: episode.animeId,
      episodeId: episode.episodeId,
      historyItem: episode.historyItem,
      actualPlayUrl: episode.actualPlayUrl,
      playbackSession: episode.playbackSession,
      mediaKey: episode.mediaKey,
      detailContext: !detailContext.isIdentified &&
              episode.animeId != null &&
              episode.animeId! > 0
          ? null
          : detailContext,
    );
  }

  PlayableItem withDetailContext(PlaybackDetailContext context) {
    return PlayableItem(
      mediaLibraryScope: mediaLibraryScope ?? context.mediaLibraryScope,
      videoPath: videoPath,
      title: title,
      subtitle: subtitle,
      animeId: animeId,
      episodeId: episodeId,
      historyItem: historyItem,
      actualPlayUrl: actualPlayUrl,
      playbackSession: playbackSession,
      detailContext: context,
      mediaKey: mediaKey,
    );
  }
}

extension PlayableItemLibraryScope on PlayableItem {
  PlayableItem withMediaLibraryScope(MediaLibraryScope? scope) => PlayableItem(
        videoPath: videoPath,
        title: title,
        subtitle: subtitle,
        animeId: animeId,
        episodeId: episodeId,
        historyItem: historyItem,
        actualPlayUrl: actualPlayUrl,
        playbackSession: playbackSession,
        detailContext: detailContext,
        mediaKey: mediaKey,
        mediaLibraryScope: scope,
      );
}
