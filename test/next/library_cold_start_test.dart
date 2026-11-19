import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/mesh/library_codec.dart';
import 'package:nipaplay/next/mesh/library_projection.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui/library/category_grid.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/library_index.dart';
import 'package:nipaplay/next/ui_data/library_service.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../security/memory_vault.dart';
import 'media_test_support.dart';

/// #1125: a cold start showed an empty library until this run had built
/// the index again, though the last run's index was complete.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore jobs;
  late TaskEngine engine;
  late UiDataService ui;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('nipa-library-cold-');
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(store: jobs, ownerDeviceId: 'fixture', executors: []);
    ui = UiDataService(
        MediaService(
            store: IdentityStore(jobs.database, 'fixture'),
            providers: [],
            classic: MemoryClassic(),
            authorizedRoots: () => [root.path]),
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
  });
  tearDown(() async {
    await ui.close();
    await engine.close();
    await jobs.database.close();
    await root.delete(recursive: true);
  });

  Future<String> allLocal(LibraryDataService library) async =>
      (await library.page('local')).categories.single.categoryId;

  test('the index the last run left is read at once, then read again',
      () async {
    await replaceLibraryIndex(jobs.database, [
      for (var i = 0; i < 3; i++)
        {
          'id': 'w$i',
          'added': DateTime.utc(2026).microsecondsSinceEpoch + i,
          'payload': workJson(UiWork(workId: 'w$i', title: '作品 $i')),
          'facts': {
            'sourceIds': ['local'],
            'identified': true
          }
        }
    ]);
    final library = LibraryDataService(ui);
    ui.libraryData = library;
    final again = Completer<void>();
    final listening = library.changes.listen((_) {
      if (!again.isCompleted) again.complete();
    });
    addTearDown(listening.cancel);
    final slice = await library.items(await allLocal(library),
        offset: 0, limit: 10);
    expect(slice.total, 3);
    expect(slice.items, hasLength(3));
    // The build behind it finishes and tells the page to read again.
    await again.future.timeout(const Duration(seconds: 5));
  });

  test('a library never indexed waits for its first build and says nothing',
      () async {
    final library = LibraryDataService(ui);
    ui.libraryData = library;
    var told = 0;
    final listening = library.changes.listen((_) => told++);
    addTearDown(listening.cancel);
    final slice = await library.items(await allLocal(library),
        offset: 0, limit: 10);
    expect(slice.total, 0);
    await pumpEventQueue();
    expect(told, 0);
  });

  test('a missing poster file does not abort LibraryProjection.build (#1125)',
      () async {
    const workId = 'work-lost-poster';
    await jobs.database.insert('media_entities', {
      'id': workId,
      'kind': 'work',
      'revision': 0,
      'attributes': jsonEncode({
        'title': 'Lost Poster Work',
        'localOnly': true,
      }),
    });
    await jobs.database.insert('media_overrides', {
      'entity_id': workId,
      'field': 'artwork',
      'value': jsonEncode({'poster': '${root.path}/gone-poster.jpg'}),
      'invocation_id': 'test-poster',
    });
    final projection = LibraryProjection(ui, 'fixture');
    await projection.build('v1');
    final snapshot = await projection.compose({}, {}, null);
    expect(snapshot.works.values, hasLength(1));
    final built = snapshot.works.values.single;
    expect(built.title, 'Lost Poster Work');
    expect(built.artwork.poster, isNull);
    final indexed = await jobs.database.query('next_library_index');
    expect(indexed, hasLength(1));
  });

  testWidgets('CategoryItems recovers with backoff after a read failure (#1125)',
      (tester) async {
    final data = _FlakyLibraryData();
    final items = CategoryItems(data, 'all');
    addTearDown(items.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: CustomScrollView(
          slivers: [
            CategoryGrid(
              items: items,
              on: LibraryCallbacks(
                openWork: (_) {},
                play: (_) {},
                openFolder: (_) {},
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(data.calls, 1);
    expect(find.text('Recovered Work'), findsNothing);

    // First retry fires after 2 seconds (1 << 1).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(data.calls, 2);
    expect(find.text('Recovered Work'), findsOneWidget);
  });
}

final class _FlakyLibraryData implements NextLibraryData {
  int calls = 0;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<List<UiLibrarySource>> sources() async => const [
        UiLibrarySource(
            sourceId: 'local',
            name: '本地',
            kind: UiSourceKind.local,
            online: true),
      ];

  @override
  Future<UiLibraryPage> page(String sourceId) async => const UiLibraryPage(
        form: UiLibraryForm.shelves,
        categories: [
          UiCategory(
            categoryId: 'all',
            title: '全部',
            count: 1,
          ),
        ],
      );

  @override
  Future<UiSlice> items(String categoryId,
      {int offset = 0, int limit = 60, String? sort}) async {
    calls++;
    if (calls == 1) throw StateError('transient read failure');
    return const UiSlice(
      [UiWorkItem(UiWork(workId: 'w1', title: 'Recovered Work'))],
      total: 1,
    );
  }
}
