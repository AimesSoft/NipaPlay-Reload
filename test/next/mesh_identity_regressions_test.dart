import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/headless/ports.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/mesh/library_codec.dart';
import 'package:nipaplay/next/mesh/library_worker.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../security/memory_vault.dart';
import 'support/platform.dart';
import 'media_test_support.dart';
import 'danmaku_test_support.dart';
import 'package:nipaplay/next/danmaku/automatic.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'dart:async';

Future<JsonMap> _probeInWorker(String path) async => {
      'subtitles': [
        {
          'index': 0,
          'streamIndex': 2,
          'language': 'jpn',
          'title': Isolate.current.debugName == 'next-library'
              ? 'worker-probe'
              : 'main-probe',
          'format': 'ass'
        }
      ]
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore jobs;
  late UiDataService ui;
  late LibraryWorker worker;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('library-worker-');
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final media = MediaService(
        store: IdentityStore(jobs.database, 'owner'),
        providers: const [],
        classic: NoClassic(),
        authorizedRoots: () => [root.path]);
    final sources = StateSources()..history = () => [];
    final state = StateCapability(publicStateViews(
        media: media,
        settings: SettingsRegistry(jobs.database, const []),
        danmaku: DanmakuService(
            store: DanmakuStore(media.store),
            sources: const [],
            player: NoPlayer()),
        mesh: NoMesh(),
        sources: sources));
    ui = UiDataService(media, TaskEngine(store: jobs, ownerDeviceId: 'owner'),
        state, sources, root, MemoryVault());
    worker = LibraryWorker(ui, subtitleProbe: _probeInWorker);
    state.queryWorker = worker.query;
    final db = jobs.database;
    await db.insert('media_entities', {
      'id': 'w',
      'kind': 'work',
      'attributes': jsonEncode({'title': '最初的名字', 'localOnly': true})
    });
    await db.insert('media_entities',
        {'id': 'r', 'kind': 'release', 'parent_id': 'w', 'attributes': '{}'});
    for (var i = 1; i <= 3; i++) {
      await db.insert('media_entities', {
        'id': 'e$i',
        'kind': 'episode',
        'parent_id': 'r',
        'attributes': jsonEncode({'title': '第 $i 集', 'number': '$i'})
      });
    }
  });
  tearDown(() async {
    await worker.close();
    await ui.close();
    await ui.sources.close();
    await jobs.database.close();
    await deleteTestDirectory(root);
  });

  test('progress changes do not retransmit an unchanged rich catalogue',
      () async {
    await worker.build('fixed-content');
    final first = await worker.call('snapshot', (
      <String, Object?>{
        'offset': 0,
        'encoding': 'json-base64-v1',
        'progressSeparately': true
      },
      0
    )) as JsonMap;
    await worker.call('merge', <String, JsonMap>{
      'episode:e1': {
        'progress': 0.4,
        'at': '2026-10-28T10:00:00Z',
        'writer': 'peer'
      }
    });
    final next = await worker.call('snapshot', (
      <String, Object?>{
        'offset': 0,
        'encoding': 'json-base64-v1',
        'progressSeparately': true,
        'known': first['version']
      },
      1
    )) as JsonMap;
    expect(next['unchanged'], true);
    expect(next['data'], isNull);
    expect(((next['progress'] as Map)['episode:e1'] as Map)['progress'], 0.4);
  });

  test('newer sparse peer retains older source fields', () async {
    await worker.build('probe');
    JsonMap peer(String when, JsonMap fields) => {
          'name': 'peer',
          'records': [
            {
              'kind': 'work',
              'id': 'remote',
              'keys': [
                jsonEncode(['tmdb', 'tv', '', '999'])
              ],
              'added': 1,
              'attributes': <String, Object?>{},
              'metadata': {
                'fields': fields,
                'sources': [
                  {
                    'provider': 'tmdb',
                    'objectType': 'tv',
                    'externalId': '999',
                    'scope': '',
                    'language': 'zh-CN',
                    'fetchedAt': when,
                    'fields': fields
                  }
                ]
              },
              'value': workJson(const UiWork(workId: 'remote', title: 'probe'))
            }
          ]
        };
    final snapshot = await worker.compose({
      'a': peer('2026-10-20', {
        'title': 'probe',
        'actors': ['kept actor']
      }),
      'b': peer('2026-10-21', {'title': 'probe', 'imageUrl': 'image'})
    }, {
      'a': true,
      'b': true
    }, null);
    final work = snapshot.works.values.singleWhere((w) => w.title == 'probe');
    final evidence = await worker.call('evidence', work.workId) as JsonMap;
    final source =
        ((evidence['metadata'] as Map)['sources'] as List).single as Map;
    expect((source['fields'] as Map).containsKey('actors'), true);
  });
  test('explicit empty provider collection clears composite', () async {
    final f = MediaFixture();
    await f.open();
    try {
      final file = await f.file('empty.mkv');
      final result = await f.call('media.identity.bind_batch', {
        'requestId': 'bind',
        'entries': [tmdbBinding(file)]
      });
      final work =
          ((result['entries'] as List).single as Map)['workId'] as String;
      final object = (await f.jobs.database.query('media_external_objects',
              where: "provider='tmdb' AND object_type='tv'"))
          .single['id'];
      for (final entry in [
        (
          '2026-10-20',
          <String, Object?>{
            'actors': ['removed actor'],
            'overview': 'removed overview'
          }
        ),
        ('2099-10-21', <String, Object?>{'actors': [], 'overview': null})
      ]) {
        await f.jobs.database.insert('media_snapshots', {
          'id': entry.$1,
          'object_id': object,
          'language': 'zh-CN',
          'fetched_at': entry.$1,
          'fields':
              jsonEncode({'source': 'provider_snapshot', 'metadata': entry.$2})
        });
      }
      final metadata = await f.identities.mergedMetadata(work);
      final source = (metadata['sources'] as List)
          .cast<Map>()
          .singleWhere((s) => s['objectType'] == 'tv');
      expect((metadata['fields'] as Map)['actors'], isEmpty);
      expect((source['fields'] as Map)['actors'], isEmpty);
    } finally {
      await f.close();
    }
  });
  test('metadata identity confirmed during hashing wins', () async {
    final f = DanmakuFixture();
    await f.open();
    try {
      final id = await f.file();
      final entered = Completer<void>();
      final release = Completer<void>();
      final loader = AutomaticDanmaku(f.service,
          matchHash: (_) async {
            entered.complete();
            await release.future;
            return [ddpVideo];
          },
          readSettings: () async => (
                strategy: DanmakuAutoLoadStrategy.remoteAndLocal,
                skipMatching: false
              ));
      final pending = loader.prepare('/fixture/video.mkv', fileId: id);
      await entered.future;
      await f.service.store.db.insert('media_external_objects', {
        'id': 'manual-new',
        'provider': 'dandanplay',
        'object_type': 'episode',
        'external_id': '9999',
        'scope': 'anime/7001'
      });
      await f.service.store.db.insert('media_bindings', {
        'id': 'manual-new-binding',
        'entity_id': id,
        'object_id': 'manual-new',
        'relation': 'exact',
        'scope': '{}',
        'status': 'accepted',
        'source': 'explicit_binding',
        'bound_by': 'user',
        'revision': 0,
        'created_at': DateTime.now().toIso8601String()
      });
      release.complete();
      await pending;
      final binding = (await f.service.store.bindings(id)).single;
      expect((binding['video'] as Map)['videoId'], '9999');
    } finally {
      await f.close();
    }
  });
  test('Mesh and local choose the same unique video pool', () async {
    final f = DanmakuFixture();
    await f.open();
    try {
      final id = await f.file();
      final db = f.service.store.db;
      await db.insert('media_entities',
          {'id': 'episode', 'kind': 'episode', 'attributes': '{}'});
      await db.insert('media_file_episodes', {
        'file_id': id,
        'episode_id': 'episode',
        'relation': 'local_catalog',
        'ordinal': 0
      });
      final b1 = await f.service.store.importEntries(id, ddpVideo, [],
          '/tmp/import-file.json', 'newer file', Invocation(origin: 'gui'));
      final b2 = await f.service.store.importEntries('episode', ddpVideo, [],
          '/tmp/import-episode.json', 'episode', Invocation(origin: 'gui'));
      await f.service.refreshCurrent();
      expect(f.player.tracks.length, 1);
      f.player.tracks.clear();
      f.service.remoteTracks = (_) async => [
            for (final binding in [b1, b2])
              <String, Object?>{
                'binding': binding,
                'entries': <JsonMap>[],
                'startMs': 0,
                'endMs': null
              }
          ];
      await f.service.refreshCurrent();
      expect(f.player.tracks.length, 1);
    } finally {
      await f.close();
    }
  });
  test(
      'distinct works in disjoint ranges of identical compilation remain distinct',
      () async {
    await worker.build('range-collision');
    JsonMap peer(String device, String external, int start, int end) => {
          'name': device,
          'records': <JsonMap>[
            {
              'kind': 'work',
              'id': 'work-$device',
              'keys': [
                jsonEncode(['tmdb', 'tv', '', external])
              ],
              'added': 1,
              'attributes': <String, Object?>{},
              'metadata': <String, Object?>{
                'fields': <String, Object?>{},
                'provenance': <String, Object?>{},
                'sources': <JsonMap>[],
                'ratings': <JsonMap>[]
              },
              'value': workJson(
                  UiWork(workId: 'work-$device', title: 'Series $external'))
            },
            {
              'kind': 'episode',
              'id': 'episode-$device',
              'workId': 'work-$device',
              'keys': [
                jsonEncode([
                  'tmdb',
                  'episode',
                  'tv/$external/season/1/episode/1',
                  '${external}1'
                ])
              ],
              'files': [
                {
                  'fileId': 'file-$device',
                  'sample': 'same-real-compilation-digest',
                  'startMs': start,
                  'endMs': end
                }
              ],
              'metadata': <String, Object?>{
                'fields': <String, Object?>{},
                'provenance': <String, Object?>{},
                'sources': <JsonMap>[],
                'ratings': <JsonMap>[]
              },
              'danmaku': [],
              'subtitles': [],
              'subtitleFiles': [],
              'value': episodeJson(UiEpisode(
                  episodeId: 'episode-$device',
                  workId: 'work-$device',
                  title: 'Series $external',
                  number: 1,
                  season: 1,
                  playable: true))
            }
          ]
        };
    final snapshot = await worker.compose({
      'a': peer('a', '100', 0, 60000),
      'b': peer('b', '200', 60000, 120000),
    }, {
      'a': true,
      'b': true
    }, null);
    final remoteWorks = snapshot.works.values
        .where((w) => w.title.startsWith('Series'))
        .toList();
    expect(remoteWorks.length, 2);
    final aWork = remoteWorks.singleWhere((w) => w.title == 'Series 100');
    final bWork = remoteWorks.singleWhere((w) => w.title == 'Series 200');
    final episode = snapshot.episodes[aWork.workId]!.single;
    expect(snapshot.episodes[bWork.workId], hasLength(1));
    await worker.call('progress', <JsonMap>[
      {
        'episodeId': episode.episodeId,
        'progress': 0.5,
        'positionMs': 30000,
        'durationMs': 60000
      }
    ]);
    final saved =
        (await jobs.database.query('ui_cache', where: "id='mesh:progress'"))
            .single;
    final observed = jsonDecode(saved['payload'] as String) as Map;
    String ref(String device) =>
        'mesh-ref:${base64Url.encode(utf8.encode(jsonEncode([
                  device,
                  'episode-$device'
                ]))).replaceAll('=', '')}';
    expect((observed[ref('a')] as Map)['progress'], 0.5);
    expect(observed[ref('b')], isNull);
  });
}
