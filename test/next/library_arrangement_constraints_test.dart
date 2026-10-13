import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/library_capability.dart';
import 'package:nipaplay/next/ui_data/library_service.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smb_connect/src/exceptions.dart' show SmbConnectException;
import 'package:nipaplay/next/ui_data/library_index.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/next/mesh/library_codec.dart';
import '../security/memory_vault.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore jobs;
  late TaskEngine engine;
  late UiDataService ui;
  late LibraryDataService library;
  late Harness harness;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('nipa-x48-constraints-');
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(store: jobs, ownerDeviceId: 'fixture', executors: []);
    final media = MediaService(
        store: IdentityStore(jobs.database, 'fixture'),
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path]);
    ui = UiDataService(
        media,
        engine,
        StateCapability([
          StateView(
              name: 'library.files',
              description: 'empty',
              fields: const ObjectSchema({}),
              read: (_, __) async => [])
        ]),
        StateSources(),
        root,
        MemoryVault());
    library = LibraryDataService(ui);
    ui.libraryData = library;
    library.register(ui.state);
    harness = Harness([LibraryCapability(library)]);
    for (final id in ['a', 'b'])
      await jobs.database.insert('media_entities', {
        'id': id,
        'kind': 'work',
        'attributes': jsonEncode({'title': '作品$id'})
      });
  });
  tearDown(() async {
    await ui.close();
    await engine.close();
    await jobs.database.close();
    await root.delete(recursive: true);
  });
  JsonMap category(String id, List<String> works) => {
        'sourceId': 'local',
        'categoryId': id,
        'title': '类别$id',
        'content': {'kind': 'manual', 'workIds': works}
      };
  Future<Outcome> call(String op, List<JsonMap> entries) => harness.invokeJson(
      'ui.library.$op',
      {'entries': entries},
      Invocation(origin: 'harness_cli:chat:x48'));

  test('invalid reference in a batch preserves all arrangements and activity',
      () async {
    expect(
        await call('put', [
          category('first', ['a'])
        ]),
        isA<Completed>());
    final before = await jobs.database
        .query('ui_cache', where: "id LIKE 'library:layout:%'");
    final events = await jobs.database.query('body_changes');
    expect(
        await call('put', [
          category('first', ['b']),
          category('second', ['missing'])
        ]),
        isA<Failed>());
    expect(
        await jobs.database
            .query('ui_cache', where: "id LIKE 'library:layout:%'"),
        before);
    expect(await jobs.database.query('body_changes'), events);
    expect(
        await call('put', [
          {
            'sourceId': 'local',
            'categoryId': 'broken',
            'title': '坏类别',
            'content': {'kind': 'manual', 'filter': {}}
          }
        ]),
        isA<Failed>());
    expect(
        await call('put', [
          category('first', ['b'])
        ]),
        isA<Completed>());
    expect(
        (await jobs.database.query('media_entities', where: "kind='work'"))
            .length,
        2);
  });

  test(
      'source reconfiguration cannot reuse old server work, folder or episode ids',
      () async {
    final port = _MutableSource();
    library.port = port;
    final workId = sourceEntityId('work', 'jellyfin:test', 'same-item',
        serverId: 'first-server');
    final work = await ui.work(workId);
    expect(work!.title, '测试作品');
    final episode = (await ui.episodes(workId)).single.episodeId;
    final readsBeforeReconfiguration = port.itemReads;
    port.serverId = 'second-server';
    final conflict =
        isA<Failure>().having((f) => f.code, 'code', FailureCode.conflict);
    await expectLater(ui.work(workId), throwsA(conflict));
    await expectLater(
        library.validatedSourceRef(episode, 'episode'), throwsA(conflict));
    await expectLater(
        library.items(sourceEntityId('folder', 'jellyfin:test', 'same-folder',
            serverId: 'first-server')),
        throwsA(conflict));
    expect(port.itemReads, readsBeforeReconfiguration);
  });
  test(
      'source snapshots retain metadata but exclude authenticated transport URLs',
      () async {
    library.port = _MutableSource();
    await ui.work(sourceEntityId('work', 'jellyfin:test', 'same-item',
        serverId: 'first-server'));
    final saved = jsonEncode(await jobs.database.query('ui_cache'));
    expect(saved, isNot(contains('x48-transport-marker')));
    expect(saved, contains('credentialRef'));
  });

  test(
      'user operations keep ordered contents, original switch and caller attribution',
      () async {
    await call('put', [
      category('first', ['a', 'b']),
      category('second', ['b'])
    ]);
    await library.setForm('local', UiLibraryForm.cards);
    await library.moveCategory('second', 0);
    await library.useOriginal('local', true);
    final recreated = LibraryDataService(ui);
    final original = await recreated.page('local');
    expect(original.arranged, false);
    expect(original.hasArrangement, true);
    await recreated.useOriginal('local', false);
    final arranged = await recreated.page('local');
    expect(arranged.form, UiLibraryForm.cards);
    expect(arranged.categories.map((c) => c.categoryId), ['second', 'first']);
    await recreated.removeCategory('second');
    final rows = await jobs.database.query('body_changes', orderBy: 'sequence');
    expect(rows.first['actor'], 'agent');
    expect(
        rows.skip(1).every((r) => r['actor'] == 'user' && r['origin'] == 'gui'),
        true);
    expect((await recreated.items('first')).total, 2);
    final query = await ui.state.query({'view': 'library.arrangements'});
    expect(((query['rows'] as List).single as Map)['original'], false);
    expect(await jobs.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
      'original ordering, hiding and restoration persist without changing source contents',
      () async {
    final port = _CatalogueSource(root.path);
    library.port = port;
    final original = await library.page(port.sourceId);
    final ids = original.categories.map((c) => c.categoryId).toList();
    await library.moveCategory(ids[2], 0);
    await library.removeCategory(ids[0]);
    final recreated = LibraryDataService(ui, port: port);
    var page = await recreated.page(port.sourceId);
    expect(page.arranged, false);
    expect(page.categories.map((c) => c.categoryId), [ids[2], ids[1]]);
    expect(page.hiddenCategories.single.categoryId, ids[0]);
    expect(page.hiddenCategories.single.title, '库A');
    final state = await ui.state.query({'view': 'library.arrangements'});
    final layout = (state['rows'] as List)
        .firstWhere((r) => (r as Map)['sourceId'] == port.sourceId) as Map;
    expect(layout['hiddenOriginal'], [ids[0]]);
    final originalRows =
        await jobs.database.query('body_changes', orderBy: 'sequence');
    expect(
        jsonDecode(originalRows.last['facts'] as String)['title'], '已隐藏原始类别');
    expect(originalRows.last['actor'], 'user');
    expect(
        await call('restore', [
          {'categoryId': ids[0]}
        ]),
        isA<Completed>());
    page = await recreated.page(port.sourceId);
    expect(page.categories.map((c) => c.categoryId), [ids[2], ids[0], ids[1]]);
    expect(page.hiddenCategories, isEmpty);
    expect(port.rootNames, ['A', 'B', 'C']);
    expect((await jobs.database.query('body_changes')).last['actor'], 'agent');
    await call('put', [
      {
        ...category('arranged', ['a']),
        'sourceId': port.sourceId
      }
    ]);
    await library.useOriginal(port.sourceId, true);
    expect(
        (await library.page(port.sourceId)).categories.map((c) => c.categoryId),
        [ids[2], ids[0], ids[1]]);
    await library.useOriginal(port.sourceId, false);
    await library.removeCategory('arranged');
    final removal = jsonDecode(
        (await jobs.database.query('body_changes')).last['facts'] as String);
    expect(removal['title'], '已移除整理类别');
  });

  test(
      'invalid original batch changes neither layout nor activity; local original can be restored',
      () async {
    final id = (await library.page('local')).categories.single.categoryId;
    final layouts = await jobs.database
        .query('ui_cache', where: "id LIKE 'library:layout:%'");
    final events = await jobs.database.query('body_changes');
    expect(
        await call('remove', [
          {'categoryId': id},
          {'categoryId': 'missing'}
        ]),
        isA<Failed>());
    expect(
        await jobs.database
            .query('ui_cache', where: "id LIKE 'library:layout:%'"),
        layouts);
    expect(await jobs.database.query('body_changes'), events);
    await library.removeCategory(id);
    expect((await library.page('local')).categories, isEmpty);
    expect(
        (await library.page('local')).hiddenCategories.single.categoryId, id);
    expect(
        await call('restore', [
          {'categoryId': id}
        ]),
        isA<Completed>());
    expect((await library.page('local')).categories.single.categoryId, id);
  });

  for (final type in ['jellyfin', 'emby', 'smb', 'webdav']) {
    test(
        '$type last successful pages and covers survive disconnect and service recreation',
        () async {
      final port = _CatalogueSource(root.path, type: type);
      library.port = port;
      final online = await library.page(port.sourceId);
      final id = online.categories.first.categoryId;
      final last = await library.items(id, offset: 8, limit: 2);
      expect(last.total, 12);
      final poster = online.categories.first.posters.first;
      expect(await File(poster).exists(), true);
      expect(
          (online.categories.first.preview.first as UiWorkItem)
              .work
              .next!
              .playable,
          true);
      port.online = false;
      final recreated = LibraryDataService(ui, port: port);
      ui.libraryData = recreated;
      final offline = await recreated.page(port.sourceId);
      expect(offline.categories.map((c) => c.title),
          online.categories.map((c) => c.title));
      expect(offline.categories.first.posters, online.categories.first.posters);
      final slice = await recreated.items(id, offset: 7, limit: 3);
      expect(slice.total, 12);
      expect(slice.items.map((i) => (i as UiWorkItem).work.title),
          ['作品7', '作品8', '作品9']);
      expect(slice.items.every((i) => !(i as UiWorkItem).work.next!.playable),
          true);
      expect((await recreated.sources()).last.online, false);
      await recreated.setForm(port.sourceId, UiLibraryForm.cards);
      expect((await recreated.page(port.sourceId)).categories.first.posters,
          online.categories.first.posters);
      port.online = true;
      final recovered = await recreated.page(port.sourceId);
      expect(
          (await recreated.items(id, limit: 1))
              .items
              .whereType<UiWorkItem>()
              .single
              .work
              .next!
              .playable,
          true);
      expect(recovered.categories.length, online.categories.length);
    });
    test('$type never successfully read offline source has an empty page',
        () async {
      final port = _CatalogueSource(root.path, type: type)..online = false;
      library.port = port;
      final page = await library.page(port.sourceId);
      expect(page.categories, isEmpty);
      final slice = await library.items(sourceEntityId('folder', port.sourceId,
          type == 'smb' || type == 'webdav' ? '/' : 'A',
          serverId: port.actualServer));
      expect(slice.items, isEmpty);
      expect(slice.total, 0);
    });
  }

  test(
      'offline series keeps its next and previously read episodes with playback disabled',
      () async {
    final port = _CatalogueSource(root.path)..series = true;
    library.port = port;
    final online = await library.page(port.sourceId);
    final work = (online.categories.first.preview.first as UiWorkItem).work;
    final episodes = await ui.episodes(work.workId);
    expect(episodes.single.playable, true);
    port.online = false;
    final offline = await library.page(port.sourceId);
    final cached = (offline.categories.first.preview.first as UiWorkItem).work;
    expect(cached.next!.episodeId, work.next!.episodeId);
    expect(cached.next!.playable, false);
    expect((await ui.episodes(work.workId)).single.playable, false);
    expect(cached.artwork.poster, work.artwork.poster);
  });

  test(
      'source caches reject malformed responses and never cross actual server identities',
      () async {
    final port = _CatalogueSource(root.path);
    library.port = port;
    await library.page(port.sourceId);
    port.malformed = true;
    await expectLater(library.page(port.sourceId), throwsFormatException);
    port.malformed = false;
    port.server = 'another-server';
    port.online = false;
    expect((await library.page(port.sourceId)).categories, isEmpty);
  });

  test(
      'SMB transport errors preserve the catalogue without catching programming errors',
      () async {
    final port = _CatalogueSource(root.path, type: 'smb');
    library.port = port;
    final original = await library.page(port.sourceId);
    port.disconnectedError = SmbConnectException('disconnected test SMB');
    port.online = false;
    expect((await library.page(port.sourceId)).categories.single.title,
        original.categories.single.title);
    port.disconnectedError = StateError('programming error');
    await expectLater(library.page(port.sourceId), throwsStateError);
  });

  test(
      'unchanged successful and offline observations do not cause database change notifications',
      () async {
    final port = _CatalogueSource(root.path);
    library.port = port;
    await library.page(port.sourceId);
    final before = await jobs.database.rawQuery('SELECT total_changes() AS n');
    await library.page(port.sourceId);
    expect(await jobs.database.rawQuery('SELECT total_changes() AS n'), before);
    port.online = false;
    await library.page(port.sourceId);
    expect(await jobs.database.rawQuery('SELECT total_changes() AS n'), before);
  });

  test(
      'bound server works in condition and manual categories lose playback when their source disconnects',
      () async {
    final port = _CatalogueSource(root.path);
    library.port = port;
    final file = await ui.media.store
        .ensureRemoteFile('jellyfin://episode', port.sourceId, {
      'sourceId': port.sourceId,
      'serverId': port.actualServer,
      'itemId': 'episode',
      'type': 'jellyfin'
    });
    await jobs.database.insert('media_entities', {
      'id': 'release',
      'kind': 'release',
      'parent_id': 'a',
      'attributes': '{}'
    });
    await jobs.database.insert('media_entities', {
      'id': 'episode',
      'kind': 'episode',
      'parent_id': 'release',
      'attributes': '{"number":"1"}'
    });
    await jobs.database.insert('media_file_episodes', {
      'file_id': file,
      'episode_id': 'episode',
      'relation': 'exact',
      'ordinal': 0
    });
    const work = UiWork(
        workId: 'a',
        title: '已绑定作品',
        next: UiEpisode(
            episodeId: 'episode', workId: 'a', number: 1, playable: true));
    await replaceLibraryIndex(jobs.database, [
      {
        'id': 'a',
        'added': 1,
        'payload': workJson(work),
        'facts': {
          'sourceIds': [port.sourceId],
          'identified': true
        }
      }
    ]);
    expect(
        await call('put', [
          {
            'sourceId': port.sourceId,
            'categoryId': 'bound',
            'title': '条件',
            'content': {'kind': 'condition', 'filter': {}}
          }
        ]),
        isA<Completed>());
    expect(
        (await library.items('bound'))
            .items
            .whereType<UiWorkItem>()
            .single
            .work
            .next!
            .playable,
        true);
    port.online = false;
    final offline = (await library.items('bound'))
        .items
        .whereType<UiWorkItem>()
        .single
        .work;
    expect(offline.title, work.title);
    expect(offline.next!.playable, false);
    expect(
        await call('put', [
          {
            ...category('manual', ['a']),
            'sourceId': port.sourceId
          }
        ]),
        isA<Completed>());
    expect(
        (await library.items('manual'))
            .items
            .whereType<UiWorkItem>()
            .single
            .work
            .next!
            .playable,
        false);
  });
}

final class _CatalogueSource implements LibrarySourcePort {
  _CatalogueSource(this.root, {this.type = 'jellyfin'});
  final String root, type;
  final rootNames = ['A', 'B', 'C'];
  bool online = true, malformed = false, series = false;
  Object disconnectedError = const SocketException('disconnected test source');
  String server = 'test-server';
  String get sourceId => '$type:catalogue';
  String? get actualServer => type == 'smb' || type == 'webdav' ? null : server;
  void requireOnline() {
    if (!online) throw disconnectedError;
  }

  @override
  Future<List<JsonMap>> sources({bool initialize = true}) async => [
        {
          'sourceId': sourceId,
          'name': '测试来源',
          'type': type,
          'connected': online,
          if (actualServer != null) 'serverId': actualServer
        }
      ];
  @override
  Future<List<JsonMap>> roots(String id) async {
    requireOnline();
    if (malformed) throw const FormatException('invalid test response');
    return [
      for (final name in actualServer == null ? ['/'] : rootNames)
        {
          'id': name,
          'name': '库$name',
          if (actualServer != null) 'serverId': actualServer
        }
    ];
  }

  @override
  Future<JsonMap> browse(String id, String parent,
      {int offset = 0,
      int limit = 60,
      String? sort,
      bool recursive = false,
      String? filters}) async {
    requireOnline();
    final total = recursive ? 1 : 12;
    return {
      'entries': [
        for (var i = offset; i < offset + limit && i < total; i++)
          await item(id, recursive ? 'episode' : '$parent-$i')
      ],
      'total': total
    };
  }

  @override
  Future<JsonMap> item(String id, String item) async {
    requireOnline();
    return {
      'id': item,
      'name': item == 'episode' ? '第一集' : '作品${item.split('-').last}',
      'kind': item == 'episode'
          ? 'Episode'
          : series
              ? 'Series'
              : 'Movie',
      'isDirectory': series && item != 'episode',
      'metadata': {
        'ImageTags': {'Primary': 'poster'},
        'IndexNumber': 1
      },
      if (actualServer != null) 'serverId': actualServer
    };
  }

  @override
  Future<String?> image(String id, JsonMap item, String kind) async {
    requireOnline();
    if (kind != 'Primary') return null;
    final file = File('$root/source-poster.png');
    if (!await file.exists()) await file.writeAsBytes([1, 2, 3]);
    return file.path;
  }

  @override
  Future<String?> currentSort(String id, String parent) async =>
      'SortName:Ascending';
}

final class _MutableSource implements LibrarySourcePort {
  String serverId = 'first-server';
  int itemReads = 0;
  @override
  Future<List<JsonMap>> sources({bool initialize = true}) async => [
        {
          'sourceId': 'jellyfin:test',
          'name': '测试来源',
          'type': 'jellyfin',
          'connected': true,
          'serverId': serverId
        }
      ];
  @override
  Future<List<JsonMap>> roots(String sourceId) async => [];
  @override
  Future<JsonMap> browse(String sourceId, String parentId,
          {int offset = 0,
          int limit = 60,
          String? sort,
          bool recursive = false,
          String? filters}) async =>
      {'entries': [], 'total': 0};
  @override
  Future<JsonMap> item(String sourceId, String itemId) async {
    itemReads++;
    return {
      'id': itemId,
      'name': '测试作品',
      'kind': 'Movie',
      'isDirectory': false,
      'metadata': {
        'Path': 'https://example.invalid/video?token=x48-transport-marker'
      },
      'serverId': serverId
    };
  }

  @override
  Future<String?> image(String sourceId, JsonMap item, String kind) async =>
      null;
  @override
  Future<String?> currentSort(String sourceId, String parentId) async => null;
}
