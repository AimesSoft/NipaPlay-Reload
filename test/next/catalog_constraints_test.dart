import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'media_test_support.dart';

void main() {
  late MediaFixture f;
  setUp(() async {
    f = MediaFixture();
    await f.open();
  });
  tearDown(() => f.close());
  Future<JsonMap> put(String request, List<JsonMap> entries) =>
      f.call('media.entities.put_batch', {
        'requestId': request,
        'reason': 'test explicit local catalog',
        'entries': entries
      });
  test(
      'local hierarchy is atomic, receipt survives restart, removal preserves files and history and can be undone',
      () async {
    final file = await f.file('home.mkv');
    final location = (await f.identities.database
            .query('media_locations', where: 'file_id=?', whereArgs: [file]))
        .single;
    await f.identities.database.insert('media_legacy_history', {
      'location_id': location['id'],
      'fingerprint': 'progress-before',
      'payload': '{"lastPosition":12345,"watchProgress":0.4,"source":"classic"}'
    });
    final entries = <JsonMap>[
      {'kind': 'work', 'entityId': 'home', 'title': 'Home'},
      {
        'kind': 'release',
        'entityId': 'season',
        'parentId': 'home',
        'title': '2026'
      },
      {
        'kind': 'episode',
        'entityId': 'episode',
        'parentId': 'season',
        'title': 'Trip',
        'number': '1',
        'fileIds': [file]
      },
    ];
    final receipt = await put('create', entries);
    expect(await f.identities.library(), contains(isA<Map>()));
    expect((await f.identities.mergedMetadata('home'))['fields'],
        containsPair('title', 'Home'));
    await f.reopen();
    expect(await put('create', entries), receipt);
    final locator = location['locator'] as String;
    f.classic.rows[locator] = {
      'filePath': locator,
      'animeName': 'home.mkv',
      'episodeTitle': null,
      'lastPosition': 18000,
      'watchProgress': 0.5,
      'duration': 36000,
      'lastWatchTime': '2026-10-13T00:00:00Z'
    };
    await f.identities.importLegacy(await f.classic.history());
    expect(
        await f.identities.database.query('media_file_episodes'), hasLength(1));
    final historyBefore =
        await f.identities.database.query('media_legacy_history');
    final input = <String, Object?>{
      'requestId': 'remove',
      'reason': 'detach only',
      'entityIds': ['home']
    };
    final preview = await f.call('media.entities.remove_batch', input);
    final episode = (preview['preview'] as List)
        .cast<JsonMap>()
        .singleWhere((item) => (item['entity'] as JsonMap)['id'] == 'episode');
    final progress =
        (((episode['files'] as List).single as JsonMap)['progress'] as List)
            .single as JsonMap;
    expect(progress, containsPair('lastPosition', 18000));
    expect(progress, containsPair('observed', true));
    f.classic.rows[locator]!['lastPosition'] = 19000;
    final apply = {
      ...input,
      'preview': false,
      'expectedPlan': preview['expectedPlan']
    };
    final removed = await f.call('media.entities.remove_batch', apply);
    expect(await f.call('media.entities.remove_batch', apply), removed);
    expect(await f.identities.library(), isEmpty);
    expect(await f.identities.database.query('media_locations'), isNotEmpty);
    expect(await File('${f.media.path}/home.mkv').exists(), true);
    await f.call('media.entities.restore', {'undoId': removed['undoId']});
    expect(
        await f.identities.database.query('media_file_episodes'), hasLength(1));
    expect(await f.identities.library(), hasLength(1));
    expect(await f.identities.database.query('media_legacy_history'),
        historyBefore);
    expect(f.classic.rows[locator]!['lastPosition'], 19000);
    expect(
        await f.identities.database.query('body_changes',
            where: 'type=?', whereArgs: ['media.entities.remove_batch']),
        hasLength(1));
  });
  test(
      'invalid later entry rolls back entire batch; stale update/remove preview cannot change facts',
      () async {
    final invalid = await f.harness.invokeJson(
        'media.entities.put_batch',
        {
          'requestId': 'bad',
          'reason': 'test',
          'entries': [
            {'kind': 'work', 'entityId': 'w', 'title': 'Title'},
            {
              'kind': 'episode',
              'entityId': 'e',
              'parentId': 'w',
              'title': 'Invalid parent'
            },
          ]
        },
        Invocation(origin: 'mcp'));
    expect(invalid, isA<Failed>());
    expect(await f.identities.database.query('media_entities'), isEmpty);
    await put('good', [
      {'kind': 'work', 'entityId': 'w', 'title': 'Title'}
    ]);
    final change = {
      'requestId': 'change',
      'reason': 'rename',
      'preview': true,
      'entries': [
        {
          'kind': 'work',
          'entityId': 'w',
          'title': 'Renamed',
          'expectedRevision': 0
        }
      ]
    };
    final preview = await f.call('media.entities.put_batch', change);
    await f.call('media.entities.put_batch',
        {...change, 'preview': false, 'expectedPlan': preview['expectedPlan']});
    final stale = await f.harness.invokeJson(
        'media.entities.put_batch',
        {
          ...change,
          'requestId': 'stale',
          'preview': false,
          'expectedPlan': preview['expectedPlan']
        },
        Invocation(origin: 'mcp'));
    expect(stale, isA<Failed>());
    expect((await f.identities.entity('w'))['revision'], 1);
  });

  test(
      'shared file relationships survive subtree removal and restore, while later association changes conflict',
      () async {
    final file = await f.file('collection.mkv');
    await put('shared-create', [
      {'kind': 'work', 'entityId': 'w', 'title': 'Collection'},
      {'kind': 'release', 'entityId': 'r', 'parentId': 'w', 'title': 'Edition'},
      for (final id in ['e1', 'e2'])
        {
          'kind': 'episode',
          'entityId': id,
          'parentId': 'r',
          'title': id,
          'fileIds': [file]
        }
    ]);
    Future<JsonMap> remove(String id, String request) async {
      final input = {
        'entityIds': [id],
        'requestId': request,
        'reason': 'shared relationship test'
      };
      final preview = await f.call('media.entities.remove_batch', input);
      return f.call('media.entities.remove_batch', {
        ...input,
        'preview': false,
        'expectedPlan': preview['expectedPlan']
      });
    }

    final one = await remove('e1', 'one');
    expect(
        await f.identities.database.query('media_file_episodes'), hasLength(1));
    await f.call('media.entities.restore', {'undoId': one['undoId']});
    expect(
        await f.identities.database.query('media_file_episodes'), hasLength(2));
    final all = await remove('w', 'all');
    expect(await f.identities.database.query('media_file_episodes'), isEmpty);
    await f.call('media.entities.restore', {'undoId': all['undoId']});
    expect(
        await f.identities.database.query('media_file_episodes'), hasLength(2));
    final conflict = await remove('e1', 'conflict');
    await put('third', [
      {
        'kind': 'episode',
        'entityId': 'e3',
        'parentId': 'r',
        'title': 'Third',
        'fileIds': [file]
      }
    ]);
    final result = await f.harness.invokeJson('media.entities.restore',
        {'undoId': conflict['undoId']}, Invocation(origin: 'mcp'));
    expect(result, isA<Failed>());
    expect((await f.identities.entity('e1'))['attributes'],
        containsPair('removed', true));
    expect(
        await f.identities.database.query('media_file_episodes'), hasLength(2));
  });
}
