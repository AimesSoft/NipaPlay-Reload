import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/library_capability.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'download_test_support.dart';
import 'media_test_support.dart';
import 'test_support.dart';

Future<JsonMap> call(Harness api, String id, JsonMap input) async {
  final outcome = await api.invokeJson(id, input, Invocation(origin: 'mcp'));
  expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
  final result = (outcome as Completed).value.toJson();
  expect(api.lookup(id)!.spec.output.validate(result), isEmpty);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  group('public Core views', () {
    late NextCore core;
    late Harness api;
    late Directory root;
    late FakeDownloadBackend backend;
    late FixtureTransport tmdb;
    late List<JsonMap> history;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('next-state-');
      backend = FakeDownloadBackend(root);
      tmdb = FixtureTransport('tmdb');
      core = NextCore(
          root: root,
          databaseFactory: databaseFactoryFfi,
          downloadBackend: backend,
          downloadLibrary: FakeDownloadLibrary(),
          isDownloaderEnabled: () async => false,
          loadImportedKeys: () async => {},
          classic: MemoryClassic(),
          authorizedRoots: () => [root.path],
          mediaProviders: [TmdbMetadataProvider(tmdb)],
          mediaDurationProbe: (_) async => 10000);
      await core.ready;
      history = [];
      core.stateSources.history = () => history;
      core.stateSources.continueWatching = () => history;
      core.stateSources.classicLibrary = classicLibraryStateViews(
          history: () => [], seriesDetail: (_) => null);
      api = Harness(core.capabilities);
    });
    tearDown(() async {
      await core.close();
      await root.delete(recursive: true);
    });

    test(
        'one state.query returns all episodes files bindings and viewing progress',
        () async {
      final entries = <JsonMap>[];
      for (var number = 1; number <= 2; number++) {
        final path = '${root.path}/episode$number.mkv';
        await File(path).writeAsString('offline video');
        final id = await core.media.service.index(path);
        entries.add(tmdbBinding(id, episodes: [number]));
        history.add({
          'filePath': path,
          'animeName': '长安十二时辰',
          'lastPosition': number * 1000,
          'duration': 10000,
          'watchProgress': number / 10,
          'lastWatchTime': '2026-10-11T01:00:00Z'
        });
      }
      final binding = await call(api, 'media.identity.bind_batch',
          {'requestId': 'state-work', 'entries': entries});
      final workId = ((binding['entries'] as List).first as Map)['workId'];
      final db = core.media.service.store.database;
      final before = await db.rawQuery('SELECT total_changes() AS changes');
      final requests = tmdb.requests.length;
      final response = await call(api, 'state.query', {
        'view': 'library.works',
        'filter': {
          'id': {'eq': workId}
        },
        'include': {
          'episodes': {
            'limit': 200,
            'include': {
              'files': {'limit': 200}
            }
          }
        }
      });
      final work = (response['rows'] as List).single as Map;
      final episodes = ((work['episodes'] as Map)['rows'] as List).cast<Map>();
      expect(episodes.length, 2);
      final files = [
        for (final episode in episodes)
          ...((episode['files'] as Map)['rows'] as List)
      ];
      expect(files.length, 2);
      expect(files.map((row) => (row as Map)['fileId']).toSet().length, 2);
      expect(
          files.every((row) =>
              (row as Map)['bindings'] is List &&
              (row['bindings'] as List).isNotEmpty),
          isTrue);
      expect(
          files
              .map((row) => ((row as Map)['progress'] as Map)['positionMs'])
              .toSet(),
          {1000, 2000});
      expect(response['truncated'], false);
      expect(response['snapshotId'], null);
      expect(await db.rawQuery('SELECT total_changes() AS changes'), before);
      expect(tmdb.requests.length, requests);
      expect(backend.additions, 0);
      final old = await call(api, 'media.library.work', {'workId': workId});
      expect((old['work'] as Map)['title'], work['title']);
      expect(
          (await call(api, 'state.query', {'view': 'history.entries'}))['rows'],
          hasLength(2));
    });

    test(
        'all registered views exclude secret fields and authenticated URL components without writes',
        () async {
      final db = core.media.service.store.database;
      final now = DateTime.now().toUtc();
      const secret = 'state-query-private-marker';
      final job = Job(
          jobId: 'secret-download',
          type: 'download',
          title: 'Offline test',
          state: JobState.succeeded,
          phase: 'done',
          progress: JobProgress(completed: 1, unit: 'files'),
          createdAt: now,
          updatedAt: now,
          ownerDeviceId: core.deviceId,
          revision: 0,
          input: {'token': secret},
          checkpoint: {'cookie': secret},
          details: {
            'authentication': {'password': secret},
            'credentialRef': secret
          },
          receipt:
              JobReceipt(verification: VerificationLevel.verified, details: {
            'token': secret,
            'session': {'secret': secret},
            'infoHash': testHash,
            'files': [
              {
                'path':
                    'https://user:$secret@example.test/video.mkv?token=$secret#signature=$secret',
                'expectedSize': 42,
                'headers': {'Authorization': secret},
                'cookie': secret
              }
            ]
          }));
      await db.insert('jobs', {
        'job_id': job.jobId,
        'type': job.type,
        'state': job.state.wireName,
        'revision': 0,
        'created_at': now.toIso8601String(),
        'snapshot': jsonEncode(job.toStorageJson())
      });
      await db.insert('job_events', {
        'job_id': job.jobId,
        'revision': 0,
        'kind': 'succeeded',
        'at': now.toIso8601String(),
        'snapshot': jsonEncode(job.toJson())
      });
      final description = await call(api, 'state.describe', {});
      expect((description['views'] as List).length, 20);
      final before = await db.rawQuery('SELECT total_changes() AS changes');
      for (final view in core.state.views.values) {
        final result = await call(api, 'state.query', {'view': view.name});
        final encoded = jsonEncode(result);
        expect(encoded, isNot(contains(secret)), reason: view.name);
        for (final key in [
          'token',
          'cookie',
          'password',
          'credentialRef',
          'input',
          'checkpoint',
          'Authorization',
          'authentication'
        ]) {
          expect(encoded, isNot(contains('"$key":')),
              reason: '${view.name}: $key');
        }
        expect(view.describe()['fields'], publicSchema(view.fields));
        for (final row in result['rows'] as List) {
          expect(view.fields.validate(row), isEmpty, reason: view.name);
        }
      }
      final downloads = await call(api, 'state.query', {
        'view': 'downloads',
        'include': {'events': {}}
      });
      final file = (((((downloads['rows'] as List).single as Map)['receipt']
              as Map)['details'] as Map)['files'] as List)
          .single as Map;
      expect(file['path'], 'https://example.test/video.mkv');
      expect(file['expectedSize'], 42);
      expect(await db.rawQuery('SELECT total_changes() AS changes'), before);
      expect(tmdb.requests, isEmpty);
      expect(backend.additions, 0);
    });

    test(
        'registered setting schemas project history values and filter hidden keys',
        () async {
      final db = core.settings.database;
      for (final key in [
        'danmaku.opacity',
        'dandanplay_token',
        'agent.endpoint'
      ]) {
        await db.insert('settings_changes', {
          'key': key,
          'previous_value': '1.0',
          'value': '0.5',
          'changed_at': '2026-10-11T00:00:00Z',
          'changed_by': 'agent',
          'origin': 'mcp',
          'invocation_id': 'state-settings',
          'revision': 1
        });
      }
      final response = await call(api, 'state.query', {
        'view': 'settings.changes',
        'filter': {
          'key': {'eq': 'danmaku.opacity'}
        }
      });
      final row = (response['rows'] as List).single as Map;
      expect(row['valueJson'], '0.5');
      expect(row['previousValueJson'], '1.0');
      expect(row['changedBy'], 'agent');
      expect(
          (await call(
              api, 'state.query', {'view': 'settings.changes'}))['rows'],
          hasLength(1));
    });

    test('Classic URL filename fallback excludes authentication parameters',
        () async {
      const secret = 'classic-private-marker';
      final rows = [
        watchItem(
            'https://user:$secret@example.test/video.mp4?token=$secret#signature=$secret',
            episodeTitle: null)
      ];
      core.stateSources.classicLibrary = classicLibraryStateViews(
          history: () => rows, seriesDetail: (_) => null);
      final result = await call(api, 'state.query', {
        'view': 'library.classic_series',
        'include': {'episodes': {}}
      });
      expect(result['rows'], isNotEmpty);
      expect(jsonEncode(result), isNot(contains(secret)));
      final episode = (((result['rows'] as List).single as Map)['episodes']
          as Map)['rows'] as List;
      expect((episode.single as Map)['title'], 'video.mp4');
    });

    test(
        'history joins use recorded file IDs and unavailable history is explicit',
        () async {
      final path = '${root.path}/history.mkv';
      await File(path).writeAsString('fixture');
      final id = await core.media.service.index(path);
      history.add({
        'filePath': path,
        'lastPosition': 17,
        'duration': 20,
        'watchProgress': 0.85
      });
      final query = await call(api, 'state.query', {
        'view': 'library.files',
        'filter': {
          'fileId': {'eq': id}
        },
        'include': {'history': {}}
      });
      final file = (query['rows'] as List).single as Map;
      final row = ((file['history'] as Map)['rows'] as List).single as Map;
      expect(row['fileId'], id);
      expect(row['positionMs'], 17);
      core.stateSources.history = null;
      final outcome = await api.invokeJson('state.query',
          {'view': 'history.entries'}, Invocation(origin: 'mcp')) as Failed;
      expect(outcome.failure.code, FailureCode.unavailable);
      expect(outcome.failure.message, 'history_unavailable');
    });

    test(
        'Classic query projections preserve existing getter identities and progress',
        () async {
      final playback = PlaybackFixture();
      final library = LibraryCapability(
          history: () => playback.rows, seriesDetail: (_) => seriesDetail());
      core.stateSources.classicLibrary = classicLibraryStateViews(
          history: () => playback.rows, seriesDetail: (_) => seriesDetail());
      final legacy = Harness([library]);
      final old = await call(legacy, 'media.library.series', {'animeId': 10});
      final response = await call(api, 'state.query', {
        'view': 'library.classic_series',
        'filter': {
          'animeId': {'eq': 10}
        },
        'include': {'episodes': {}}
      });
      final row =
          Map<String, Object?>.from((response['rows'] as List).single as Map);
      final episodes =
          ((row.remove('episodes') as Map)['rows'] as List).cast<Map>();
      row.remove('searchText');
      expect(row, old['series']);
      expect([
        for (final ep in episodes) {...ep}..remove('animeId')
      ], old['episodes']);
    });
  });

  group('query budgets and validation', () {
    Harness fixture(List<JsonMap> rows,
            {ObjectSchema? fields,
            Map<String, StateRelation> relations = const {},
            List<StateView> extra = const []}) =>
        Harness([
          StateCapability([
            StateView(
                name: 'items',
                description: 'Offline items.',
                fields: fields ??
                    const ObjectSchema(
                        {'id': IntegerSchema(), 'title': StringSchema()}),
                relations: relations,
                read: (offset, limit) async =>
                    rows.skip(offset).take(limit).toList()),
            ...extra
          ])
        ]);
    test('filters projection stable sorting and query-bound pagination',
        () async {
      final api = fixture([
        for (var i = 0; i < 7; i++)
          {'id': i, 'title': i.isEven ? 'Series' : 'Other'}
      ]);
      final input = <String, Object?>{
        'view': 'items',
        'filter': {
          'title': {'contains': 'series'},
          'id': {'gte': 2}
        },
        'select': ['id'],
        'orderBy': [
          {'field': 'id', 'direction': 'desc'}
        ],
        'limit': 2
      };
      final first = await call(api, 'state.query', input);
      expect(first['rows'], [
        {'id': 6},
        {'id': 4}
      ]);
      expect(first['truncated'], true);
      final second = await call(
          api, 'state.query', {...input, 'cursor': first['nextCursor']});
      expect(second['rows'], [
        {'id': 2}
      ]);
      expect(second['nextCursor'], null);
      final failure = await api.invokeJson(
          'state.query',
          {...input, 'limit': 1, 'cursor': first['nextCursor']},
          Invocation(origin: 'mcp')) as Failed;
      expect(failure.failure.code, FailureCode.invalidInput);
    });
    test(
        'unknown views fields relations operators and deep joins fail before reading',
        () async {
      var reads = 0;
      final api = Harness([
        StateCapability([
          StateView(
              name: 'items',
              description: 'fixture',
              fields: const ObjectSchema({'id': IntegerSchema()}),
              relations: {'self': const StateRelation('items', 'id', 'id')},
              read: (_, __) async {
                reads++;
                return [];
              })
        ])
      ]);
      for (final input in <JsonMap>[
        {'view': 'credentials'},
        {
          'view': 'items',
          'select': ['token']
        },
        {
          'view': 'items',
          'filter': {
            'id': {'sql': 'DROP TABLE jobs'}
          }
        },
        {
          'view': 'items',
          'filter': {
            'id': {'eq': 'wrong-type'}
          }
        },
        {
          'view': 'items',
          'include': {'unknown': {}}
        },
        {
          'view': 'items',
          'include': {
            'self': {
              'include': {
                'self': {
                  'include': {'self': {}}
                }
              }
            }
          }
        },
        {'view': 'items', 'limit': 201},
        {'view': 'items', 'cursor': 'not a cursor'},
      ]) {
        final outcome = await api.invokeJson(
            'state.query', input, Invocation(origin: 'mcp')) as Failed;
        expect(outcome.failure.code, FailureCode.invalidInput,
            reason: jsonEncode(input));
      }
      expect(reads, 0);
    });
    test(
        'nested public schemas exclude secrets even in malformed object values',
        () async {
      final api = fixture([
        {
          'id': 1,
          'token': 'private',
          'details': {'id': 'safe', 'cookie': 'private', 'secret': 'private'}
        },
        {'id': 2, 'details': 'private'}
      ],
          fields: const ObjectSchema({
            'id': IntegerSchema(),
            'token': StringSchema(secret: true),
            'details': ObjectSchema(
                {'id': StringSchema(), 'secret': StringSchema(secret: true)})
          }));
      final response = await call(api, 'state.query', {'view': 'items'});
      expect(jsonEncode(response), isNot(contains('private')));
      expect((response['rows'] as List).first, {
        'id': 1,
        'details': {'id': 'safe'}
      });
      expect(jsonEncode(await call(api, 'state.describe', {})),
          isNot(contains('"token":')));
    });
    test('scan budget continuation reaches rows beyond the first 5000',
        () async {
      final api = fixture([
        for (var i = 0; i < 5005; i++) {'id': i, 'title': 'row'}
      ]);
      final input = <String, Object?>{
        'view': 'items',
        'filter': {
          'id': {'gte': 5000}
        }
      };
      final first = await call(api, 'state.query', input);
      expect(first['rows'], isEmpty);
      expect(first['warnings'], contains('scan_limit'));
      expect(first['nextCursor'], isNotNull);
      final second = await call(
          api, 'state.query', {...input, 'cursor': first['nextCursor']});
      expect(second['rows'], hasLength(5));
      expect(second['truncated'], false);
    });
    test('row relation array and byte limits report omissions', () async {
      final children = StateView(
          name: 'children',
          description: 'fixture',
          fields: const ObjectSchema(
              {'parent': IntegerSchema(), 'id': IntegerSchema()}),
          read: (offset, limit) async => [
                for (var i = 0; i < 250; i++) {'parent': 1, 'id': i}
              ].skip(offset).take(limit).toList());
      final api = fixture([
        {'id': 1, 'title': 'work'}
      ], relations: {
        'children': const StateRelation('children', 'id', 'parent')
      }, extra: [
        children
      ]);
      final result = await call(api, 'state.query', {
        'view': 'items',
        'include': {
          'children': {'limit': 200}
        }
      });
      final relation =
          ((result['rows'] as List).single as Map)['children'] as Map;
      expect(relation['rows'], hasLength(199));
      expect(relation['truncated'], true);
      expect(relation['nextQuery'], isNotNull);
      expect(result['warnings'], contains('relation_limit'));
      final large = fixture([
        {'id': 1, 'title': 'a' * 130000},
        {'id': 2, 'title': 'b' * 130000}
      ]);
      final bytes = await call(large, 'state.query', {'view': 'items'});
      expect(bytes['rows'], hasLength(1));
      expect(bytes['warnings'], contains('byte_limit'));
      expect(utf8.encode(jsonEncode(bytes)).length,
          lessThanOrEqualTo(StateCapability.maxBytes));
      final array = fixture([
        {'id': 1, 'names': List.filled(201, 'item')}
      ],
          fields: const ObjectSchema(
              {'id': IntegerSchema(), 'names': ArraySchema(StringSchema())}));
      final arrayResult = await call(array, 'state.query', {'view': 'items'});
      expect(arrayResult['warnings'], contains('field_limit'));
      expect(((arrayResult['rows'] as List).single as Map)['names'],
          hasLength(200));
    });
    test(
        'timeout and concurrent readers are bounded and do not cancel unrelated tasks',
        () async {
      final gate = Completer<void>();
      final api = Harness([
        StateCapability([
          StateView(
              name: 'slow',
              description: 'fixture',
              fields: const ObjectSchema({'id': IntegerSchema()}),
              read: (_, __) async {
                await gate.future;
                return [];
              })
        ])
      ]);
      final first = api.invokeJson('state.query',
          {'view': 'slow', 'timeoutMs': 20}, Invocation(origin: 'mcp'));
      final second = api.invokeJson('state.query',
          {'view': 'slow', 'timeoutMs': 20}, Invocation(origin: 'mcp'));
      final third = await api.invokeJson(
          'state.query',
          {'view': 'slow', 'timeoutMs': 20},
          Invocation(origin: 'mcp')) as Failed;
      expect(third.failure.message, 'query_concurrency_limit');
      final result = ((await first) as Completed).value.toJson();
      expect(result['truncated'], true);
      expect(result['warnings'], contains('time_limit'));
      expect(result['nextCursor'], isNotNull);
      await second;
      gate.complete();
    });
    test('source failures return a stable error without raw secrets or paths',
        () async {
      final api = Harness([
        StateCapability([
          StateView(
              name: 'broken',
              description: 'fixture',
              fields: const ObjectSchema({}),
              read: (_, __) async =>
                  throw StateError('cookie=private /secret/database.db'))
        ])
      ]);
      final failure = await api.invokeJson(
              'state.query', {'view': 'broken'}, Invocation(origin: 'mcp'))
          as Failed;
      expect(failure.failure.message, 'state_read_failed');
      final domain = Harness([
        StateCapability([
          StateView(
              name: 'broken',
              description: 'fixture',
              fields: const ObjectSchema({}),
              read: (_, __) async => throw const Failure(
                  FailureCode.unavailable,
                  'cookie=private /secret/database.db'))
        ])
      ]);
      final hidden = await domain.invokeJson(
              'state.query', {'view': 'broken'}, Invocation(origin: 'mcp'))
          as Failed;
      expect(hidden.failure.code, FailureCode.unavailable);
      expect(hidden.failure.message, 'state_source_failed');
    });
  });
}
