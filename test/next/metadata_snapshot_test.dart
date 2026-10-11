// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/next/media/classic_metadata_view.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'download_test_support.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late NextCore core;
  late Harness api;
  late Directory root;
  late FixtureTransport tmdb;
  late JsonMap douban;
  late String workId, releaseId, episodeId;

  Future<JsonMap> call(String id, JsonMap input) async {
    final outcome = await api.invokeJson(id, input, Invocation(origin: 'mcp'));
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    final result = (outcome as Completed).value.toJson();
    expect(api.lookup(id)!.spec.output.validate(result), isEmpty);
    return result;
  }

  Future<void> connect() async {
    core = NextCore(
        root: root,
        databaseFactory: databaseFactoryFfi,
        downloadBackend: FakeDownloadBackend(root),
        downloadLibrary: FakeDownloadLibrary(),
        isDownloaderEnabled: () async => false,
        loadImportedKeys: () async => {},
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path],
        mediaProviders: [TmdbMetadataProvider(tmdb)],
        mediaDurationProbe: (_) async => 10000);
    await core.ready;
    api = Harness(core.capabilities);
  }

  JsonMap binding(String id, String kind, JsonMap ref) => {
        'entityId': id,
        'kind': kind,
        'ref': ref,
        'reason': '实验 6：Agent 根据外部页面确认同一对象',
        'evidence': [
          {
            'source': 'public_page',
            'detail': '离线复现已归档豆瓣公开事实',
            'url': douban['url']
          }
        ],
      };
  Future<JsonMap> import(String request, {JsonMap? snapshot}) =>
      call('media.metadata.import_batch', {
        'requestId': request,
        'entries': [snapshot ?? douban]
      });
  Future<void> bindDouban() async => call('media.identity.bind_batch', {
        'requestId': 'douban-bind',
        'entries': [binding(workId, 'work', douban['ref'] as JsonMap)],
      });
  Future<Map> view(String id) async =>
      (await call('media.identity.get', {'entityId': id}))['identity'] as Map;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('next-x9-');
    tmdb = FixtureTransport('tmdb');
    douban = Map<String, Object?>.from(jsonDecode(
        File('test/next/fixtures/media/douban_snapshot.json')
            .readAsStringSync()) as Map)
      ..remove('sourceArchive');
    await connect();
    final result = await call('media.identity.bind_batch', {
      'requestId': 'tmdb-only',
      'entries': [
        {
          'kind': 'episode',
          'workRef': mediaWorkRef,
          'releaseRef': mediaReleaseRef,
          'episodeRefs': [mediaEpisodeRef(1)],
          'reason': '作品最初只有 TMDB 身份',
        }
      ],
    });
    final entry = (result['entries'] as List).single as Map;
    workId = entry['workId'] as String;
    releaseId = entry['releaseId'] as String;
    episodeId = (entry['episodeIds'] as List).single as String;
  });
  tearDown(() async {
    await core.close();
    await root.delete(recursive: true);
  });

  test(
      'X9 experiment: arbitrary facts coexist and work views agree after reopen',
      () async {
    final store = core.media.service.store;
    final before = await store.database.query('media_snapshots');
    final requestCount = tmdb.requests.length;
    await bindDouban();
    final receipt = await import('douban-snapshot');
    expect(await import('douban-snapshot'), receipt);
    final work = await view(workId), release = await view(releaseId);
    final metadata = work['metadataView'] as Map;
    expect(metadata, release['metadataView']);
    expect((metadata['fields'] as Map)['rating'], {
      ...((douban['fields'] as Map)['rating'] as Map),
      'source': 'https://movie.douban.com',
    });
    expect((metadata['fields'] as Map)['unfamiliar'],
        (douban['fields'] as Map)['unfamiliar']);
    expect((await view(episodeId))['metadataView'], isNot(metadata));
    final library =
        (await call('media.library.work', {'workId': workId}))['work'] as Map;
    expect(library['metadataView'], metadata);
    expect((library['releases'] as List).single['metadataView'], metadata);
    final states = <String, Map>{};
    for (final name in ['media.entities', 'library.works', 'library.seasons']) {
      final id = name == 'library.seasons' ? releaseId : workId;
      final query = await call('state.query', {
        'view': name,
        'filter': {
          'id': {'eq': id}
        }
      });
      final state = (query['rows'] as List).single['metadataView'] as Map;
      expect(state, metadata);
      states[name] = state;
    }
    final snapshots = (await call(
        'media.metadata.snapshots', {'entityId': workId}))['snapshots'] as List;
    final providers = snapshots.map((s) => s['ref']['provider']).toSet();
    expect(providers, {'tmdb', 'https://movie.douban.com'});
    for (final old in before) {
      expect(
          (await store.database.query('media_snapshots',
                  where: 'id=?', whereArgs: [old['id']]))
              .single,
          old);
    }
    final newRecord = snapshots.singleWhere(
            (s) => s['ref']['provider'] == 'https://movie.douban.com')['record']
        as Map;
    expect(newRecord['actor'], 'agent');
    expect(newRecord['origin'], 'mcp');
    expect(newRecord['receivedAt'], isA<String>());
    expect(newRecord['invocationId'], isA<String>());
    final persisted = await store.database.query('media_snapshots');
    await core.close();
    await connect();
    expect(await core.media.service.store.database.query('media_snapshots'),
        persisted);
    expect((await view(workId))['metadataView'], metadata);
    expect(tmdb.requests.length, requestCount);
    print('X9_EXPERIMENT ${jsonEncode({
          'initialProviders': ['tmdb'],
          'acceptedProviders': (work['bindings'] as List)
              .where((b) => b['status'] == 'accepted')
              .map((b) => b['ref']['provider'])
              .toList(),
          'rating': (metadata['fields'] as Map)['rating'],
          'ratingProvenance': (metadata['provenance'] as Map)['rating'],
          'overview': (metadata['fields'] as Map)['overview'],
          'snapshotProviders': providers.toList(),
          'snapshotCount': snapshots.length,
          'unknownField': (metadata['fields'] as Map)['unfamiliar'],
          'workEqualsRelease': metadata == release['metadataView'] ||
              jsonEncode(metadata) == jsonEncode(release['metadataView']),
          'consistentEntrances': [
            'media.identity.get',
            'media.library.work',
            ...states.keys
          ],
          'retrySameReceipt': true,
          'oldSnapshotsUnchanged': true,
          'reopenUnchanged': true,
          'extraNetworkRequests': tmdb.requests.length - requestCount,
        })}');
  });

  test(
      'direct namespaces are canonical, atomic, audited and cannot create conflicting owners',
      () async {
    final ref = {
      ...douban['ref'] as Map<String, Object?>,
      'provider': ' HTTPS://MOVIE.DOUBAN.COM:443/ '
    };
    await call('media.identity.bind_batch', {
      'requestId': 'canonical',
      'entries': [binding(workId, 'work', ref)]
    });
    expect((await view(workId))['bindings'].last['ref']['provider'],
        'https://movie.douban.com');
    final episodeRef = {
      ...douban['ref'] as JsonMap,
      'objectType': 'episode',
      'scope': 'subject/26849758',
      'externalId': '1'
    };
    final before =
        await core.media.service.store.database.query('media_bindings');
    final invalid = await api.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'rollback',
          'entries': [
            binding(episodeId, 'episode', episodeRef),
            binding(workId, 'work',
                {...douban['ref'] as JsonMap, 'externalId': 'wrong'}),
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(invalid.failure.code, FailureCode.conflict);
    expect(invalid.failure.violations.single.path, '/entries/1');
    expect(await core.media.service.store.database.query('media_bindings'),
        before);
    await call('media.identity.bind_batch', {
      'requestId': 'levels',
      'entries': [
        binding(releaseId, 'release', {
          ...douban['ref'] as JsonMap,
          'objectType': 'season',
          'scope': 'subject/26849758',
          'externalId': '1'
        }),
        binding(episodeId, 'episode', episodeRef),
      ]
    });
    final nickname = await api.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'nickname',
          'entries': [
            binding(workId, 'work',
                {...douban['ref'] as JsonMap, 'provider': 'douban'})
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(nickname.failure.code, FailureCode.invalidInput);
    expect(nickname.failure.message, contains('HTTPS origins'));
    final secondWork = await call('media.identity.bind_batch', {
      'requestId': 'other-work',
      'entries': [
        {
          'kind': 'work',
          'workRef': {
            'provider': 'tmdb',
            'objectType': 'movie',
            'externalId': '9301',
            'scope': ''
          },
          'reason': '不同作品'
        }
      ],
    });
    final ownerConflict = await api.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'duplicate-owner',
          'entries': [
            binding((secondWork['entries'] as List).single['workId'] as String,
                'work', douban['ref'] as JsonMap)
          ],
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(ownerConflict.failure.code, FailureCode.conflict);
    expect(ownerConflict.failure.message, contains('already bound'));
    final spoof = await api.invokeJson(
        'media.metadata.import_batch',
        {
          'requestId': 'spoof',
          'entries': [
            {...douban, 'actor': 'user'}
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(spoof.failure.code, FailureCode.invalidInput);
  });

  test(
      'snapshots roll back invalid ratings; source histories and persistent edits survive refresh',
      () async {
    await bindDouban();
    final store = core.media.service.store;
    final before = await store.database.query('media_snapshots');
    final invalid = await api.invokeJson(
        'media.metadata.import_batch',
        {
          'requestId': 'bad-rating',
          'entries': [
            douban,
            {
              ...douban,
              'fields': {
                'rating': {'value': 11, 'max': 10}
              }
            }
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(invalid.failure.violations.single.path, '/entries/1');
    expect(await store.database.query('media_snapshots'), before);
    await call('media.metadata.override',
        {'entityId': releaseId, 'field': 'overview', 'value': '持久编辑'});
    final oldEdits = await store.database.query('media_overrides');
    await import('one');
    expect(await store.database.query('media_overrides'), oldEdits);
    expect((await view(workId))['metadataView']['fields']['overview'], '持久编辑');
    await call('media.metadata.override', {
      'entityId': workId,
      'field': 'overview',
      'value': null,
      'mode': 'clear'
    });
    expect((await view(releaseId))['metadataView']['fields']['overview'],
        (douban['fields'] as Map)['overview']);
    await call('media.metadata.override', {
      'entityId': workId,
      'field': 'overview',
      'value': '临时校正',
      'mode': 'correction'
    });
    await import('two', snapshot: {
      ...douban,
      'fetchedAt': '2000-01-01T00:00:00Z',
      'fields': {
        'overview': '新来源快照',
        'rating': {'value': 8.2, 'max': 10, 'count': 520050}
      }
    });
    expect(
        (await view(releaseId))['metadataView']['fields']['overview'], '新来源快照');
    expect(
        (await view(workId))['metadataView']['ratings'].single['value'], 8.2);
    final retained = (await call(
        'media.metadata.snapshots', {'entityId': workId}))['snapshots'] as List;
    expect(
        retained
            .where((s) => s['ref']['provider'] == 'https://movie.douban.com'),
        hasLength(2));
    expect(
        retained.any(
            (s) => (s['record'] as Map)['metadata']?['unfamiliar'] != null),
        isTrue);
    final changed = await api.invokeJson(
        'media.metadata.import_batch',
        {
          'requestId': 'one',
          'entries': [
            {
              ...douban,
              'fields': {'overview': '变更'}
            }
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(changed.failure.code, FailureCode.conflict);
  });

  testWidgets(
      'TMDB-only local playback renders Douban in the existing Classic detail',
      (tester) async {
    final context = await tester.runAsync(() async {
      final file =
          await File('${root.path}/changan.mkv').writeAsString('fixture video');
      final id = await core.media.service.index(file.path);
      await call('media.identity.bind_batch', {
        'requestId': 'local-video',
        'entries': [tmdbBinding(id)]
      });
      await bindDouban();
      await import('playback-snapshot');
      await call('media.metadata.override',
          {'entityId': workId, 'field': 'imageUrl', 'value': null});
      final metadata = ClassicMetadataView(core.media.service.store);
      final projected = await metadata.applyForPath(
          file.path,
          BangumiAnime(
              id: 0, name: 'changan.mkv', nameCn: '未识别', imageUrl: ''));
      expect(projected.ratingDetails?['豆瓣评分'], 8.1);
      return PlaybackDetailContext(
        sourceKind: PlaybackSourceKind.localFile,
        sourceLabel: '本地文件',
        sourceKey: file.path,
        title: 'changan.mkv',
        isIdentified: false,
        episodeLoader: () async => [],
        metadataView: (_) async => projected.copyWith(imageUrl: ''),
      );
    });
    await tester.pumpWidget(
        ChangeNotifierProvider<AppearanceSettingsProvider>.value(
            value: _TestAppearance(),
            child: AppDisplaySurfaceScope(
                surface: AppDisplaySurface.phone,
                child: MaterialApp(
                    home: Scaffold(
                        body: AnimeDetailPage(
                            animeId: 0,
                            renderInWindowScaffold: false,
                            playbackDetailContext: context))))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final ratingVisible = tester
        .widgetList<RichText>(find.byType(RichText))
        .any((w) => w.text.toPlainText().contains('豆瓣: 8.1'));
    expect(ratingVisible, isTrue);
    expect(find.textContaining('改编自马伯庸'), findsOneWidget);
    expect(tester.takeException(), isNull);
    print('X9_CLASSIC_TMDB_ONLY ${jsonEncode({
          'ratingText': '豆瓣: 8.1',
          'rendered': ratingVisible,
          'dandanplayIdentity': false,
          'summaryRendered': true
        })}');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
      'all source ratings coexist and revoked snapshot history remains readable',
      () async {
    await bindDouban();
    await import('douban');
    await import('tmdb-rating', snapshot: {
      'ref': mediaWorkRef,
      'language': 'zh-CN',
      'fields': {
        'rating': {'value': 7.9, 'max': 10, 'count': 123, 'label': 'TMDB'}
      },
    });
    final identity = await view(workId);
    expect(
        (identity['metadataView']['ratings'] as List)
            .map((r) => r['source'])
            .toSet(),
        {'tmdb', 'https://movie.douban.com'});
    final before = (await call(
        'media.metadata.snapshots', {'entityId': workId}))['snapshots'];
    final bindingId = (identity['bindings'] as List).singleWhere(
        (b) => b['ref']['provider'] == 'https://movie.douban.com')['bindingId'];
    await call('media.identity.unbind_batch', {
      'requestId': 'revoke-douban',
      'entries': [
        {
          'entityId': workId,
          'bindingIds': [bindingId],
          'reason': '撤销身份但保留事实审计',
        }
      ]
    });
    expect((await view(workId))['metadataView']['ratings'].single['source'],
        'tmdb');
    expect(
        (await call(
            'media.metadata.snapshots', {'entityId': workId}))['snapshots'],
        before);
  });

  test(
      'Classic detail displays structured rating and credits without rewriting its cache',
      () async {
    final original = BangumiAnime(
        id: 7001,
        name: 'Classic 原名',
        nameCn: 'Classic 原名',
        imageUrl: '/poster.jpg',
        summary: 'Classic 原简介',
        rating: 7,
        ratingDetails: {'Bangumi评分': 7.0},
        metadata: ['制作: 原制作'],
        tags: ['原类型'],
        language: 'zh');
    final cached = jsonEncode({
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'animeDetail': original.toJson()
    });
    SharedPreferences.setMockInitialValues({'bangumi_detail_7001': cached});
    final classic = BangumiService.forTesting(
        MockClient((_) async => throw StateError('No network expected')));
    classic.metadataView = ClassicMetadataView(core.media.service.store).apply;
    expect((await classic.getAnimeDetails(7001)).toJson(), original.toJson());
    await call('media.identity.bind_batch', {
      'requestId': 'classic-id',
      'entries': [
        binding(workId, 'work', {
          'provider': 'dandanplay',
          'objectType': 'anime',
          'externalId': '7001',
          'scope': ''
        })
      ]
    });
    await bindDouban();
    await import('classic-snapshot');
    final result = await classic.getAnimeDetails(7001);
    expect(result.summary, (douban['fields'] as Map)['overview']);
    expect(result.ratingDetails!['豆瓣评分'], 8.1);
    expect(result.ratingDetails!['Bangumi评分'], 7.0);
    expect(result.rating, 7);
    expect(result.metadata, contains('导演: 曹盾'));
    expect(result.metadata, contains('豆瓣评价人数: 520049'));
    expect(
        (await SharedPreferences.getInstance())
            .getString('bangumi_detail_7001'),
        cached);
    print('X9_CLASSIC ${jsonEncode({
          'summary': result.summary,
          'ratingDetails': result.ratingDetails,
          'credits': result.metadata,
          'cacheUnchanged': true
        })}');
  });

  test('Classic view leaves streams, missing files and unknown works unchanged',
      () async {
    final view = ClassicMetadataView(core.media.service.store);
    final anime =
        BangumiAnime(id: 424242, name: 'x', nameCn: 'x', imageUrl: '');
    expect(identical(await view.apply(anime), anime), isTrue);
    expect(
        identical(
            await view.applyForPath('https://media.example/stream/1', anime),
            anime),
        isTrue);
    expect(
        identical(
            await view.applyForPath('${root.path}/missing.mkv', anime), anime),
        isTrue);
  });
}

class _TestAppearance extends ChangeNotifier
    implements AppearanceSettingsProvider {
  @override
  AnimeCardAction get animeCardAction => AnimeCardAction.synopsis;
  @override
  bool get enablePageAnimation => false;
  @override
  bool get enableWidgetBlurEffect => false;
  @override
  dynamic noSuchMethod(invocation) => super.noSuchMethod(invocation);
}
