import 'watch_history_model.dart';
import 'media_server_playback.dart';
import 'playback_detail_context.dart';

class PlayableItem {
  final String videoPath;
  final String? title;
  final String? subtitle;
  final int? animeId;
  final int? episodeId;
  final WatchHistoryItem? historyItem;
  final String? actualPlayUrl;
  final PlaybackSession? playbackSession;
  final PlaybackDetailContext? detailContext;

  PlayableItem({
    required this.videoPath,
    this.title,
    this.subtitle,
    this.animeId,
    this.episodeId,
    this.historyItem,
    this.actualPlayUrl,
    this.playbackSession,
    this.detailContext,
  });

  factory PlayableItem.fromDetailEpisode(
    PlaybackDetailEpisode episode, {
    required PlaybackDetailContext detailContext,
  }) {
    return PlayableItem(
      videoPath: episode.videoPath,
      title: episode.title,
      subtitle: episode.subtitle,
      animeId: episode.animeId,
      episodeId: episode.episodeId,
      historyItem: episode.historyItem,
      actualPlayUrl: episode.actualPlayUrl,
      playbackSession: episode.playbackSession,
      detailContext: !detailContext.isIdentified &&
              episode.animeId != null &&
              episode.animeId! > 0
          ? null
          : detailContext,
    );
  }

  PlayableItem withDetailContext(PlaybackDetailContext context) {
    return PlayableItem(
      videoPath: videoPath,
      title: title,
      subtitle: subtitle,
      animeId: animeId,
      episodeId: episodeId,
      historyItem: historyItem,
      actualPlayUrl: actualPlayUrl,
      playbackSession: playbackSession,
      detailContext: context,
    );
  }
}
