

import 'package:nipaplay/models/database/bangumi_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_episode_record.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/printable.dart';


class DbBangumiAnimePackage implements Printable {
  final DbBangumiAnimeRecord        anime;
  final Set<DbBangumiEpisodeRecord> episodes;

  DbBangumiAnimePackage({
    required this.anime,
    required this.episodes,
  });

  @override
  String toPrintString({
    String indent = '',
    bool enableColor = false,
  }) {
    final lines = <String>[
      '$indent${color('Bangumi Anime Package', ColorCode.boldCyan, enableColor)}',
      '$indent  Anime: ID=${anime.bangumiAnimeId}, Title=${anime.title ?? '-'}',
      '$indent  Episodes (${episodes.length}):',
    ];
    final sortedEpisodes = episodes.toList()
      ..sort(
        (left, right) => (left.sortOrder ?? double.infinity).compareTo(
          right.sortOrder ?? double.infinity,
        ),
      );
    for (final episode in sortedEpisodes) {
      lines.add(
        '$indent    ID=${episode.bangumiEpisodeId}, '
        'Sort=${episode.sortOrder ?? '-'}, Title=${episode.title ?? '-'}',
      );
    }
    return lines.join('\n');
  }
}
