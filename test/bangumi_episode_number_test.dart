import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/bangumi_model.dart';

void main() {
  test('an episode keeps the number dandanplay gives, through the cache', () {
    final anime = BangumiAnime.fromDandanplayDetail({
      'animeId': 18779,
      'animeTitle': '躲在超市后门抽烟的两人',
      'episodes': [
        {'episodeId': 187790001, 'episodeTitle': '第1话', 'episodeNumber': '1'},
        {'episodeId': 187790011, 'episodeTitle': '总集篇', 'episodeNumber': 'S1'},
        {'episodeId': 187790012, 'episodeTitle': '第11话'},
      ],
    });
    expect([for (final e in anime.episodeList!) e.episodeNumber],
        ['1', 'S1', null]);
    final cached = BangumiAnime.fromJson(anime.toJson());
    expect([for (final e in cached.episodeList!) e.episodeNumber],
        ['1', 'S1', null]);
  });
}
