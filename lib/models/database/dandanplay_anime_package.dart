

import 'package:nipaplay/models/database/dandanplay_anime_record.dart';
import 'package:nipaplay/models/database/dandanplay_episode_record.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/printable.dart';


class DbDandanplayAnimePackage implements Printable {

  final DbDandanplayAnimeRecord        anime;
  final Set<DbDandanplayEpisodeRecord> episodes;

  DbDandanplayAnimePackage({
    required this.anime,
    required this.episodes,
  });

  @override
  String toPrintString({
    String indent = '',
    bool enableColor = false,
  }) {
    final lines = <String>[
      '$indent${color('Dandanplay Anime Package', ColorCode.boldCyan, enableColor)}',
      '$indent  Anime: ID=${anime.dandanplayAnimeId}, Title=${anime.title ?? '-'}',
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
        '$indent    ID=${episode.dandanplayEpisodeId}, '
        'Sort=${episode.sortOrder ?? '-'}, Title=${episode.title ?? '-'}',
      );
    }
    return lines.join('\n');
  }
}
