

import 'package:nipaplay/models/database/bangumi_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_episode_record.dart';


class DbBangumiAnimePackage {
  final DbBangumiAnimeRecord        anime;
  final Set<DbBangumiEpisodeRecord> episodes;

  DbBangumiAnimePackage({
    required this.anime,
    required this.episodes,
  });
}
