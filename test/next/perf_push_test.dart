import 'dart:async';
import 'dart:io';
import 'dart:isolate';

// fake_async is supplied by flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/db/notifications.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/mesh/catalogue_updates.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/system/foreground.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/service.dart';
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/mixin/import_mixin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'media_test_support.dart';

Future<void> writeCatalogueInWorker(String path, SendPort send) =>
    Isolate.run(() async {
      sqfliteFfiInit();
      // Match LibraryWorker: an independent connection must not reuse the
      // native hot-restart single-instance handle owned by the parent.
      final notifications = NotifyingDatabaseFactory(
          databaseFactoryFfiNoIsolate, () => send.send(null));
      final db = await notifications.factory.openDatabase('$path/next.db',
          options: OpenDatabaseOptions(singleInstance: false));
      await notifications.observe(db);
      await db.insert('media_entities',
          {'id': 'worker-work', 'kind': 'work', 'attributes': '{}'});
      await Future<void>.delayed(Duration.zero);
      await db.close();
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('committed catalogue pushes', () {
    late Directory root;
    late SqliteJobStore jobs;
    late TaskEngine engine;
    late UiDataService service;
    late int queries;
    late StreamSubscription<void> subscription;
    late int notifications;
    setUp(() async {
      sqfliteFfiInit();
      NextForeground.setActive(true);
      queries = 0;
      notifications = 0;
      root = await Directory.systemTemp.createTemp('perf-push-');
      final delegate = databaseFactoryFfi as SqfliteInvokeHandler;
      final factory = buildDatabaseFactory(invokeMethod: (method, [args]) {
        if (method == 'query') queries++;
        return delegate.invokeMethod<Object?>(method, args);
      });
      jobs = await SqliteJobStore.open(root, factory: factory);
      engine = TaskEngine(store: jobs, ownerDeviceId: 'perf', executors: []);
      final sources = StateSources();
      service = UiDataService(
          MediaService(
              store: IdentityStore(jobs.database, 'perf'),
              providers: [],
              classic: MemoryClassic(),
              authorizedRoots: () => []),
          engine,
          StateCapability([]),
          sources,
          root,
          MemoryVault());
      subscription = service.changes.listen((_) => notifications++);
    });
    tearDown(() async {
      await subscription.cancel();
      await service.close();
      await engine.close();
      await root.delete(recursive: true);
      NextForeground.setActive(true);
    });

    test('60 idle seconds do no SQL, network work or notifications', () {
      fakeAsync((clock) {
        service.start();
        final baseline = queries;
        var network = 0;
        final updates = CatalogueUpdates((_) async {
          network++;
        });
        updates.start();
        clock.elapse(const Duration(seconds: 60));
        clock.flushMicrotasks();
        expect(queries, baseline);
        expect(network, 0);
        expect(notifications, 0);
        expect(clock.periodicTimerCount, 0);
        updates.close();
        service.pause();
        clock.flushMicrotasks();
      });
    });

    test('IdentityStore commit reaches the UI with one push', () async {
      await service.start();
      final delivered = service.changes.first;
      await service.media.store.ensureFile('${root.path}/episode.mkv');
      await delivered;
      expect(notifications, 1);
    });

    test('multi-row transaction pushes once and rollback never pushes',
        () async {
      await service.start();
      final delivered = service.changes.first;
      await jobs.database.transaction((tx) async {
        for (var n = 0; n < 3; n++) {
          await tx.insert('media_entities',
              {'id': 'work-$n', 'kind': 'work', 'attributes': '{}'});
        }
        expect(notifications, 0, reason: 'uncommitted facts stay private');
      });
      await delivered;
      expect(notifications, 1);
      await expectLater(jobs.database.transaction((tx) async {
        await tx.delete('media_entities');
        throw StateError('rollback');
      }), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
    });

    test('batch mutations push once; mesh-derived output stays silent',
        () async {
      await service.start();
      final delivered = service.changes.first;
      final batch = jobs.database.batch();
      for (var n = 0; n < 3; n++) {
        batch.insert('media_entities',
            {'id': 'batch-$n', 'kind': 'work', 'attributes': '{}'});
      }
      await batch.commit(noResult: true);
      await delivered;
      expect(notifications, 1);
      await jobs.database.insert('ui_cache',
          {'id': 'mesh:peer:test', 'fingerprint': 'x', 'payload': '{}'});
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
    });

    test('background defers delivery; foreground reconciles once', () async {
      await service.start();
      NextForeground.setActive(false);
      await service.media.store.ensureFile('${root.path}/hidden.mkv');
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
      final resumed = service.changes.first;
      NextForeground.setActive(true);
      await resumed;
      expect(notifications, 1);
    });

    test('worker connection forwards a committed change through a port',
        () async {
      await service.start();
      final port = ReceivePort();
      final path = root.path;
      final send = port.sendPort;
      final received = port.first.then((_) {
        CatalogueChanges.committed(jobs.database.path);
      });
      final delivered = service.changes.first;
      await writeCatalogueInWorker(path, send);
      await received;
      await delivered;
      expect(notifications, 1);
      port.close();
    });
  });

  test('push-capable peer is silent for 60s and a notice refreshes once', () {
    fakeAsync((clock) {
      NextForeground.setActive(true);
      final calls = <Set<String>?>[];
      final updates = CatalogueUpdates((peers) async => calls.add(peers));
      updates.start();
      updates.peer('new', push: true);
      clock.elapse(const Duration(seconds: 60));
      expect(calls, isEmpty);
      expect(clock.periodicTimerCount, 0);
      updates.changed(peers: {'new'});
      clock.flushMicrotasks();
      expect(calls, [
        {'new'}
      ]);
      updates.close();
      clock.flushMicrotasks();
    });
  });

  test('old peer refreshes at 60s, stops behind and reconciles on resume', () {
    fakeAsync((clock) {
      NextForeground.setActive(true);
      final calls = <Set<String>?>[];
      final updates = CatalogueUpdates((peers) async => calls.add(peers));
      updates.start();
      updates.peer('old', push: false);
      updates.peer('new', push: true);
      clock.elapse(const Duration(seconds: 59));
      expect(calls, isEmpty);
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(calls, [
        {'old'}
      ]);
      NextForeground.setActive(false);
      clock.elapse(const Duration(minutes: 2));
      expect(calls.length, 1);
      expect(clock.periodicTimerCount, 0);
      NextForeground.setActive(true);
      clock.flushMicrotasks();
      expect(calls, [
        {'old'},
        null
      ]);
      updates.peer('old', push: true);
      expect(clock.periodicTimerCount, 0);
      updates.close();
      clock.flushMicrotasks();
    });
  });

  test('notice during refresh gets another delivery', () {
    fakeAsync((clock) {
      NextForeground.setActive(true);
      final gate = Completer<void>();
      var calls = 0;
      final updates = CatalogueUpdates((_) async {
        calls++;
        if (calls == 1) await gate.future;
      });
      updates.start();
      updates.changed(peers: {'a'});
      updates.changed(peers: {'a'});
      expect(calls, 1);
      gate.complete();
      clock.flushMicrotasks();
      expect(calls, 2);
      updates.close();
      clock.flushMicrotasks();
    });
  });
}
