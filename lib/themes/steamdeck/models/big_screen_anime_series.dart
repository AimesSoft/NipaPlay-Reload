import 'package:nipaplay/models/watch_history_model.dart';

class BigScreenAnimeSeries {
  const BigScreenAnimeSeries({
    required this.key,
    required this.title,
    required this.episodes,
    this.animeId,
    this.coverPath = '',
  });

  final String key;
  final int? animeId;
  final String title;
  final String coverPath;
  final List<WatchHistoryItem> episodes;

  WatchHistoryItem? get latestEpisode {
    if (episodes.isEmpty) {
      return null;
    }
    return episodes.first;
  }

  BigScreenAnimeSeries copyWith({
    String? key,
    int? animeId,
    String? title,
    String? coverPath,
    List<WatchHistoryItem>? episodes,
  }) {
    return BigScreenAnimeSeries(
      key: key ?? this.key,
      animeId: animeId ?? this.animeId,
      title: title ?? this.title,
      coverPath: coverPath ?? this.coverPath,
      episodes: episodes ?? this.episodes,
    );
  }
}
