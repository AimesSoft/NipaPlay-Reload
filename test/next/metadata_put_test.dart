import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_capability.dart';
import 'package:nipaplay/next/media/media_executors.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/capability.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore jobs;
  late TaskEngine engine;
  late UiDataService service;
  late Harness harness;
  late Uint8List png;
  late List<String> fetched;
  late String workId, releaseId, episodeId;

  Future<Outcome> invoke(String id, JsonMap input) =>
      harness.invokeJson(id, input, Invocation(origin: 'mcp'));
  Future<JsonMap> call(String id, JsonMap input) async {
    final outcome = await invoke(id, input);
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    final result = (outcome as Completed).value.toJson();
    expect(harness.lookup(id)!.spec.output.validate(result), isEmpty);
    return result;
  }

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('metadata-put-');
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff3366aa), ui.BlendMode.src);
    final image = await recorder.endRecording().toImage(16, 24);
    png = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    fetched = [];
    final client = MockClient((request) async {
      fetched.add(request.url.toString());
      if (request.url.path.contains('missing')) {
        return http.Response('no', 404);
      }
      return http.Response.bytes(png, 200);
    });
    final media = MediaService(
        store: IdentityStore(jobs.database, 'fixture'),
        providers: [TmdbMetadataProvider(FixtureTransport('tmdb'))],
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path]);
    engine = TaskEngine(
        store: jobs, ownerDeviceId: 'fixture', executors: mediaExecutors(media));
    media.engine = engine;
    await engine.start();
    service = UiDataService(
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
        MemoryVault(),
        artworkClient: client);
    harness = Harness([MediaCapability(media), UiDataCapability(service)]);
    // A work that began with a TMDB identity: one season, one episode.
    final bound = await call('media.identity.bind_batch', {
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
    final entry = (bound['entries'] as List).single as Map;
    workId = entry['workId'] as String;
    releaseId = entry['releaseId'] as String;
    episodeId = (entry['episodeIds'] as List).single as String;
  });
  tearDown(() async {
    await service.close();
    await engine.close();
    await root.delete(recursive: true);
  });

  Future<Map> facts([String? id]) async =>
      await call('media.metadata.ui_facts', {'workId': id ?? workId});
  Future<Map> merged(String id) async =>
      (await service.media.store.mergedMetadata(id))['fields'] as Map;
  Future<int> rows(String table) async =>
      (await jobs.database.query(table)).length;

  const source = {'label': 'TMDB 条目页', 'url': 'https://tmdb.test/tv/9001'};
  JsonMap put(String request, {JsonMap? work, List<JsonMap>? episodes}) => {
        'requestId': request,
        'workId': workId,
        'language': 'zh-CN',
        'source': source,
        if (work != null) 'work': work,
        if (episodes != null) 'episodes': episodes,
      };

  test('a whole submission leaves ui_facts with nothing missing', () async {
    final before = await facts();
    expect((before['missing'] as Map)['identities'], isEmpty,
        reason: 'the work has a TMDB identity');
    expect((before['missing'] as Map)['fields'], contains('backdrop'));
    expect(
        ((before['missing'] as Map)['episodes'] as Map)['withoutStill'],
        [episodeId]);

    final result = await call(
        'media.metadata.put',
        put('all', work: {
          'title': '葬送的芙莉莲',
          'originalTitle': '葬送のフリーレン',
          'overview': '勇者一行打倒魔王之后的故事。',
          'year': 2023,
          'genres': ['动画', '奇幻'],
          'poster': 'https://img.test/poster.png',
          'backdrop': 'https://img.test/backdrop.png',
          'logo': 'https://img.test/logo.png',
        }, episodes: [
          {
            'season': 1,
            'number': '1',
            'title': '冒险的结束',
            'overview': '第一集简介',
            'airDate': '2023-09-29',
            'runtime': 25,
            'still': 'https://img.test/still1.png',
          }
        ]));
    expect(result['written'], 13);
    expect(result['unchanged'], 0);
    expect(((result['episodes'] as List).single as Map)['episodeId'], episodeId);
    final summary = result['uiFacts'] as Map;
    final missing = summary['missing'] as Map;
    expect(missing['identities'], ['bangumi', 'dandanplay']);
    expect(missing['chinese'], isEmpty);
    expect(missing['fields'], isNot(containsAll(['backdrop', 'poster', 'logo'])));
    expect(missing['fields'], isNot(contains('title')));
    expect(missing['fields'], isNot(contains('overview')));
    expect((missing['episodes'] as Map)['withoutTitle'], isEmpty);
    expect((missing['episodes'] as Map)['withoutStill'], isEmpty);

    final full = await facts();
    final fields = full['fields'] as Map;
    expect(fields['title']['value'], '葬送的芙莉莲');
    expect(fields['title']['inChinese'], true);
    expect(fields['title']['source']['record'], source);
    expect(fields['year']['value'], 2023);
    expect(await File(fields['logo']['path'] as String).exists(), true);
    expect(fields['backdrop']['source']['record'], source);
    expect(full['heroImage'], 'backdrop');
    final merged1 = await merged(episodeId);
    expect(merged1['runtimeMs'], 25 * 60000);
    expect(merged1['airDate'], '2023-09-29');
    final edits = await jobs.database.query('media_metadata_edits');
    expect(
        edits.every((e) =>
            e['actor'] == 'agent' &&
            e['origin'] == 'mcp' &&
            e['invocation_id'] != null),
        true);
  });

  test('a partial submission touches only the fields it names', () async {
    await call('media.metadata.put',
        put('first', work: {'title': '旧标题', 'overview': '旧简介'}));
    final result = await call(
        'media.metadata.put', put('second', work: {'overview': '新简介'}));
    expect(result['work'], {'overview': 'written'});
    final fields = await merged(workId);
    expect(fields['title'], '旧标题');
    expect(fields['overview'], '新简介');
    final again = await call(
        'media.metadata.put', put('third', work: {'title': '旧标题', 'overview': '新简介'}));
    expect(again['work'], {'title': 'unchanged', 'overview': 'unchanged'});
    expect(again['written'], 0);
  });

  test('an episode named by season and number is created when absent',
      () async {
    final result = await call(
        'media.metadata.put',
        put('create', episodes: [
          {'season': 1, 'number': '01', 'title': '已有的一集'},
          {'season': 1, 'number': '2', 'title': '新的一集', 'runtime': 24},
          {'season': 2, 'number': '1', 'title': '第二季第一集'},
        ]));
    final items = (result['episodes'] as List).cast<Map>();
    expect(items[0]['episodeId'], episodeId);
    expect(items[0]['created'], false);
    expect(items[1]['created'], true);
    expect(items[2]['created'], true);
    final created = result['created'] as Map;
    expect(created['episodes'], hasLength(2));
    expect(created['releases'], hasLength(1), reason: 'season 2 had no release');
    final row = (await jobs.database.query('media_entities',
            where: 'id=?', whereArgs: [items[1]['episodeId']]))
        .single;
    expect(row['parent_id'], releaseId);
    final attrs = decodeMediaJson(row['attributes']);
    expect(attrs['localOnly'], true);
    expect(attrs['number'], '2');
    expect((await merged(items[1]['episodeId'] as String))['title'], '新的一集');
    final library = (await call('media.library.work', {'workId': workId}))['work'] as Map;
    expect(library['releases'], hasLength(2));
    // The same numbers again name the episodes made above.
    final repeat = await call(
        'media.metadata.put',
        put('create-again', episodes: [
          {'season': 1, 'number': '2', 'title': '新的一集'},
        ]));
    expect((repeat['episodes'] as List).single['created'], false);
    expect(((repeat['episodes'] as List).single as Map)['episodeId'],
        items[1]['episodeId']);
  });

  test('ambiguous or contradictory episode names refuse the whole batch',
      () async {
    final before = await rows('media_overrides');
    final entities = await rows('media_entities');
    for (final episodes in [
      [
        {'season': 1, 'number': '1', 'title': 'A'},
        {'episodeId': episodeId, 'title': 'B'},
      ],
    ]) {
      final outcome = await invoke(
          'media.metadata.put',
          put('bad-${episodes.length}',
              work: {'title': '不该写入'}, episodes: episodes));
      expect(outcome, isA<Failed>());
    }
    expect(await rows('media_overrides'), before);
    expect(await rows('media_entities'), entities);
  });

  Future<String> addEpisode(String id, {String? number, int? season}) async {
    await jobs.database.insert('media_entities', {
      'id': id,
      'kind': 'episode',
      'parent_id': releaseId,
      'revision': 0,
      'attributes': jsonEncode({
        'removed': false,
        'title': '',
        if (number != null) 'number': number,
        if (season != null) 'season': season
      })
    });
    return id;
  }

  Future<Map> attributes(String id) async => decodeMediaJson((await jobs
          .database
          .query('media_entities', where: 'id=?', whereArgs: [id]))
      .single['attributes']);

  test('episodeId with number writes the number of an unnumbered episode',
      () async {
    final bare = await addEpisode('ep-bare');
    expect(
        (((await facts())['missing'] as Map)['episodes'] as Map)['withoutNumber'],
        [bare]);
    final result = await call(
        'media.metadata.put',
        put('number', episodes: [
          {'episodeId': bare, 'season': 1, 'number': '2'}
        ]));
    final item = (result['episodes'] as List).single as Map;
    expect(item['episodeId'], bare);
    expect(item['created'], false);
    expect(item['numbering'], {
      'written': true,
      'before': {'season': 1, 'number': null},
      'after': {'season': 1, 'number': '2'}
    });
    expect(result['written'], 1);
    expect((await attributes(bare))['number'], '2');
    final shown = await facts();
    expect(((shown['missing'] as Map)['episodes'] as Map)['withoutNumber'],
        isEmpty);
    expect(
        ((shown['episodes'] as Map)['items'] as List)
            .cast<Map>()
            .firstWhere((e) => e['episodeId'] == bare)['number'],
        2);
    final audit = await jobs.database.query('body_changes',
        where: "type='media.metadata.put'");
    expect(audit.last['facts'], contains('numbering'));
    final again = await call(
        'media.metadata.put',
        put('number-again', episodes: [
          {'episodeId': bare, 'number': '2'}
        ]));
    expect(((again['episodes'] as List).single as Map)['numbering']['written'],
        false);
    expect(again['unchanged'], 1);
  });

  test('an existing number is replaced with before and after', () async {
    final result = await call(
        'media.metadata.put',
        put('renumber', episodes: [
          {'episodeId': episodeId, 'number': '5', 'title': '改号'}
        ]));
    final numbering = ((result['episodes'] as List).single as Map)['numbering'];
    expect(numbering['written'], true);
    expect(numbering['before']['number'], '1');
    expect(numbering['after'], {'season': 1, 'number': '5'});
    expect((await attributes(episodeId))['number'], '5');
    expect((await merged(episodeId))['title'], '改号');
  });

  test('a number already held in the same release refuses the whole batch',
      () async {
    final other = await addEpisode('ep-other', number: '7', season: 1);
    final entities = await jobs.database.query('media_entities');
    final overrides = await rows('media_overrides');
    final outcome = await invoke(
        'media.metadata.put',
        put('clash', work: {'title': '不该写入'}, episodes: [
          {'episodeId': other, 'number': '1'},
        ]));
    expect(outcome, isA<Failed>());
    expect((outcome as Failed).failure.message, contains(episodeId));
    expect(await jobs.database.query('media_entities'), entities);
    expect(await rows('media_overrides'), overrides);
    // A swap inside one batch leaves no duplicate, so it is accepted.
    await call(
        'media.metadata.put',
        put('swap', episodes: [
          {'episodeId': other, 'number': '1'},
          {'episodeId': episodeId, 'number': '7'},
        ]));
    expect((await attributes(other))['number'], '1');
    expect((await attributes(episodeId))['number'], '7');
  });

  test('an unreachable image refuses the batch and leaves no trace', () async {
    final overrides = await rows('media_overrides');
    final edits = await rows('media_metadata_edits');
    final entities = await rows('media_entities');
    final operations = await rows('media_binding_operations');
    final outcome = await invoke(
        'media.metadata.put',
        put('broken', work: {
          'title': '不该写入',
          'poster': 'https://img.test/poster.png',
          'backdrop': 'https://img.test/missing-backdrop.png',
        }, episodes: [
          {'season': 5, 'number': '1', 'still': 'https://img.test/missing-still.png'},
        ]));
    expect(outcome, isA<Failed>());
    final failure = (outcome as Failed).failure;
    expect(failure.message, contains('work.backdrop'));
    expect(failure.message, contains('episodes[0].still'));
    expect(await rows('media_overrides'), overrides);
    expect(await rows('media_metadata_edits'), edits);
    expect(await rows('media_entities'), entities);
    expect(await rows('media_binding_operations'), operations);
    expect((await merged(workId))['title'], isNot('不该写入'));
  });

  test('the same requestId replays; different input under it conflicts',
      () async {
    final input = put('replay', work: {
      'title': '重放',
      'poster': 'https://img.test/poster.png'
    }, episodes: [
      {'season': 3, 'number': '1', 'title': '新集'}
    ]);
    final first = await call('media.metadata.put', input);
    final edits = await rows('media_metadata_edits');
    final entities = await rows('media_entities');
    final requests = fetched.length;
    final second = await call('media.metadata.put', input);
    expect(second['replayed'], true);
    expect(second['created'], first['created']);
    expect(second['written'], first['written']);
    expect(await rows('media_metadata_edits'), edits);
    expect(await rows('media_entities'), entities);
    expect(fetched.length, requests, reason: 'a replay fetches nothing');
    final other = await invoke('media.metadata.put',
        put('replay', work: {'title': '别的内容'}));
    expect(other, isA<Failed>());
  });

  test('a refreshed snapshot does not displace what was handed in', () async {
    await call(
        'media.metadata.put',
        put('keep', work: {'title': '我的标题', 'overview': '我的简介'}));
    await call('media.metadata.import_batch', {
      'requestId': 'newer-snapshot',
      'entries': [
        {
          'ref': mediaWorkRef,
          'language': 'zh-CN',
          'fields': {'title': '快照标题', 'overview': '快照简介'},
        }
      ]
    });
    final snapshots = (await call('media.metadata.snapshots',
            {'entityId': workId}))['snapshots'] as List;
    expect(
        snapshots.any((s) => (s['record'] as Map).toString().contains('快照标题')),
        true);
    final fields = await merged(workId);
    expect(fields['title'], '我的标题');
    expect(fields['overview'], '我的简介');
    final shown = await facts();
    expect(shown['fields']['title']['value'], '我的标题');
    expect(shown['fields']['title']['source']['mode'], 'persistent');
  });

  test('ui_facts reports a missing TMDB identity', () async {
    final id = 'work-local-only';
    await jobs.database.insert('media_entities', {
      'id': id,
      'kind': 'work',
      'attributes': jsonEncode({'title': '本地作品', 'localOnly': true})
    });
    final shown = await facts(id);
    final missing = shown['missing'] as Map;
    expect(missing['identities'], ['tmdb']);
    expect(shown['identities'], {'tmdb': false, 'bangumi': false, 'dandanplay': false});
    expect(missing['fields'], containsAll(['backdrop', 'logo', 'poster', 'overview']));
    expect(missing['chinese'], ['title', 'overview']);
    expect(await facts(), isNot(contains('nothing')));
    expect(((await facts())['identities'] as Map)['tmdb'], true);
  });
}
