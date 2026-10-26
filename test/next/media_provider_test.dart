import '../security/memory_vault.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/media/provider_transport.dart'
    hide VaultCredentialResolver;
import 'package:nipaplay/next/media/vault_credential_resolver.dart';
import 'package:nipaplay/next/media/providers.dart';

import 'media_test_support.dart';

void main() {
  test(
      'rich TMDB and Bangumi records retain credits, facts and roundtrip details',
      () async {
    final transport = FixtureTransport('tmdb');
    final row = transport.responses['/3/tv/9001'] as Map;
    row.addAll(<String, dynamic>{
      'genres': [
        {'id': 16, 'name': '动画'}
      ],
      'episode_run_time': [24],
      'production_companies': [
        {'name': '样本工作室'}
      ],
      'status': 'Returning Series',
      'aggregate_credits': {
        'cast': [
          {
            'id': 1,
            'name': '样本演员',
            'roles': [
              {'character': '主角'}
            ]
          }
        ],
        'crew': [
          {
            'id': 2,
            'name': '样本导演',
            'jobs': [
              {'job': 'Director'}
            ]
          }
        ]
      },
      'external_ids': {'imdb_id': 'tt123'},
    });
    final record = await TmdbMetadataProvider(transport)
        .get(const ExternalRef('tmdb', 'tv', '9001'));
    expect(record.details['genres'], ['动画']);
    expect(record.details['runtimeMs'], 1440000);
    expect(((record.details['credits'] as Map)['cast'] as List).single['role'],
        '主角');
    expect(record.details['directors'], ['样本导演']);
    expect(MetadataRecord.fromJson(record.toJson()).details, record.details);
    expect((transport.requests.last['query'] as Map)['append_to_response'],
        contains('aggregate_credits'));
    final bgm = await BangumiMetadataProvider(FixtureTransport('bangumi'))
        .get(const ExternalRef('bangumi', 'subject', '8001'));
    expect((bgm.details['staff'] as List).single['name'], '样本监督');
    expect(
        ((bgm.details['characters'] as List).single['actors'] as List)
            .single['name'],
        '样本声优');
  });

  test('public Bangumi credit arrays are read without authentication',
      () async {
    final client = MockClient((request) async {
      expect(request.headers.containsKey('authorization'), false);
      return http.Response('[{"id":1,"name":"Staff"}]', 200);
    });
    final transport = HttpMetadataTransport(
        provider: 'bangumi',
        baseUri: Uri.parse('https://example.invalid'),
        client: client,
        interval: Duration.zero);
    expect((await transport.request('/v0/subjects/8001/persons'))['data'],
        hasLength(1));
    client.close();
  });
  test(
      'TMDB stable object IDs keep route numbers separately and retain language and images',
      () async {
    final transport = FixtureTransport('tmdb');
    final provider = TmdbMetadataProvider(transport);
    final results = await provider.search('长安十二时辰', year: 2019);
    expect(results.single.ref.externalId, '9001');
    expect(transport.requests.single['query'], {
      'query': '长安十二时辰',
      'language': 'zh-CN',
      'first_air_date_year': '2019'
    });
    final tv = await provider.get(results.single.ref);
    final season = await provider.get(tv.episodes.single.ref);
    expect(season.ref.externalId, '9101');
    expect(season.episodes.first.ref.externalId, '9201');
    final episode =
        await provider.get(season.episodes.first.ref, language: 'ja-JP');
    expect(episode.language, 'ja-JP');
    expect(transport.requests.last['path'], '/3/tv/9001/season/1/episode/1');
    expect(
        results.single.imageUrl, 'https://image.tmdb.org/t/p/w500/changan.jpg');
    final movie = await provider
        .get((await provider.search('86', kind: 'movie')).single.ref);
    expect(movie.kind, 'movie');
    await expectLater(
        provider.get(const ExternalRef('tmdb', 'season', '999',
            scope: 'tv/9001/season/1')),
        throwsA(isA<Failure>()
            .having((error) => error.code, 'code', FailureCode.conflict)));
  });
  test(
      'Bangumi preserves subject scope and separates regular and special sort=1',
      () async {
    final provider = BangumiMetadataProvider(FixtureTransport('bangumi'));
    final subject =
        await provider.get((await provider.search('季度')).single.ref);
    expect(subject.episodes.map((ep) => ep.ref.externalId),
        ['8101', '8102', '8191']);
    expect(subject.episodes.first.ref.scope, 'subject/8001');
    expect(
        subject.episodes
            .where((ep) => ep.number == '1')
            .map((ep) => ep.episodeType),
        ['regular', 'special']);
    expect(subject.episodes.first.order, 'subject');
  });
  test(
      'Dandanplay hash requests use hashOnly without fetching danmaku or accepting filename fallback',
      () async {
    final transport = FixtureTransport('dandanplay');
    final provider = DandanplayMetadataProvider(transport);
    final records =
        await provider.matchHash('sample.mkv', 'fixture-content-hash', 128);
    expect((transport.requests.single['body'] as Map)['matchMode'], 'hashOnly');
    expect(records.single.episodes.single.ref.scope, 'anime/7001');
    transport.responses['/api/v2/match'] = {'isMatched': false, 'matches': []};
    expect(await provider.matchHash('sample.mkv', 'fixture-content-hash', 128),
        isEmpty);
    final anime = await provider.get((await provider.search('动画')).single.ref);
    expect(anime.episodes, hasLength(2));
    expect(
        transport.requests
            .any((request) => (request['path'] as String).contains('comment')),
        isFalse);
  });
  test('TMDB without a kind searches series and films together, in its order',
      () async {
    final transport = FixtureTransport('tmdb');
    transport.responses['/3/search/multi'] = {
      'total_results': 3,
      'results': [
        {
          'id': 133701,
          'media_type': 'movie',
          'title': '钢铁之泪',
          'release_date': '2012-09-26'
        },
        {'id': 7, 'media_type': 'person', 'name': 'Someone'},
        {
          'id': 296286,
          'media_type': 'tv',
          'name': '躲在超市后门抽烟的两人',
          'first_air_date': '2026-10-04'
        },
      ]
    };
    final provider = TmdbMetadataProvider(transport);
    final all = await provider.search('steel', kind: 'any');
    expect([for (final r in all) '${r.kind}:${r.ref.externalId}'],
        ['movie:133701', 'tv:296286']);
    expect(transport.requests.last['query'],
        {'query': 'steel', 'language': 'zh-CN'});
    final dated = await provider.search('steel', kind: 'any', year: 2012);
    expect([for (final r in dated) r.ref.externalId], ['133701']);
  });
  test('malformed catalogues fail instead of becoming empty matches', () async {
    final transport = FixtureTransport('tmdb');
    transport.responses['/3/search/tv'] = {'total_results': 0};
    await expectLater(TmdbMetadataProvider(transport).search('name'),
        throwsA(isA<Failure>()));
    final bgm = FixtureTransport('bangumi');
    bgm.responses['/v0/episodes'] = {'data': [], 'total': 2};
    await expectLater(
        BangumiMetadataProvider(bgm)
            .get(const ExternalRef('bangumi', 'subject', '8001')),
        throwsA(isA<Failure>()));
  });
  test(
      'rate limit and temporary failure retry; authentication and missing objects are distinct',
      () async {
    var code = 429;
    final client = MockClient((request) async =>
        http.Response('{}', code, headers: {'retry-after': '2'}));
    final transport = HttpMetadataTransport(
        provider: 'tmdb',
        baseUri: Uri.parse('https://example.invalid'),
        client: client,
        interval: Duration.zero);
    await expectLater(
        transport.request('/x'),
        throwsA(isA<ProviderRetry>()
            .having((retry) => retry.provider, 'provider', 'tmdb')));
    // Use independent transports so the server's Retry-After is not slept through in tests.
    for (final status in [401, 403, 404, 500]) {
      code = status;
      final t = HttpMetadataTransport(
          provider: 'tmdb',
          baseUri: Uri.parse('https://example.invalid'),
          client: client,
          interval: Duration.zero);
      await expectLater(
          t.request('/x'),
          throwsA(status == 500
              ? isA<ProviderRetry>()
              : isA<Failure>().having(
                  (error) => error.code,
                  'code',
                  status == 404
                      ? FailureCode.notFound
                      : FailureCode.unavailable)));
    }
    client.close();
  });
  test(
      'credentials are private references and a missing reference reports no secret material',
      () async {
    final root = await Directory.systemTemp.createTemp('next-credentials-');
    try {
      final resolver = VaultCredentialResolver(root,
          store: CredentialStore(MemoryVault(), desktop: true));
      await expectLater(
          resolver.resolve(const CredentialRef('metadata', 'tmdb')),
          throwsA(isA<Failure>()
              .having((error) => error.message, 'message', contains('tmdb'))));
      expect(await File('${root.path}/credentials.json').exists(), false);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
