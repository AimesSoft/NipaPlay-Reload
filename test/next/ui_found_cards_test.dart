import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/capability.dart';
import 'package:nipaplay/next/ui_data/found.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import '../security/memory_vault.dart';
import 'media_test_support.dart';

/// A provider that answers from [records] (`objectType/externalId`) and
/// counts what it was asked.
final class _Provider implements MetadataProvider {
  _Provider(this.id, this.records);
  @override
  final String id;
  final Map<String, MetadataRecord> records;
  final asked = <String>[];
  Object? error;

  @override
  Future<List<MetadataRecord>> search(String query,
          {String kind = 'tv', int? year}) async =>
      [];

  @override
  Future<MetadataRecord> get(ExternalRef ref,
      {String language = 'zh-CN'}) async {
    asked.add('${ref.objectType}/${ref.externalId}');
    if (error case final e?) throw e;
    return records['${ref.objectType}/${ref.externalId}'] ??
        (throw Failure(FailureCode.notFound, '$id object not found. HTTP 404'));
  }
}

MetadataRecord _record(String provider, String type, String id, String title,
        {int? year, int? episodes, JsonMap? rating, String? image}) =>
    MetadataRecord(
        ref: ExternalRef(provider, type, id),
        title: title,
        kind: type,
        year: year,
        overview: '$title 的简介。',
        imageUrl: image,
        rating: rating,
        episodeCount: episodes,
        fetchedAt: DateTime.utc(2026, 10, 20));

Future<Uint8List> _png(int argb) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(ui.Color(argb), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(20, 30);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return bytes.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late UiDataService service;
  late Harness harness;
  late _Provider tmdb, bangumi;
  late List<Uri> downloads;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('ui-found-cards-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [FakeExecutor()]);
    await engine.start();
    tmdb = _Provider('tmdb', {
      'tv/1001': _record('tmdb', 'tv', '1001', '长安十二时辰',
          year: 2019,
          episodes: 48,
          rating: {'value': 8.6, 'max': 10, 'count': 1200},
          image: 'https://image.example/changan.png'),
      'movie/2002': _record('tmdb', 'movie', '2002', '大鱼海棠',
          year: 2016, image: 'https://image.example/bigfish.png'),
    });
    bangumi = _Provider('bangumi', {
      'subject/3003': _record('bangumi', 'subject', '3003', '败犬女主太多了！',
          year: 2024,
          episodes: 12,
          rating: {'value': 7.9, 'max': 10},
          image: 'https://image.example/makeine.png'),
    });
    final posters = {
      '/changan.png': await _png(0xff884422),
      '/bigfish.png': await _png(0xff224488),
      '/makeine.png': await _png(0xff448822),
    };
    downloads = [];
    final media = MediaService(
        store: IdentityStore(store.database, 'fixture'),
        providers: [tmdb, bangumi],
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path]);
    // The artwork cache's own client: every picture it fetches is counted.
    service = http.runWithClient(
        () => UiDataService(
            media,
            engine,
            StateCapability([
              StateView(
                  name: 'library.files',
                  description: 'fixture',
                  fields: const ObjectSchema({}),
                  read: (offset, limit) async => [])
            ]),
            StateSources(),
            root,
            MemoryVault()),
        () => MockClient((request) async {
              downloads.add(request.url);
              final bytes = posters[request.url.path];
              return bytes == null
                  ? http.Response('missing', 404)
                  : http.Response.bytes(bytes, 200);
            }));
    harness = Harness([UiDataCapability(service)]);
    for (final (id, title) in [('w1', '葬送的芙莉莲'), ('w2', '孤独摇滚！')]) {
      await store.database.insert('media_entities', {
        'id': id,
        'kind': 'work',
        'attributes': jsonEncode({'title': title})
      });
    }
    await File('${root.path}/journal.jsonl').writeAsString('${jsonEncode({
          'event': 'chat.turn_boundary',
          'origin': 'harness_cli:chat:fixture',
          'threadId': 'thread',
          'turnId': 'turn',
          'phase': 'started'
        })}\n');
  });
  tearDown(() async {
    await service.close();
    await engine.close();
    await root.delete(recursive: true);
  });

  Future<Outcome> present(List<JsonMap> cards) => harness.invokeJson(
      'ui.present',
      {'cards': cards},
      Invocation(origin: 'harness_cli:chat:fixture'));
  Future<List<UiCard>> read() => service.cards(threadId: 'thread');

  /// The library holding tmdb [type]/[id] as [workId]'s accepted identity.
  Future<void> bind(String workId, String type, String id,
      {String status = 'accepted'}) async {
    await store.database.insert(
        'media_external_objects',
        {
          'id': 'object-$type-$id',
          'provider': 'tmdb',
          'object_type': type,
          'scope': '',
          'external_id': id,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await store.database.insert(
        'media_bindings',
        {
          'id': 'binding-$workId-$id',
          'entity_id': workId,
          'object_id': 'object-$type-$id',
          'relation': 'exact',
          'scope': '{}',
          'status': status,
          'source': 'fixture',
          'revision': 0,
          'created_at': '2026-10-20T00:00:00Z',
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  JsonMap ref(String provider, String type, String id) =>
      {'provider': provider, 'objectType': type, 'externalId': id};

  test(
      'a work outside the library is presented by ref and read back from its cache',
      () async {
    final outcome = await present([
      {'kind': 'work', 'ref': ref('tmdb', 'tv', '1001')},
      {
        'kind': 'candidates',
        'items': [
          {'ref': ref('bangumi', 'subject', '3003'), 'reason': '轻松，一集二十分钟'},
          {
            'ref': {...ref('tmdb', 'movie', '2002'), 'scope': ''}
          },
          {'workId': 'w1'},
        ]
      },
    ]);
    expect(outcome, isA<Completed>());
    final result = (outcome as Completed).value.toJson();
    expect(result['count'], 2);
    expect(result['refs'], [
      {
        'ref': {...ref('tmdb', 'tv', '1001'), 'scope': ''},
        'workId': null,
        'title': '长安十二时辰',
        'year': 2019
      },
      {
        'ref': {...ref('bangumi', 'subject', '3003'), 'scope': ''},
        'workId': null,
        'title': '败犬女主太多了！',
        'year': 2024
      },
      {
        'ref': {...ref('tmdb', 'movie', '2002'), 'scope': ''},
        'workId': null,
        'title': '大鱼海棠',
        'year': 2016
      },
    ]);
    // The presentation keeps references only; the facts are a cache.
    final saved = jsonDecode((await store.database.query('ui_presentations'))
        .single['cards'] as String) as List;
    expect(saved.first, {
      'kind': 'work',
      'ref': {...ref('tmdb', 'tv', '1001'), 'scope': ''}
    });
    expect(tmdb.asked, ['tv/1001', 'movie/2002']);
    expect(bangumi.asked, ['subject/3003']);
    expect(downloads, hasLength(3));

    for (var i = 0; i < 2; i++) {
      final cards = await read();
      final work = (cards.first as UiWorkCard).work;
      expect(Found.isFound(work), isTrue);
      expect(work.workId, 'found:tmdb:tv:1001');
      expect(work.title, '长安十二时辰');
      expect(work.year, 2019);
      expect(work.episodeCount, 48);
      expect(work.ratings.single.source, 'TMDB');
      expect(work.ratings.single.value, 8.6);
      expect(work.overview, '长安十二时辰 的简介。');
      expect(work.next, isNull);
      expect(await File(work.artwork.poster!).exists(), isTrue);
      expect(work.artwork.poster, startsWith('${root.path}/artwork/'));
      expect(work.artwork.tint, 0xff884422);
      final items = (cards.last as UiCandidatesCard).items;
      expect(items.map((i) => i.work.workId),
          ['found:bangumi:3003', 'found:tmdb:movie:2002', 'w1']);
      expect(items.first.reason, '轻松，一集二十分钟');
      expect(items.first.work.ratings.single.source, 'Bangumi');
      expect(items[1].work.ratings, isEmpty);
      expect(Found.isFound(items.last.work), isFalse);
    }
    // Reading back asked nobody again.
    expect(tmdb.asked, hasLength(2));
    expect(bangumi.asked, hasLength(1));
    expect(downloads, hasLength(3));

    // Presented again: the provider is read afresh, the pictures are not.
    expect(
        await present([
          {'kind': 'work', 'ref': ref('tmdb', 'tv', '1001')}
        ]),
        isA<Completed>());
    expect(tmdb.asked, hasLength(3));
    expect(downloads, hasLength(3));

    // The disposable cache cleared: read once more, then kept again.
    await store.database
        .delete('ui_cache', where: 'id=?', whereArgs: ['found:tmdb:tv:1001']);
    expect(((await read()).first as UiWorkCard).work.title, '长安十二时辰');
    expect(((await read()).first as UiWorkCard).work.title, '长安十二时辰');
    expect(tmdb.asked, hasLength(4));
    expect(downloads, hasLength(3));
  });

  test('a ref its provider does not return rejects the whole batch', () async {
    Future<Failure> rejected(List<JsonMap> cards) async {
      final outcome = await present(cards);
      expect(outcome, isA<Failed>());
      return (outcome as Failed).failure;
    }

    final missing = await rejected([
      {'kind': 'work', 'workId': 'w1'},
      {
        'kind': 'candidates',
        'items': [
          {'ref': ref('tmdb', 'movie', '2002')},
          {'ref': ref('tmdb', 'tv', '404')},
        ]
      },
    ]);
    expect(missing.code, FailureCode.invalidInput);
    expect(missing.message, contains('must reference an existing work'));
    expect(missing.message, contains('tmdb tv 404'));
    expect(await store.database.query('ui_presentations'), isEmpty);
    expect(await store.database.query('ui_cache', where: "id LIKE 'found:%'"),
        isEmpty);

    tmdb.error = ProviderRetry(
        'tmdb', DateTime.utc(2026, 10, 20, 12), 'Network unavailable.');
    final offline = await rejected([
      {'kind': 'work', 'ref': ref('tmdb', 'tv', '1001')}
    ]);
    expect(offline.code, FailureCode.unavailable);
    expect(offline.retryable, isTrue);
    tmdb.error = null;

    for (final card in <JsonMap>[
      {'kind': 'work', 'ref': ref('bangumi', 'tv', '3003')},
      {'kind': 'work', 'ref': ref('tmdb', 'season', '1001')},
      {
        'kind': 'work',
        'ref': {...ref('tmdb', 'tv', '1001'), 'scope': 'tv/1001/season/1'}
      },
      {'kind': 'work', 'workId': 'w1', 'ref': ref('tmdb', 'tv', '1001')},
      {'kind': 'work'},
      {
        'kind': 'candidates',
        'items': [
          {'workId': 'w1', 'ref': ref('tmdb', 'tv', '1001')}
        ]
      },
      {
        'kind': 'candidates',
        'items': [
          {'reason': '没有引用'}
        ]
      },
      {
        'kind': 'candidates',
        'items': [
          {'ref': ref('tmdb', 'tv', '1001'), 'reason': 'https://example.test'}
        ]
      },
    ]) {
      await rejected([card]);
    }
    final unknown = await rejected([
      {'kind': 'work', 'workId': 'missing'}
    ]);
    expect(unknown.message, contains('uses ref instead'));
    expect(await store.database.query('ui_presentations'), isEmpty);
  });

  test('a ref the library holds is the library work, now and later', () async {
    await bind('w2', 'tv', '5005');
    final outcome = await present([
      {'kind': 'work', 'ref': ref('tmdb', 'tv', '5005')},
      {'kind': 'work', 'ref': ref('tmdb', 'tv', '1001')},
    ]);
    expect(outcome, isA<Completed>());
    expect(((outcome as Completed).value.toJson()['refs'] as List).first, {
      'ref': {...ref('tmdb', 'tv', '5005'), 'scope': ''},
      'workId': 'w2',
    });
    // Held already: nothing asked of the provider.
    expect(tmdb.asked, ['tv/1001']);
    var cards = await read();
    expect((cards.first as UiWorkCard).work.workId, 'w2');
    expect((cards.first as UiWorkCard).work.title, '孤独摇滚！');
    expect((cards.last as UiWorkCard).work.workId, 'found:tmdb:tv:1001');

    // Brought into the library afterwards: the card opens the library's.
    await bind('w1', 'tv', '1001');
    cards = await read();
    expect((cards.last as UiWorkCard).work.workId, 'w1');
    expect(Found.isFound((cards.last as UiWorkCard).work), isFalse);

    // Only an accepted identity counts; without it the card is found again,
    // from its cache.
    await bind('w1', 'tv', '1001', status: 'revoked');
    cards = await read();
    expect((cards.last as UiWorkCard).work.workId, 'found:tmdb:tv:1001');
    expect(tmdb.asked, ['tv/1001']);
  });

  test('found IDs name their provider object', () {
    expect(Found.id('dandanplay', 123), 'found:dandanplay:123');
    expect(Found.id('bangumi', '3003', objectType: 'subject'),
        'found:bangumi:3003');
    expect(Found.id('tmdb', 1001, objectType: 'tv'), 'found:tmdb:tv:1001');
    expect(Found.ref('found:dandanplay:123'),
        (provider: 'dandanplay', objectType: 'anime', externalId: '123'));
    expect(Found.ref('found:tmdb:movie:2002'),
        (provider: 'tmdb', objectType: 'movie', externalId: '2002'));
    expect(Found.ref('found:tmdb:2002'), isNull);
    expect(Found.ref('found:fake:frieren'), isNull);
    expect(Found.ref('w1'), isNull);
    UiWork found(String id) => UiWork(workId: id, title: '');
    expect(Found.describe(found('found:dandanplay:123')), '弹弹play 作品 123');
    expect(Found.describe(found('found:tmdb:tv:1001')), 'TMDB tv 1001');
    expect(Found.describe(found('found:fake:frieren')), 'fake 作品 frieren');
  });

  test('provider work records carry rating and episode count when reported',
      () async {
    final tv = FixtureTransport('tmdb');
    (tv.responses['/3/tv/9001'] as Map)
      ..['vote_average'] = 8.6
      ..['vote_count'] = 1200
      ..['number_of_episodes'] = 24;
    final series = await TmdbMetadataProvider(tv)
        .get(const ExternalRef('tmdb', 'tv', '9001'));
    expect(series.rating, {'value': 8.6, 'max': 10, 'count': 1200});
    expect(series.episodeCount, 24);
    expect(series.episodes.every((s) => s.rating == null), isTrue);
    expect(MetadataRecord.fromJson(series.toJson()).rating, series.rating);
    final plain = await TmdbMetadataProvider(FixtureTransport('tmdb'))
        .get(const ExternalRef('tmdb', 'tv', '9001'));
    expect(plain.toJson().containsKey('rating'), isFalse);
    expect(plain.toJson().containsKey('episodeCount'), isFalse);

    final subjects = FixtureTransport('bangumi');
    (subjects.responses['/v0/subjects/8001'] as Map)
      ..['rating'] = {'score': 7.9, 'total': 300}
      ..['eps'] = 12;
    final subject = await BangumiMetadataProvider(subjects)
        .get(const ExternalRef('bangumi', 'subject', '8001'));
    expect(subject.rating, {'value': 7.9, 'max': 10, 'count': 300});
    expect(subject.episodeCount, 12);

    final anime = FixtureTransport('dandanplay');
    ((anime.responses['/api/v2/bangumi/7001'] as Map)['bangumi']
        as Map)['rating'] = 8.2;
    final series2 = await DandanplayMetadataProvider(anime)
        .get(const ExternalRef('dandanplay', 'anime', '7001'));
    expect(series2.rating, {'value': 8.2, 'max': 10});
    expect(series2.episodeCount, 2);
  });
}
