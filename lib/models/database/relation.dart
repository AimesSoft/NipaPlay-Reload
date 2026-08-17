
// lib/models/database/relation.dart

class DandanplayAndBangumiAnimeId {

  final int dandanplayAnimeId;
  final int bangumiAnimeId;

  DandanplayAndBangumiAnimeId({
    required this.dandanplayAnimeId,
    required this.bangumiAnimeId,
  });

  Map<String, Object> toMap() => <String, Object>{
    'dandanplay_anime_id': dandanplayAnimeId,
    'bangumi_anime_id': bangumiAnimeId,
  };
}


class DandanplayAndBangumiEpisodeId {

  final int dandanplayEpisodeId;
  final int bangumiEpisodeId;

  DandanplayAndBangumiEpisodeId({
    required this.dandanplayEpisodeId,
    required this.bangumiEpisodeId,
  });

  Map<String, Object> toMap() => <String, Object>{
    'dandanplay_episode_id': dandanplayEpisodeId,
    'bangumi_episode_id': bangumiEpisodeId,
  };
}