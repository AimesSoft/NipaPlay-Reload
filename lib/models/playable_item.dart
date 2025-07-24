import 'watch_history_model.dart';

class PlayableItem {
  final String videoPath;
  final String? title;
  final String? subtitle;
  final int? animeId;
  final int? episodeId;
  final WatchHistoryItem? historyItem;
  final String? actualPlayUrl;

  PlayableItem({
    required this.videoPath,
    this.title,
    this.subtitle,
    this.animeId,
    this.episodeId,
    this.historyItem,
    this.actualPlayUrl,
  });
}
