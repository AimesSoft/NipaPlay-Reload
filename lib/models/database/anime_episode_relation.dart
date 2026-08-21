
// lib/models/database/anime_episode_relation.dart


class DbAnimeEpisodeRelation {

  int animeId;
  Iterable<int> episodeIds;

  DbAnimeEpisodeRelation({
    required this.animeId,
    required this.episodeIds,
  });
}


enum DbAnimeEpisodeRelationType {
  common,
  dandanplay,
  bangumi,
}


// 别名
typedef AniEpiRlt     = DbAnimeEpisodeRelation;
typedef AniEpiRltType = DbAnimeEpisodeRelationType;
