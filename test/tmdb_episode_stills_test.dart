import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/tmdb_artwork.dart';
import 'package:nipaplay/models/tmdb_episode_stills.dart';
import 'package:nipaplay/services/tmdb_media_artwork_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final body = (jsonDecode(
          File('test/fixtures/tmdb/makeine_season_1.json').readAsStringSync())
      as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  final rows = (body['episodes'] as List).cast<Map<String, dynamic>>();
  BangumiAnime anime(
          {List<EpisodeData>? episodes, String? date = '2024-07-14'}) =>
      BangumiAnime(
          id: 9,
          name: '败犬女主太多了！',
          nameCn: '败犬女主太多了！',
          imageUrl: '',
          airDate: date,
          episodeList: episodes ??
              [
                EpisodeData(id: 101, title: '第1话'),
                EpisodeData(id: 102, title: '第2话'),
              ]);
  final season = {
    'id': body['id'],
    'season_number': 1,
    'air_date': '2024-07-14'
  };

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('real gateway stills map by episode identity even when reversed', () {
    final result = matchTmdbEpisodeStills(
        anime(episodes: [
          EpisodeData(id: 102, title: '第2话'),
          EpisodeData(id: 101, title: '第1话'),
          EpisodeData(id: 999, title: '第99话'),
        ]),
        rows,
        (path) => validTmdbImagePath(path) ? path : null);
    expect(result, {
      101: '/zddmlyXsak6TaMrYOjwweopZwiY.jpg',
      102: '/xCqsia9e9j49LurHZC07NXFSbvh.jpg'
    });
  });

  test('selects sequel by premiere and rejects ambiguous seasons', () {
    final second = {...season, 'id': 99, 'season_number': 2};
    expect(
        selectTmdbStillSeason(anime(), [
          {...season, 'air_date': '2020-01-01'},
          second
        ]),
        second);
    expect(
        selectTmdbStillSeason(anime(date: '2024-03-01'), [
          season,
          {...second, 'air_date': '2024-10-01'}
        ]),
        isNull);
    expect(selectTmdbStillSeason(anime(date: '2025-01-01'), [season]), isNull);
  });

  test('dates handle offsets and missing or invalid stills keep placeholders',
      () {
    final result = matchTmdbEpisodeStills(
        anime(episodes: [
          EpisodeData(id: 1, title: '第13话', airDate: '2024-07-14'),
          EpisodeData(id: 2, title: '第2话', airDate: '2020-01-01'),
          EpisodeData(id: 3, title: '第3话'),
          EpisodeData(id: 4, title: '第4话'),
        ]),
        [
          rows.first,
          {...rows[1]},
          {...rows[2], 'still_path': null},
          {...rows[3], 'still_path': '/../bad.jpg'},
        ],
        (path) => validTmdbImagePath(path) ? path : null);
    expect(result.keys, [1]);
  });

  test('season fetches coalesce, persist across instances and retry failures',
      () async {
    final requests = <String>[];
    var fail = false;
    TmdbMediaArtworkService service() => TmdbMediaArtworkService(
        gateway: Uri.parse('https://gateway.test/metadata/v1/'),
        client: MockClient((request) async {
          requests.add(request.url.path);
          final path = request.url.path;
          if (path.endsWith('/seasons/1') && fail) {
            return http.Response('', 503);
          }
          final data = path.endsWith('/seasons/1')
              ? body
              : path.endsWith('/configuration')
                  ? {
                      'images': {
                        'secure_base_url': 'https://image.tmdb.org/t/p/',
                        for (final kind in [
                          'poster',
                          'backdrop',
                          'logo',
                          'still'
                        ])
                          '${kind}_sizes': ['w300', 'original']
                      }
                    }
                  : {
                      'id': 241535,
                      'seasons': [season]
                    };
          return http.Response(
              jsonEncode({'schema_version': 1, 'data': data}), 200,
              headers: {'content-type': 'application/json'});
        }));
    const ref = TmdbReference('tv', 241535);
    final first = service();
    fail = true;
    expect(await first.resolveEpisodeStills(anime(), ref), isEmpty);
    fail = false;
    final results = await Future.wait([
      first.resolveEpisodeStills(anime(), ref),
      first.resolveEpisodeStills(anime(), ref),
    ]);
    expect(results.first[101],
        'https://image.tmdb.org/t/p/w300/zddmlyXsak6TaMrYOjwweopZwiY.jpg');
    expect(results.last, results.first);
    expect(requests.where((p) => p.endsWith('/seasons/1')), hasLength(2));
    expect(await service().resolveEpisodeStills(anime(), ref), results.first);
    expect(requests.where((p) => p.endsWith('/seasons/1')), hasLength(2));
    expect(
        await first.resolveEpisodeStills(
            anime(), const TmdbReference('movie', 1)),
        isEmpty);
  });
}
