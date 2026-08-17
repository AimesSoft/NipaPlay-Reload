

import 'package:nipaplay/models/database/dandanplay_anime_record.dart';
import 'package:nipaplay/models/database/dandanplay_episode_record.dart';


class DbDandanplayAnimePackage {

  final DbDandanplayAnimeRecord        anime;
  final Set<DbDandanplayEpisodeRecord> episodes;

  DbDandanplayAnimePackage({
    required this.anime,
    required this.episodes,
  });
}
