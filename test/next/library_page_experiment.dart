// Run explicitly; this records functional observations rather than a regression suite.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/mesh/library_codec.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/library_index.dart';
import 'package:nipaplay/next/ui_data/library_service.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../security/memory_vault.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('X48 paged local conditions and source identity isolation observations',
      () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('nipa-x48-pages-');
    final jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final engine =
        TaskEngine(store: jobs, ownerDeviceId: 'fixture', executors: []);
    final media = MediaService(
        store: IdentityStore(jobs.database, 'fixture'),
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path]);
    final ui = UiDataService(media, engine, StateCapability([]), StateSources(),
        root, MemoryVault());
    final port = _Sources();
    final library = LibraryDataService(ui, port: port);
    ui.libraryData = library;
    addTearDown(() async {
      await ui.close();
      await engine.close();
      await jobs.database.close();
      await root.delete(recursive: true);
    });
    final records = [
      for (var i = 0; i < 5000; i++)
        {
          'id': 'w$i',
          'added': DateTime.utc(2026).microsecondsSinceEpoch + i,
          'payload': workJson(UiWork(
              workId: 'w$i', title: '作品 $i', year: 2026, genres: ['奇幻'])),
          'facts': {
            'sourceIds': [i.isEven ? 'local' : 'jellyfin:test'],
            'deviceIds': [i % 3 == 0 ? 'mesh-device' : 'this-device'],
            'identified': i != 4999,
            'types': ['anime'],
            'watch': i % 4 == 0 ? 'watched' : 'unwatched',
            'year': 2026,
            'genres': ['奇幻'],
            'rating': 8.5
          }
        }
    ];
    await replaceLibraryIndex(jobs.database, records);
    await library.mutate(
        'put',
        [
          {
            'sourceId': 'local',
            'categoryId': 'fantasy',
            'title': '奇幻',
            'content': {
              'kind': 'condition',
              'filter': {
                'sourceIds': ['local', 'jellyfin:test'],
                'types': ['anime'],
                'watch': 'unwatched',
                'genres': ['奇幻'],
                'yearMin': 2025,
                'ratingMin': 8,
                'addedAfter': '2025-01-01T00:00:00Z'
              }
            }
          }
        ],
        Invocation(origin: 'harness_cli:x48'));
    final clock = Stopwatch()..start();
    final first = await library.items('fantasy', limit: 60);
    final second = await library.items('fantasy', offset: 60, limit: 60);
    print(jsonEncode({
      'observation': 'paged condition',
      'cachedWorks': 5000,
      'total': first.total,
      'pageSizes': [first.items.length, second.items.length],
      'milliseconds': clock.elapsedMilliseconds,
      'firstWork': (first.items.first as UiWorkItem).work.workId
    }));
    expect(first.total, 3749);
    expect(first.items.length, 60);
    expect(second.items.length, 60);
    final extra = {
      'id': 'new',
      'added': DateTime.utc(2027).microsecondsSinceEpoch,
      'payload':
          workJson(const UiWork(workId: 'new', title: '新作品', year: 2026)),
      'facts': records[1]['facts']
    };
    await replaceLibraryIndex(jobs.database, [...records, extra]);
    final updated = await library.items('fantasy', limit: 1);
    print(jsonEncode({
      'observation': 'new matching work enters without Nipa',
      'total': updated.total,
      'workId': (updated.items.single as UiWorkItem).work.workId
    }));
    expect(updated.total, 3750);
    final original = await library.page('jellyfin:test');
    final slice = await library.items(original.categories.single.categoryId,
        offset: 120, limit: 10);
    final work = (slice.items.first as UiWorkItem).work;
    final eps = await ui.episodes(work.workId);
    print(jsonEncode({
      'observation': 'unbound source work opens',
      'workId': work.workId,
      'episodeId': eps.first.episodeId,
      'number': eps.first.number,
      'total': slice.total,
      'requestedPages': port.requests
    }));
    expect(work.title, '未绑定剧集');
    expect(eps.first.playable, true);
    expect(sourceEntityRef(eps.first.episodeId, 'episode'),
        ['jellyfin:test', 'episode']);
    expect(
        sourceEntityId('work', 'jellyfin:other', 'series'), isNot(work.workId));
  });
}

final class _Sources implements LibrarySourcePort {
  final requests = <JsonMap>[];
  @override
  Future<String?> currentSort(String sourceId, String parentId) async => null;
  @override
  Future<List<JsonMap>> sources({bool initialize = true}) async => [
        {
          'sourceId': 'jellyfin:test',
          'name': '测试服务器',
          'type': 'jellyfin',
          'connected': true
        }
      ];
  @override
  Future<List<JsonMap>> roots(String id) async => [
        {'id': 'root', 'name': '动画'}
      ];
  @override
  Future<JsonMap> browse(String id, String parent,
      {int offset = 0,
      int limit = 60,
      String? sort,
      bool recursive = false,
      String? filters}) async {
    requests.add({'offset': offset, 'limit': limit, 'recursive': recursive});
    return {
      'entries': [await item(id, recursive ? 'episode' : 'series')],
      'total': recursive ? 1 : 500
    };
  }

  @override
  Future<JsonMap> item(String id, String item) async => {
        'id': item,
        'name': item == 'series' ? '未绑定剧集' : '第一集',
        'kind': item == 'series' ? 'Series' : 'Episode',
        'isDirectory': item == 'series',
        'metadata': {
          'IndexNumber': 1,
          'ParentIndexNumber': 1,
          'SeriesId': 'series',
          'RunTimeTicks': 20000000
        }
      };
  @override
  Future<String?> image(String source, JsonMap item, String kind) async => null;
}
