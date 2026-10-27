import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/library_capability.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'download_test_support.dart';
import 'media_test_support.dart';

// The direct database actions as the application composes them: one NextCore,
// its real library index, interface notifications and activity view.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late NextCore core;
  late Harness api;
  late Directory root;
  late CredentialStore previousStore;

  setUp(() async {
    previousStore = CredentialStore.instance;
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('next-db-core-');
    core = NextCore(
        root: root,
        databaseFactory: databaseFactoryFfi,
        downloadBackend: FakeDownloadBackend(root),
        downloadLibrary: FakeDownloadLibrary(),
        isDownloaderEnabled: () async => false,
        loadImportedKeys: () async => {},
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path],
        mediaProviders: [TmdbMetadataProvider(FixtureTransport('tmdb'))],
        mediaDurationProbe: (_) async => 10000);
    await core.ready;
    await core.harnessLocation.setPath('${root.path}/harness');
    core.stateSources.history = () => [];
    core.stateSources.continueWatching = () => [];
    core.stateSources.classicLibrary =
        classicLibraryStateViews(history: () => [], seriesDetail: (_) => null);
    api = Harness(core.capabilities);
  });
  tearDown(() async {
    await core.close();
    CredentialStore.instance = previousStore;
    await root.delete(recursive: true);
  });

  Future<JsonMap> call(String id, JsonMap input,
      {String origin = 'mcp'}) async {
    final outcome = await api.invokeJson(id, input, Invocation(origin: origin));
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    final result = (outcome as Completed).value.toJson();
    expect(api.lookup(id)!.spec.output.validate(result), isEmpty);
    return result;
  }

  test('the application offers the four db actions locally and to Mesh peers',
      () {
    expect({
      for (final s in api.catalog.where((s) => s.id.startsWith('db.')))
        s.id: s.effect
    }, {
      'db.describe': Effect.read,
      'db.query': Effect.read,
      'db.undo': Effect.write,
      'db.write': Effect.write,
    });
    for (final id in ['db.describe', 'db.query', 'db.write', 'db.undo']) {
      expect(meshActionAllowed(id), true, reason: id);
    }
  });

  test('a committed title is what the library, the interface and activity show',
      () async {
    // A work made on this device alone, so nothing is fetched from anywhere.
    final database = core.media.service.store.database;
    const workId = 'w1';
    await database.insert('media_entities', {
      'id': workId, 'kind': 'work', 'revision': 0,
      'attributes': '{"title":"原来的标题","localOnly":true}'
    });
    await database.insert('media_entities', {
      'id': 'r1', 'kind': 'release', 'parent_id': workId, 'revision': 0,
      'attributes': '{"title":"第一季"}'
    });
    await database.insert('media_entities', {
      'id': 'e1', 'kind': 'episode', 'parent_id': 'r1', 'revision': 0,
      'attributes': '{"title":"第一集","number":"1"}'
    });
    expect((await core.uiData.work(workId))!.title, '原来的标题');
    final changed =
        core.uiData.changes.first.timeout(const Duration(seconds: 2));
    expect((await core.uiData.meshLibrary!.library()).single.title, '原来的标题');

    final p = await call('db.write', {
      'statements': [
        {
          'sql':
              'INSERT INTO media_overrides(entity_id,field,value,invocation_id,mode,actor,origin,changed_at) VALUES(?,?,?,?,?,?,?,?)',
          'params': [
            workId, 'title', '"直接改的标题"', 'inv', 'persistent', 'agent', 'mcp',
            '2026-10-21T00:00:00Z'
          ]
        }
      ],
      'reason': '用户要求改名'
    });
    expect(
        (await core.uiData.work(workId))!.title, isNot('直接改的标题'),
        reason: 'a preview changes nothing');
    final done = await call('db.write', {'previewId': p['previewId']});
    await changed;

    expect((await core.uiData.work(workId))!.title, '直接改的标题');
    final library = await core.uiData.meshLibrary!.library();
    expect(library.where((w) => w.workId == workId).single.title, '直接改的标题');
    expect(done['refreshed'], containsAll(['mesh_library_index', 'ui_data']));
    expect(await core.media.service.store.database.query('media_projection_outbox'),
        isEmpty);

    final rows = (await call('state.query', {
      'view': 'activity',
      'filter': {'type': {'eq': 'db.write'}}
    }))['rows'] as List;
    final row = rows.single as Map;
    expect(row['actor'], 'agent');
    expect(row['origin'], 'mcp');
    expect(row['subjectId'], done['commitId']);
    expect(row['entityIds'], contains(workId));
    expect(row['title'], contains('1'));
    expect(row['facts']['reason'], '用户要求改名');
    expect(row['facts']['counts'],
        {'media_overrides': {'insert': 1, 'update': 0, 'delete': 0}});

    await call('db.undo', {'commitId': done['commitId']});
    expect((await core.uiData.work(workId))!.title, isNot('直接改的标题'));
    final types = ((await call('state.query', {
      'view': 'activity',
      'filter': {'type': {'in': ['db.write', 'db.undo']}}
    }))['rows'] as List)
        .map((r) => r['type']);
    expect(types, unorderedEquals(['db.write', 'db.undo']));
  });

  test('work merge reaches the real UI and Mesh projection; old IDs and resume observations survive', () async {
    final db=core.media.service.store.database;
    final file=await File('${root.path}/episode.mkv').writeAsString('temporary video');
    final fileId=await core.media.service.index(file.path);
    for(final prefix in ['source','target']) {
      for(final kind in ['work','release','episode']) {
        await db.insert('media_entities',{'id':'$prefix-$kind','kind':kind,'revision':0,
          if(kind!='work') 'parent_id':'$prefix-${kind=='episode'?'release':'work'}',
          'attributes':jsonEncode({'title':kind,'localOnly':true,'number':'1','type':'regular','order':'local'})});
      }
      await db.insert('media_file_episodes',{'file_id':fileId,'episode_id':'$prefix-episode',
        'relation':'local_catalog','ordinal':0,'start_ms':0,'end_ms':10000});
    }
    final mesh=core.uiData.meshLibrary!;
    final before=(await mesh.library()).single;
    final oldEpisode=(await mesh.episodes(before.workId)).single;
    await mesh.recordProgress(oldEpisode.episodeId,0.6,positionMs:6000,durationMs:10000);
    final input=<String,Object?>{'sourceWorkId':'source-work','targetWorkId':'target-work',
      'requestId':'core-merge','reason':'same confirmed work', 'mappings':[
        {'sourceId':'source-release','targetId':'target-release'},
        {'sourceId':'source-episode','targetId':'target-episode'}]};
    final p=await call('media.management.merge_work',input);
    expect(p['canCommit'],isTrue,reason:jsonEncode(p));
    final done=await call('media.management.merge_work',{...input,'expectedPlan':p['expectedPlan']});
    mesh.invalidateIndex();
    final works=await mesh.library();
    expect(works,hasLength(1));
    final episodes=await mesh.episodes(works.single.workId);
    expect(episodes,hasLength(1));
    expect(episodes.single.progress,0.6);
    expect(await mesh.canonical(oldEpisode.episodeId),episodes.single.episodeId);
    expect(await mesh.canonical('source-episode'),episodes.single.episodeId);
    expect((await core.uiData.localWork('source-work'))!.workId,'target-work');
    expect(await core.uiData.localEpisodes('source-work'),hasLength(1));
    final undo={'mergeId':done['mergeId'],'requestId':'core-undo','reason':'restore'};
    final up=await call('media.management.undo_merge',undo);
    expect(up['canCommit'],isTrue,reason:jsonEncode(up));
    await call('media.management.undo_merge',{...undo,'expectedPlan':up['expectedPlan']});
    expect(await db.query('media_file_episodes'),hasLength(2));
  });
}
