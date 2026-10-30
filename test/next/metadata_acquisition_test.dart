import 'dart:convert';
import 'dart:ui' as drawing;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/media/metadata_coverage.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/ui_data/capability.dart';
import 'package:nipaplay/next/ui_data/service.dart';

import '../security/memory_vault.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaFixture f;
  late UiDataService ui;
  late Harness api;
  late String workId, episodeId;
  const anime = {
    'provider': 'dandanplay',
    'objectType': 'anime',
    'externalId': '7001',
    'scope': ''
  };
  const episode = {
    'provider': 'dandanplay',
    'objectType': 'episode',
    'externalId': '7101',
    'scope': 'anime/7001'
  };

  Future<JsonMap> facts() async {
    final result = await api.invokeJson('media.metadata.ui_facts',
        {'workId': workId}, Invocation(origin: 'mcp'));
    expect(result, isA<Completed>(), reason: jsonEncode(result.toEnvelope()));
    return (result as Completed).value.toJson();
  }

  Map tmdbCoverage(JsonMap facts) => (facts['sourceCoverage'] as List)
      .cast<Map>()
      .singleWhere((s) => (s['ref'] as Map)['provider'] == 'tmdb');

  void completeTmdbResponse(String path,
      {String credits = 'aggregate_credits', bool keywords = true}) {
    (f.tmdb.responses[path] as Map).addAll(<String, dynamic>{
      credits: {
        'cast': [
          {'id': 1, 'name': 'TMDB 演员', 'character': '角色'}
        ],
        'crew': []
      },
      'external_ids': {'imdb_id': 'tt123'},
      if (keywords)
        'keywords': {
          'results': [
            {'id': 1, 'name': '成长'}
          ]
        },
      'production_companies': [
        {'name': 'TMDB 制作公司'}
      ],
    });
  }

  Future<JsonMap> bindTmdb() => f.call('media.identity.bind_batch', {
        'requestId': 'tmdb-direct',
        'entries': [
          {
            'kind': 'work',
            'entityId': workId,
            'ref': mediaWorkRef,
            'reason': '已核实的同一作品'
          },
        ],
      });

  setUp(() async {
    f = MediaFixture();
    await f.open(sources: ['tmdb', 'dandanplay']);
    final recorder = drawing.PictureRecorder();
    drawing.Canvas(recorder)
        .drawColor(const drawing.Color(0xff3366aa), drawing.BlendMode.src);
    final image = await recorder.endRecording().toImage(2, 2);
    final png = (await image.toByteData(format: drawing.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    ui = UiDataService(
        f.service,
        f.engine,
        StateCapability([
          StateView(
              name: 'library.files',
              description: 'fixture',
              fields: const ObjectSchema({}),
              read: (offset, limit) async => [])
        ]),
        StateSources(),
        f.root,
        MemoryVault(),
        artworkClient: MockClient((_) async => http.Response.bytes(png, 200)));
    api = Harness([UiDataCapability(ui)]);
    final bound = await f.call('media.identity.bind_batch', {
      'requestId': 'dandan-first',
      'entries': [
        {
          'kind': 'episode',
          'workRef': anime,
          'episodeRefs': [episode],
          'reason': '哈希匹配后核实目录'
        },
      ],
    });
    final entry = (bound['entries'] as List).single as Map;
    workId = entry['workId'] as String;
    episodeId = (entry['episodeIds'] as List).single as String;
  });
  tearDown(() async {
    await ui.close();
    await f.close();
  });

  test(
      'Dandanplay then direct TMDB binding remains identity-only until refresh',
      () async {
    completeTmdbResponse('/3/tv/9001');
    final before = await f.identities.database.query('media_snapshots');
    final receipt = await bindTmdb();
    final effect =
        ((receipt['entries'] as List).single as Map)['metadata'] as Map;
    expect(effect['fetched'], false);
    expect(effect['persisted'], false);
    expect(effect['nextAction'], 'media.metadata.refresh_batch');
    expect(f.tmdb.requests, isEmpty);
    expect(await f.identities.database.query('media_snapshots'), before);
    expect(await bindTmdb(), receipt,
        reason: 'Retry returns the durable receipt');
    var current = await facts();
    expect((current['identities'] as Map)['tmdb'], true);
    expect(tmdbCoverage(current)['state'], 'identity_only');
    expect(
        ((current['missing'] as Map)['episodes'] as Map)['withoutTmdbIdentity'],
        [episodeId]);
    expect((current['review'] as Map)['status'], 'needs_review');

    // Reading full provider data is still not persistence.
    await f.call('media.metadata.get_batch', {
      'refs': [mediaWorkRef]
    });
    expect(tmdbCoverage(await facts())['state'], 'identity_only');
    final task = await f.call('media.metadata.refresh', {
      'ref': mediaWorkRef,
      'requestId': 'fetch-and-save',
    });
    final job = await waitForJob(
        f.engine, (task['job'] as Map)['jobId'] as String, JobState.succeeded);
    expect(job.receipt!.details['childrenRefreshed'], false);
    current = await facts();
    expect(tmdbCoverage(current)['state'], 'detail_fetched');
    final source = ((current['metadata'] as Map)['sources'] as List)
        .cast<Map>()
        .singleWhere((s) => s['provider'] == 'tmdb');
    final fields = source['fields'] as Map;
    expect(fields['studio'], 'TMDB 制作公司');
    expect(fields['tags'], ['成长']);
    expect(fields['externalIds'], {'imdb_id': 'tt123'});
    expect(
        ((fields['credits'] as Map)['cast'] as List).single['name'], 'TMDB 演员');
    expect(
        ((current['missing'] as Map)['episodes'] as Map)['withoutTmdbIdentity'],
        [episodeId],
        reason: 'Work refresh does not silently map child episodes');
    expect(await bindTmdb(), receipt,
        reason:
            'Old binding receipt describes that invocation, not current coverage');
    (f.tmdb.responses['/3/tv/9001'] as Map)['aggregate_credits'] = {
      'success': false,
      'status_message': 'fixture failure'
    };
    final retry = await f.call('media.metadata.refresh', {
      'ref': mediaWorkRef,
      'requestId': 'partial-refresh',
    });
    await waitForJob(
        f.engine, (retry['job'] as Map)['jobId'] as String, JobState.succeeded);
    current = await facts();
    expect(tmdbCoverage(current)['state'], 'detail_partial');
    expect(tmdbCoverage(current)['unreceivedSections'], ['aggregate_credits']);
    final retained = ((current['metadata'] as Map)['sources'] as List)
        .cast<Map>()
        .singleWhere((s) => s['provider'] == 'tmdb');
    expect((retained['fields'] as Map)['credits'], fields['credits'],
        reason: 'An endpoint failure is not an empty credit list');
  });

  test('artwork and other-source rich fields cannot certify TMDB details',
      () async {
    await bindTmdb();
    await f.call('media.metadata.import_batch', {
      'requestId': 'artwork-facts',
      'entries': [
        {
          'ref': mediaWorkRef,
          'language': 'zh-CN',
          'fields': {
            'artworkUrls': {'poster': 'https://example.invalid/poster.jpg'},
            'genres': ['动画'],
            'studio': '制作公司',
          }
        },
        {
          'ref': anime,
          'language': 'zh-CN',
          'fields': {
            'credits': {
              'cast': [
                {'name': '其他来源演员'}
              ],
              'crew': []
            },
          }
        },
      ],
    });
    final current = await facts();
    expect(((current['fields'] as Map)['credits'] as Map)['available'], true);
    expect(tmdbCoverage(current)['state'], 'snapshot_unverified');
    expect(
        ((current['missing'] as Map)['sourceDetails'] as List)
            .cast<Map>()
            .any((s) => (s['ref'] as Map)['provider'] == 'tmdb'),
        true);
    final source = ((current['metadata'] as Map)['sources'] as List)
        .cast<Map>()
        .singleWhere((s) => s['provider'] == 'tmdb');
    expect((source['fields'] as Map).containsKey('credits'), false);
  });

  test(
      'TMDB season summaries and detail fetches remain distinct; empty is returned',
      () async {
    completeTmdbResponse('/3/tv/9001/season/1', keywords: false);
    completeTmdbResponse('/3/tv/9001/season/1/episode/1',
        credits: 'credits', keywords: false);
    final episodeRow = f.tmdb.responses['/3/tv/9001/season/1/episode/1'] as Map;
    episodeRow['credits'] = {'cast': [], 'crew': []};
    episodeRow['still_path'] = '/still.jpg';
    episodeRow['runtime'] = 25;
    final provider = TmdbMetadataProvider(f.tmdb);
    final season = await provider.get(ExternalRef.fromJson(mediaReleaseRef));
    expect(season.acquisition['kind'], 'detail');
    expect((f.tmdb.requests.last['query'] as Map)['append_to_response'],
        'aggregate_credits,external_ids');
    expect(season.episodes.first.acquisition['kind'], 'catalogue');
    final detail = await provider.get(season.episodes.first.ref);
    expect((f.tmdb.requests.last['query'] as Map)['append_to_response'],
        'credits,external_ids');
    expect((detail.acquisition['sections'] as Map)['credits'], 'received');
    expect(detail.details['runtimeMs'], 1500000);
    expect(detail.imageUrl, endsWith('/still.jpg'));
    expect(MetadataRecord.fromJson(detail.toJson()).acquisition,
        detail.acquisition);
    episodeRow['credits'] = {
      'success': false,
      'status_message': 'fixture failure'
    };
    final failed = await provider.get(detail.ref);
    expect((failed.acquisition['sections'] as Map)['credits'], 'failed');
    expect(failed.details.containsKey('credits'), false);
    episodeRow.remove('credits');
    final absent = await provider.get(detail.ref);
    expect((absent.acquisition['sections'] as Map)['credits'], 'not_returned');
  });

  test('catalogue reuse reports fetched records it did not persist', () async {
    final input = <String, Object?>{
      'requestId': 'new-tmdb',
      'entries': [
        {
          'kind': 'episode',
          'workRef': mediaWorkRef,
          'releaseRef': mediaReleaseRef,
          'episodeRefs': [mediaEpisodeRef(1)],
          'reason': '目录建库'
        },
      ]
    };
    final first = await f.call('media.identity.bind_batch', input);
    final m1 = ((first['entries'] as List).single as Map)['metadata'] as Map;
    expect(m1['persisted'], true);
    expect((m1['records'] as List).cast<Map>().last['acquisition'],
        {'kind': 'catalogue'});
    final reused = await f.call(
        'media.identity.bind_batch', {...input, 'requestId': 'reuse-tmdb'});
    final m2 = ((reused['entries'] as List).single as Map)['metadata'] as Map;
    expect(m2['fetched'], true);
    expect(m2['persisted'], false);
  });

  test(
      'latest detail evidence survives sparse updates, but newer failed detail is visible',
      () {
    final full = {
      'kind': 'detail',
      'fetchedAt': '2026-01-01T00:00:00Z',
      'sections': {'core': 'received', 'credits': 'received'}
    };
    final catalogue = {
      'kind': 'catalogue',
      'fetchedAt': '2026-02-01T00:00:00Z'
    };
    final partial = {
      'kind': 'detail',
      'fetchedAt': '2026-03-01T00:00:00Z',
      'sections': {'core': 'received', 'credits': 'failed'}
    };
    expect(preferredAcquisition(full, catalogue), full);
    expect(preferredAcquisition(catalogue, full), full);
    expect(preferredAcquisition(full, partial), partial);
    final coverage = metadataSourceCoverage([
      mediaWorkRef
    ], {
      'sources': [
        {
          ...mediaWorkRef,
          'language': 'zh-CN',
          'fields': {'title': 'sample'},
          'acquisition': preferredAcquisition(full, partial)
        },
      ]
    }).single;
    expect(coverage['state'], 'detail_partial');
    expect(coverage['unreceivedSections'], ['credits']);
  });
}
