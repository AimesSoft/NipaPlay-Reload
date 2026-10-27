import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/events/capability.dart';
import 'package:nipaplay/next/events/signals.dart';
import 'package:nipaplay/next/harness_hooks.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/system/storage.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/services/concurrent_video_processor.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Worker implements JobExecutor {
  final entered = <JobContext>[];
  @override
  String get type => 'fixture';
  @override
  Future<void> execute(JobContext context) async {
    entered.add(context);
    await context.stopRequested;
    if ((await context.snapshot()).cancelRequestedAt != null) {
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.acknowledged,
          details: {'filesRetained': true}));
    }
  }

  @override
  Future<void> recover(JobContext context) => execute(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  setUp(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('x55-constraints-');
    db = await openNextDatabase(Directory('${root.path}/next'),
        factory: databaseFactoryFfi);
    StorageService.debugAppStorageDirectoryOverride = root;
  });
  tearDown(() async {
    BodySignals.emit = null;
    StorageService.debugAppStorageDirectoryOverride = null;
    if (db.isOpen) await db.close();
    await root.delete(recursive: true);
  });

  test('capacity queues workers; terminal pause preserves receipt and revision',
      () async {
    final worker = _Worker();
    final engine = TaskEngine(
        store: SqliteJobStore.fromDatabase(db),
        ownerDeviceId: 'fixture',
        executors: [worker]);
    engine.setCapacity(worker.type, 1);
    await engine.start();
    final first = await engine.submit(type: worker.type, title: 'First');
    await engine.submit(type: worker.type, title: 'Second');
    while (worker.entered.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(engine.activeCount(worker.type), 1);
    final context = worker.entered.first;
    await context.succeed(JobReceipt(
        verification: VerificationLevel.verified, details: {'saved': true}));
    final before = await engine.get(first.jobId);
    await expectLater(engine.pause(first.jobId), throwsA(isA<Failure>()));
    expect((await engine.get(first.jobId)).toStorageJson(),
        before.toStorageJson());
    await engine.cancel(first.jobId);
    // Retire the synthetic waiting worker so the engine can release capacity.
    while (worker.entered.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    await engine.cancel(worker.entered.last.job.jobId);
    await engine.close();
  });

  test(
      'event cursors replay committed facts and filtered wait ignores unrelated events',
      () async {
    final events = BodyEvents(db), hooks = HarnessHooks();
    hooks.observeEvent = (name, id, payload) async {
      await db.insert('followup_hook_events',
          {'event': name, 'object_id': id, 'payload': jsonEncode(payload)});
      events.changed();
    };
    await hooks.emit('settings.changed', 'library.sidecarIndexEnabled',
        {'value': false, 'token': 'synthetic-value'});
    final first = await events.wait({'timeoutMs': 0, 'limit': 1});
    expect((first['events'] as List).single['facts']['token'], '[redacted]');
    final waiting = events.wait({
      'afterCursor': first['nextCursor'],
      'events': ['media.assets.changed'],
      'timeoutMs': 1000
    });
    await hooks.emit('settings.changed', 'unrelated', {'value': true});
    await hooks.emit('media.assets.changed', 'file-1', {'kind': 'subtitle'});
    final result = await waiting;
    expect((result['events'] as List).single['entityId'], 'file-1');
    final reopened = BodyEvents(db);
    expect(
        (await reopened.wait(
            {'afterCursor': first['nextCursor'], 'timeoutMs': 0}))['events'],
        hasLength(2));
    await events.committed.close();
    await reopened.committed.close();
  });

  test(
      'rolled-back changes publish no body event; committed data is visible to subscriber',
      () async {
    final seen = <String>[];
    BodySignals.emit = (event, id, facts) async {
      expect((await db.query('body_changes')).length, 1);
      seen.add(id);
    };
    await expectLater(
        BodySignals.transaction(db, (tx) async {
          BodySignals.changed('media.assets.changed', 'rolled-back', {});
          throw const Failure(FailureCode.conflict, 'fixture rollback');
        }),
        throwsA(isA<Failure>()));
    expect(seen, isEmpty);
    await BodySignals.transaction(db, (tx) async {
      await tx.insert('body_changes', {
        'at': 'fixture',
        'type': 'fixture',
        'subject_id': 'saved',
        'actor': 'user',
        'origin': 'fixture',
        'facts': '{}'
      });
      BodySignals.changed('media.assets.changed', 'saved', {});
    });
    expect(seen, ['saved']);
  });

  test(
      'cache plan retains unique files, ignores symlinks, and rejects changed preview targets',
      () async {
    final images = await Directory('${root.path}/compressed_images').create();
    final file =
        await File('${images.path}/recoverable.jpg').writeAsBytes([1, 2]);
    final unique = await File('${root.path}/next/subtitles/unique.srt')
        .create(recursive: true);
    await unique.writeAsString('subtitle');
    await Link('${images.path}/escape.jpg').create(unique.path);
    final hooks = HarnessHooks();
    final storage = SystemStorage(Directory('${root.path}/next'), db, hooks);
    final plan = await storage.plan({
      'kinds': ['images', 'subtitles']
    });
    expect(plan['entries'], hasLength(1));
    expect(plan['retained'], hasLength(1));
    await file.writeAsBytes([1, 2, 3]);
    final result = await storage.prune(plan['planId'] as String);
    expect(result['removedBytes'], 0);
    expect(await unique.exists(), true);
    expect(await file.exists(), true);
    final fresh = await storage.plan({
      'kinds': ['images']
    });
    expect((await storage.prune(fresh['planId'] as String))['removedBytes'], 3);
    expect(await unique.exists(), true);
  });

  test('read-only configured facts cannot create settings changes', () async {
    final registry = SettingsRegistry(db, [
      SettingEntry(
          key: 'danmaku.spoilerAiConfigured',
          title: 'Configured',
          description: 'Boolean only',
          schema: const BooleanSchema(),
          defaultValue: false,
          storageKey: '@runtime:configured',
          reader: 'fixture',
          writer: 'none',
          read: () async => true,
          write: (_) async => fail('must not write'),
          decodeStorage: (v) => v,
          writable: false)
    ]);
    expect((await registry.describe()).single['readOnly'], true);
    await expectLater(
        Future.sync(() => registry.set('danmaku.spoilerAiConfigured', false,
            Invocation(origin: 'fixture'))),
        throwsA(isA<Failure>()));
    expect(await db.query('settings_changes'), isEmpty);
  });

  test(
      'Classic matching optional control stops new requests and drains in-flight work',
      () async {
    var running = 0, maximum = 0, stopped = false, attempts = 0;
    final entered = Completer<void>(), finish = Completer<void>();
    final future =
        ConcurrentVideoProcessor.processVideoPaths(['one', 'two', 'three'],
            maxConcurrency: 1,
            continueProcessing: () async => !stopped,
            getVideoInfo: (_) async {
              attempts++;
              running++;
              maximum = running > maximum ? running : maximum;
              if (!entered.isCompleted) entered.complete();
              await finish.future;
              running--;
              return {'isMatched': false};
            });
    await entered.future;
    stopped = true;
    finish.complete();
    expect(await future, isEmpty,
        reason: 'stopped recognition must not publish its in-flight result');
    expect(attempts, 1);
    expect(maximum, 1);
  });

  test(
      'unwatch drains its pending observation and emits no later threshold event',
      () async {
    const channel = MethodChannel('nipaplay/instance');
    final entered = Completer<void>(),
        release = Completer<Map<String, Object?>>();
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      if (++reads == 1) return {'availableBytes': 100};
      entered.complete();
      return release.future;
    });
    final seen = <JsonMap>[];
    final hooks = HarnessHooks()
      ..observeEvent = (_, __, facts) async {
        seen.add(facts);
      };
    final storage = SystemStorage(Directory('${root.path}/next'), db, hooks);
    try {
      final watch =
          await storage.watch({'thresholdBytes': 50, 'intervalMs': 1000});
      await entered.future;
      final cancelled =
          storage.unwatch((watch['watch'] as Map)['watchId'] as String);
      release.complete({'availableBytes': 1});
      expect(await cancelled, true);
      expect(seen, hasLength(1));
      expect((seen.single['facts'] as Map)['state'], 'above');
    } finally {
      await storage.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }, skip: !Platform.isMacOS);
}
