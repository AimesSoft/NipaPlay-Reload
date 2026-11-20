import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/tmdb_artwork.dart';
import 'package:nipaplay/models/tmdb_logo_brightness.dart';
import 'package:nipaplay/services/tmdb_media_artwork_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> source(
        {List<String> links = const [
          'https://www.themoviedb.org/tv/42-show'
        ]}) =>
    {
      'animeId': 9,
      'animeTitle': '作品 第二季',
      'type': 'tvseries',
      'imageUrl': '',
      'titles': [
        {'title': '作品 第二季', 'language': '主标题'}
      ],
      'seasons': [
        {'airDate': '2024-02-29'}
      ],
      'onlineDatabases': [
        for (final url in links) {'name': 'TMDB', 'url': url}
      ],
    };
Map<String, dynamic> images({int id = 42}) => {
      'id': id,
      'backdrops': [
        {
          'file_path': '/zh.jpg',
          'iso_639_1': 'zh',
          'width': 3840,
          'vote_average': 10
        },
        {
          'file_path': '/clean.jpg',
          'iso_639_1': null,
          'width': 1920,
          'vote_average': 1
        },
      ],
      'logos': [
        {
          'file_path': '/zh.png',
          'iso_639_1': 'zh',
          'width': 1000,
          'vote_average': 10
        },
        {
          'file_path': '/ja.png',
          'iso_639_1': 'ja',
          'width': 1000,
          'vote_average': 1
        },
      ],
    };
Map<String, dynamic> work(int id,
        {List<Map<String, dynamic>> seasons = const []}) =>
    {
      'id': id,
      'name': '作品',
      'original_language': 'ja',
      'seasons': seasons,
      'backdrop_path': '/root.jpg',
    };
final configuration = {
  'images': {
    'secure_base_url': 'https://image.tmdb.org/t/p/',
    'poster_sizes': ['w500', 'w780', 'original'],
    'backdrop_sizes': ['w780', 'w1280', 'original'],
    'logo_sizes': ['w500', 'original'],
    'still_sizes': ['w300', 'original']
  },
};
http.Response reply(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'schema_version': 1, 'data': data}), 200,
        headers: {'content-type': 'application/json'});
TmdbMediaArtworkService service(List<Uri> requests,
        {Map<String, dynamic> Function(http.Request)? search,
        Map<String, dynamic>? imageBody,
        Map<String, dynamic>? workBody,
        bool failImages = false,
        Future<BangumiAnime> Function(int)? loadDetails,
        Future<TmdbLogoBrightness?> Function(String)? logoBrightness}) =>
    TmdbMediaArtworkService(
        gateway: Uri.parse('https://gateway.test/metadata/v1/'),
        loadDetails: loadDetails,
        logoBrightness:
            logoBrightness ?? (_) async => const TmdbLogoBrightness(0.8, 1),
        bangumiServer: () async => 'https://bangumi.test',
        client: MockClient((request) async {
          requests.add(request.url);
          final path = request.url.path;
          if (path.endsWith('configuration')) return reply(configuration);
          if (path.endsWith('/images')) {
            return failImages
                ? http.Response('', 503)
                : reply(imageBody ?? images());
          }
          if (path.endsWith('/search')) {
            return reply(search?.call(request) ??
                {'page': 1, 'total_pages': 1, 'results': []});
          }
          if (path.startsWith('/v0/subjects/')) {
            return http.Response(
                jsonEncode(
                    {'name_cn': '作品 第二季', 'name': '原名', 'date': '2024-02-29'}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          return reply(workBody ?? work(42));
        }));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('provider evidence survives API parsing, copying and disk JSON', () {
    final anime = BangumiAnime.fromDandanplayDetail(source());
    final cached = BangumiAnime.fromJson(
        jsonDecode(jsonEncode(anime.copyWith(nameCn: '作品').toJson()))
            as Map<String, dynamic>);
    expect(cached.onlineDatabases?.single['url'], endsWith('/tv/42-show'));
    expect(cached.dandanplayType, 'tvseries');
    expect(cached.sourceAirDates, ['2024-02-29']);
  });

  test('backdrop fallback order matches the requested provider precedence', () {
    expect(
        mediaDetailBackdropCandidates(
            custom: ' custom ',
            tmdb: 'tmdb',
            bangumiLarge: 'bgm',
            poster: 'poster'),
        ['custom', 'tmdb', 'bgm', 'poster']);
    expect(
        mediaDetailBackdropCandidates(
            tmdb: '', bangumiLarge: 'bgm', poster: 'bgm'),
        ['bgm']);
  });

  test('TMDB links preserve movie/TV identity and reject untrusted paths', () {
    expect(
        TmdbReference.fromUrl(
                'https://www.themoviedb.org/movie/42-film?language=ja')
            ?.key,
        'movie/42');
    for (final url in [
      'https://evil.test/tv/42',
      'https://themoviedb.org/tv/42/season/1',
      'https://user@themoviedb.org/tv/42',
      'https://themoviedb.org/tv/0'
    ]) {
      expect(TmdbReference.fromUrl(url), isNull);
    }
  });

  test('Erika artwork fixture: clean backdrop and original-language logo win',
      () {
    final assets =
        TmdbImageAsset.parse(const TmdbReference('tv', 42), images());
    expect(tmdbImageLanguages('zh-CN', 'ja'), ['zh', 'ja', 'en', 'null']);
    expect(tmdbImageLanguages('zh-CN', 'ja', logo: true),
        ['ja', 'zh', 'en', 'null']);
    expect(
        chooseTmdbImage(
                assets, 'backdrop', tmdbImageLanguages('zh-CN', 'ja'), 1920)
            ?.path,
        '/clean.jpg');
    expect(
        chooseTmdbImage(assets, 'logo',
                tmdbImageLanguages('zh-CN', 'ja', logo: true), 640)
            ?.path,
        '/ja.png');
    expect(
        () => TmdbImageAsset.parse(const TmdbReference('movie', 9), images()),
        throwsFormatException);
  });

  test('real Makeine images match Erika Rust selection exactly', () {
    final body = jsonDecode(
            File('test/fixtures/tmdb/makeine_images.json').readAsStringSync())
        as Map<String, dynamic>;
    final assets =
        TmdbImageAsset.parse(const TmdbReference('tv', 241535), body);
    expect(
        chooseTmdbImage(
                assets, 'backdrop', tmdbImageLanguages('zh-CN', 'ja'), 1920)
            ?.path,
        '/7mjnk0QfutRJgHKpz9yyyqI62wo.jpg');
    expect(
        chooseTmdbImage(assets, 'logo',
                tmdbImageLanguages('zh-CN', 'ja', logo: true), 640)
            ?.path,
        '/vSfok0HM6J0Wj86DMb7AOPiWb8O.png');
  });

  test(
      'renditions use the largest available width when below target, SVG stays original',
      () {
    final config = TmdbImageConfiguration.parse(configuration);
    expect(
        config.url(
            const TmdbImageAsset(kind: 'backdrop', path: '/b.jpg'), 1920),
        endsWith('/w1280/b.jpg'));
    expect(config.url(const TmdbImageAsset(kind: 'logo', path: '/l.svg'), 1000),
        endsWith('/original/l.svg'));
  });

  test(
      'direct link bypasses search; repeat and restart reuse persisted artwork',
      () async {
    final requests = <Uri>[];
    final anime = BangumiAnime.fromDandanplayDetail(source());
    final instance = service(requests);
    final results =
        await Future.wait([instance.resolve(anime), instance.resolve(anime)]);
    expect(results.first?.reference.key, 'tv/42');
    expect(results.first?.backdropUrl, endsWith('/w1280/clean.jpg'));
    expect(results.first?.logoUrl, endsWith('/w500/ja.png'));
    expect(requests.any((uri) => uri.path.endsWith('/search')), isFalse);
    expect(requests.where((u) => u.path.endsWith('/images')), hasLength(1));
    final before = requests.length;
    await service(requests).resolve(anime);
    expect(requests.length, before,
        reason: 'restart can reuse disk metadata without contacting TMDB');
  });

  test('conflicting direct references do not search or guess an image',
      () async {
    final requests = <Uri>[];
    final result = await service(requests).resolve(
        BangumiAnime.fromDandanplayDetail(source(links: [
      'https://themoviedb.org/tv/42',
      'https://themoviedb.org/movie/42'
    ])));
    expect(result, isNull);
    expect(requests, isEmpty);
  });

  test('older cache missing links is refreshed before deciding to search',
      () async {
    final requests = <Uri>[];
    var loads = 0;
    final anime = BangumiAnime(id: 9, name: '作品', nameCn: '作品', imageUrl: '');
    final result = await service(requests, loadDetails: (id) async {
      loads++;
      expect(id, 9);
      return BangumiAnime.fromDandanplayDetail(source());
    }).resolve(anime);
    expect(loads, 1);
    expect(result?.reference.key, 'tv/42');
    expect(requests.any((uri) => uri.path.endsWith('/search')), isFalse);
  });

  test('missing or invalid dates never become the current year', () async {
    final requests = <Uri>[];
    final payload = source(links: [])
      ..['seasons'] = [
        {'airDate': '2023-02-29'}
      ];
    final result = await service(requests)
        .resolve(BangumiAnime.fromDandanplayDetail(payload));
    expect(result, isNull);
    expect(requests, isEmpty);
  });

  test('unlinked work searches sequel base and verifies a continuing season',
      () async {
    final requests = <Uri>[];
    final result = await service(requests, search: (r) {
      expect(r.url.queryParameters['query'], '作品');
      expect(r.url.queryParameters['year'], '2024');
      return {
        'page': 1,
        'total_pages': 1,
        'results': [
          {'id': 42, 'name': '作品', 'first_air_date': '2020-01-01'}
        ]
      };
    },
        workBody: work(42, seasons: [
          {'season_number': 2, 'air_date': '2024-02-29'}
        ])).resolve(BangumiAnime.fromDandanplayDetail(source(links: [])));
    expect(result?.reference.key, 'tv/42');
  });

  test('linked Bangumi original title participates in exact-year matching',
      () async {
    final requests = <Uri>[];
    final payload = source(links: [])
      ..['bangumiUrl'] = 'https://bgm.tv/subject/7';
    final result = await service(requests,
        search: (r) => {
              'page': 1,
              'total_pages': 1,
              'results': r.url.queryParameters['query'] == '原名'
                  ? [
                      {'id': 42, 'name': '原名', 'first_air_date': '2024-01-01'}
                    ]
                  : [],
            }).resolve(BangumiAnime.fromDandanplayDetail(payload));
    expect(result?.reference.id, 42);
    expect(requests.any((u) => u.path == '/v0/subjects/7'), isTrue);
  });

  for (final mode in ['ambiguous', 'paginated', 'failed']) {
    test('$mode search cannot prove uniqueness and must not load artwork',
        () async {
      final requests = <Uri>[];
      final result = await service(requests, search: (_) {
        if (mode == 'failed') throw http.ClientException('offline');
        return {
          'page': 1,
          'total_pages': mode == 'paginated' ? 2 : 1,
          'results': [
            {'id': 42, 'name': '作品', 'first_air_date': '2024-01-01'},
            if (mode == 'ambiguous')
              {'id': 43, 'name': '作品', 'first_air_date': '2024-01-01'},
          ]
        };
      }).resolve(BangumiAnime.fromDandanplayDetail(source(links: [])));
      expect(result, isNull);
      expect(requests.any((u) => u.path.contains('/tmdb/')), isFalse);
    });
  }

  test('failed images keep same-work root backdrop and no invented logo',
      () async {
    final result = await service([], failImages: true)
        .resolve(BangumiAnime.fromDandanplayDetail(source()));
    expect(result?.backdropUrl, endsWith('/w1280/root.jpg'));
    expect(result?.logoUrl, isNull);
  });

  test('bright localized logo beats a black original-language logo', () async {
    final inspected = <String>[];
    final result = await service([], logoBrightness: (url) async {
      inspected.add(url);
      return url.endsWith('/ja.png')
          ? const TmdbLogoBrightness(0.005, 0)
          : const TmdbLogoBrightness(1, 1);
    }).resolve(BangumiAnime.fromDandanplayDetail(source()));
    expect(result?.logoUrl, endsWith('/zh.png'));
    expect(inspected, hasLength(2));
  });

  test('real CLANNAD metadata skips its three black Japanese variants',
      () async {
    final images = jsonDecode(
            File('test/fixtures/tmdb/clannad_logos.json').readAsStringSync())
        as Map<String, dynamic>;
    // Measured with the real PNG/SVG bytes, via inspectTmdbLogoBytes.
    const luminance = {
      'kHJyB7Cazpm6tql8SvhD4DDgaL0.png': 0.0,
      'xyujyIzf6kFWZ2stdhIIPG7Kg5U.png': 0.0,
      'LeMfUSxvoLQ0euO2hZl877CLT4.svg': 0.0,
      '4y8COPgQNfhkGBWlzLKdhwtFmMA.png': 0.999,
    };
    final inspected = <String>[];
    final result = await service([], workBody: work(24835), imageBody: images,
        logoBrightness: (url) async {
      final name = Uri.parse(url).pathSegments.last;
      inspected.add(name);
      final l = luminance[name]!;
      return TmdbLogoBrightness(l, l > 0.5 ? 1 : 0);
    }).resolve(BangumiAnime.fromDandanplayDetail(
        source(links: ['https://themoviedb.org/tv/24835'])));
    expect(result?.logoUrl, endsWith('/4y8COPgQNfhkGBWlzLKdhwtFmMA.png'));
    expect(inspected, hasLength(4));
  });

  test('bright original color logo keeps its language preference', () async {
    final inspected = <String>[];
    final result = await service([], logoBrightness: (url) async {
      inspected.add(url);
      return const TmdbLogoBrightness(0.25, 0.5);
    }).resolve(BangumiAnime.fromDandanplayDetail(source()));
    expect(result?.logoUrl, endsWith('/ja.png'));
    expect(inspected, hasLength(1));
  });

  test(
      'old artwork policy refreshes black logo and persists the brighter choice',
      () async {
    final anime = BangumiAnime.fromDandanplayDetail(source());
    await service([]).resolve(anime);
    final prefs = await SharedPreferences.getInstance();
    const key = 'media_detail_tmdb_artwork_v1_9';
    final old = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    old.remove('logoSelectionVersion');
    await prefs.remove('media_detail_tmdb_logo_brightness_v1');
    await prefs.setString(key, jsonEncode(old));
    var inspections = 0;
    final result = await service([], logoBrightness: (url) async {
      inspections++;
      return url.endsWith('/ja.png')
          ? const TmdbLogoBrightness(0, 0)
          : const TmdbLogoBrightness(1, 1);
    }).resolve(anime);
    expect(result?.logoUrl, endsWith('/zh.png'));
    expect(inspections, 2);
    expect(
        (jsonDecode(prefs.getString(key)!) as Map)['logoSelectionVersion'], 2);
    final requests = <Uri>[];
    final reopened = await service(requests,
            logoBrightness: (_) async => throw StateError('must use cache'))
        .resolve(anime);
    expect(reopened?.logoUrl, result?.logoUrl);
    expect(requests, isEmpty);
  });

  test(
      'failed image-list refresh does not mark an old dark logo as re-evaluated',
      () async {
    final anime = BangumiAnime.fromDandanplayDetail(source());
    await service([]).resolve(anime);
    final prefs = await SharedPreferences.getInstance();
    const key = 'media_detail_tmdb_artwork_v1_9';
    final old = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    old.remove('logoSelectionVersion');
    await prefs.setString(key, jsonEncode(old));
    await prefs.remove('media_detail_tmdb_logo_brightness_v1');
    await service([], failImages: true).resolve(anime);
    expect(
        (jsonDecode(prefs.getString(key)!) as Map)['logoSelectionVersion'], 0);
    final refreshed = await service([],
        logoBrightness: (url) async => url.endsWith('/ja.png')
            ? const TmdbLogoBrightness(0, 0)
            : const TmdbLogoBrightness(1, 1)).resolve(anime);
    expect(refreshed?.logoUrl, endsWith('/zh.png'));
  });

  test(
      'brightness cache survives a metadata refresh without downloading logos again',
      () async {
    final anime = BangumiAnime.fromDandanplayDetail(source());
    await service([],
            logoBrightness: (_) async => const TmdbLogoBrightness(1, 1))
        .resolve(anime);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('media_detail_tmdb_artwork_v1_9');
    var inspections = 0;
    final result = await service([], logoBrightness: (_) async {
      inspections++;
      throw StateError('analysis should be cached');
    }).resolve(anime);
    expect(result?.logoUrl, endsWith('/ja.png'));
    expect(inspections, 0);
  });

  test(
      'unavailable logo inspection is retried rather than pinning black for a day',
      () async {
    final anime = BangumiAnime.fromDandanplayDetail(source());
    var ready = false;
    final instance = service([], logoBrightness: (url) async {
      if (!ready) throw StateError('offline');
      return url.endsWith('/ja.png')
          ? const TmdbLogoBrightness(0, 0)
          : const TmdbLogoBrightness(1, 1);
    });
    await instance.resolve(anime);
    ready = true;
    final result = await instance.resolve(anime);
    expect(result?.logoUrl, endsWith('/zh.png'));
  });

  test('empty filtered image response retries without language filter',
      () async {
    final requests = <Uri>[];
    await service(requests, imageBody: {'id': 42})
        .resolve(BangumiAnime.fromDandanplayDetail(source()));
    final imageRequests =
        requests.where((u) => u.path.endsWith('/images')).toList();
    expect(imageRequests, hasLength(2));
    expect(imageRequests.first.queryParameters['include_image_language'],
        'zh,ja,en,null');
    expect(imageRequests.last.hasQuery, isFalse);
  });
}
