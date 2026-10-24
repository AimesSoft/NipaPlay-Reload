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
import 'package:nipaplay/next/mesh/library_projection.dart';
import 'package:nipaplay/next/mesh/library_worker.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../security/memory_vault.dart';

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
    await root.delete(recursive: true);
  });
  test('background build, SQL query, live host relations and progress persist',
      () async {
    await worker.build('one');
    final snapshot = await worker.compose({}, {}, null);
    expect(snapshot.works.values.single.title, '最初的名字');
    expect(snapshot.episodes.values.single, hasLength(3));
    final id = snapshot.aliases['e2']!;
    final update = await worker.call('progress', [
      {'episodeId': id, 'progress': 0.4, 'positionMs': 400, 'durationMs': 1000}
    ]) as LibraryProgress;
    expect(
        update.episodes.values.single
            .singleWhere((e) => e.episodeId == id)
            .progress,
        .4);
    expect((await jobs.database.query('ui_cache', where: "id='mesh:progress'")),
        hasLength(1));
    expect(update.works, hasLength(1));
    // SQL readers must run on the worker: replacing the UI reader with a
    // failure leaves this query usable.
    final original = ui.state.views['library.episodes']!;
    ui.state.views[original.name] = StateView(
        name: original.name,
        description: original.description,
        fields: original.fields,
        background: true,
        relations: original.relations,
        read: (_, __) => throw StateError('SQL ran on main'));
    final result = await ui.state.query({
      'view': 'library.episodes',
      'filter': {
        'number': {'eq': '2'}
      },
      'select': ['id', 'title']
    });
    expect(result['rows'], [
      {'id': 'e2', 'title': '第 2 集'}
    ]);
    ui.state.views['live'] = StateView(
        name: 'live',
        description: 'live supplier',
        fields: const ObjectSchema(
            {'id': StringSchema(), 'private': StringSchema(secret: true)}),
        read: (_, __) async => [],
        readAll: () async => const StateRows([
              {'id': 'pushed', 'private': 'never public'}
            ]));
    final live = await ui.state.query({'view': 'live'});
    expect(live['rows'], [
      {'id': 'pushed'}
    ]);
    await worker.build('two');
    final rebuilt = await worker.compose({}, {}, null);
    expect(
        rebuilt.episodes.values.single
            .singleWhere((e) => e.episodeId == id)
            .progress,
        .4);
  });
  test('startup indexers scan, parse and commit in the library worker',
      () async {
    await worker.warm();
    final folder = await Directory('${root.path}/media').create();
    final video = File('${folder.path}/episode.mkv');
    await video.writeAsString('video');
    await File('${folder.path}/episode.xml').writeAsString(
        '<i><d p="1,1,25,16777215,1,0,s,1">sidecar text</d></i>');
    await File('${folder.path}/episode.zh.srt')
        .writeAsString('1\n00:00:00,000 --> 00:00:01,000\n字幕\n');
    final db = jobs.database;
    await db.insert('media_entities', {
      'id': 'index-file',
      'kind': 'file',
      'attributes': jsonEncode({
        'probe': {'durationMs': 1000}
      })
    });
    await db.insert('media_locations', {
      'id': 'index-location',
      'file_id': 'index-file',
      'source': 'local',
      'owner_device_id': 'owner',
      'locator': video.path,
      'available': 1
    });

    final result = await worker.reconcileIndexers(
      danmaku: true,
      subtitles: true,
      subtitlePreferences: const {
        'videoSubtitleMap': '{}',
        'languageMode': 'auto',
        'traditional': false,
        'values': <String, Object?>{},
      },
    );
    expect((result['sidecars'] as Map)['changed'], 1);
    expect((result['subtitles'] as Map)['changed'], 1);
    final bindings = await db.query('danmaku_bindings');
    expect(bindings, hasLength(1));
    expect((jsonDecode(bindings.single['local_file'] as String) as Map)['path'],
        '${folder.path}/episode.xml');
    final subtitle =
        jsonDecode((await db.query('file_subtitles')).single['facts'] as String)
            as Map;
    expect(
        ((subtitle['tracks'] as List)
                .firstWhere((track) => (track as Map)['origin'] == 'embedded')
            as Map)['title'],
        'worker-probe');
    expect(
        (subtitle['tracks'] as List)
            .where((track) => (track as Map)['origin'] == 'sidecar'),
        hasLength(1));

    final unchanged = await worker.reconcileIndexers(
      danmaku: true,
      subtitles: true,
      subtitlePreferences: const {
        'videoSubtitleMap': '{}',
        'languageMode': 'auto',
        'traditional': false,
        'values': <String, Object?>{},
      },
    );
    expect((unchanged['sidecars'] as Map)['changed'], 0);
    expect((unchanged['subtitles'] as Map)['changed'], 0);
  });

  test('prepare runs the complete index loop in the worker', () async {
    final first = await worker.prepare(
        owner: 'owner',
        peers: const {},
        peerRevision: 0,
        online: const {},
        onlineRevision: 0,
        account: null,
        composedStamp: null);
    expect(first.builds, 1);
    expect(first.composed, isTrue);
    expect(first.snapshot!.works.values.single.title, '最初的名字');

    final unchanged = await worker.prepare(
        owner: 'owner',
        peers: const {},
        peerRevision: 0,
        online: const {},
        onlineRevision: 0,
        account: null,
        composedStamp: first.compositionStamp);
    expect(unchanged.builds, 0);
    expect(unchanged.composed, isFalse);
    expect(unchanged.snapshot, isNull);
    expect(unchanged.compositionStamp, first.compositionStamp);

    final peerChanged = await worker.prepare(
        owner: 'owner',
        peers: const {},
        peerRevision: 1,
        online: const {},
        onlineRevision: 0,
        account: null,
        composedStamp: first.compositionStamp);
    expect(peerChanged.builds, 0);
    expect(peerChanged.composed, isTrue);
    expect(peerChanged.snapshot, isNotNull);

    await jobs.database.update(
        'media_entities',
        {
          'attributes': jsonEncode({'title': '改过的名字', 'localOnly': true})
        },
        where: 'id=?',
        whereArgs: ['w']);
    final rebuilt = await worker.prepare(
        owner: 'owner',
        peers: const {},
        peerRevision: 1,
        online: const {},
        onlineRevision: 0,
        account: null,
        composedStamp: peerChanged.compositionStamp);
    expect(rebuilt.builds, 1);
    expect(rebuilt.composed, isTrue);
    expect(rebuilt.snapshot!.works.values.single.title, '改过的名字');
  });
  test('a worker that ends on its own is replaced by the next request',
      () async {
    await worker.build('one');
    final snapshot = await worker.compose({}, {}, null);
    final id = snapshot.aliases['e1']!;
    // The worker serving after compose is killed like a crash would.
    await worker.call('sources', (null, null, <String>[]));
    worker.killWorkerForTest();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // A query must wait for and replace the exited worker instead of silently
    // reading the same tables on the UI isolate.
    final activity = await worker.activityRows((
      '${root.path}/repo',
      '${root.path}/journal.jsonl',
      'owner',
      const {},
      const {}
    )).timeout(const Duration(seconds: 20));
    expect(activity, isNotNull);
    expect(activity!.$4, contains('activity.journal_absent'));
    final update = await worker.call('progress', [
      {'episodeId': id, 'progress': 0.2, 'positionMs': 200, 'durationMs': 1000}
    ]).timeout(const Duration(seconds: 20)) as LibraryProgress;
    expect(
        update.episodes.values.single
            .singleWhere((e) => e.episodeId == id)
            .progress,
        .2);
  });
  test('invalid batch is atomic and closed workers reject new requests',
      () async {
    await worker.build('one');
    final snapshot = await worker.compose({}, {}, null);
    await expectLater(
        worker.call('progress', [
          {'episodeId': snapshot.aliases['e1'], 'progress': 0.3},
          {'episodeId': 'unknown', 'progress': 0.5}
        ]),
        throwsA(isA<Failure>()));
    expect(await jobs.database.query('ui_cache', where: "id='mesh:progress'"),
        isEmpty);
    await worker.close();
    await expectLater(worker.call('build', 'after close'), throwsStateError);
  });
}
