import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/chat/session_store.dart';
import 'package:nipaplay/next/chat/helpers.dart';
import 'package:nipaplay/next/harness_location.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late Followups followups;
  late HarnessLocation location;
  late FakeExecutor executor;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-followups-');
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    location = HarnessLocation();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor();
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [executor]);
    await engine.start();
    followups = Followups(store.database, engine, location);
  });
  tearDown(() async {
    await followups.close();
    await engine.close();
    location.dispose();
    await root.delete(recursive: true);
  });

  test(
      'reopening preserves condition, origin and receipt; trigger occurs once without a host',
      () async {
    final job = await engine
        .submit(type: 'test', title: 'Receipt constraint', input: {});
    final context = await executor.entered.future;
    final registration = await followups.register({
      'when': {'jobId': job.jobId},
      'instruction': 'Inspect the real receipt',
    }, Invocation(origin: 'harness_cli', id: 'register-constraint'));
    await followups.close();
    await context.succeed(verified(details: {'indexed': 3}));
    final original = (await engine.get(job.jobId)).receipt!.toJson();
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [FakeExecutor()]);
    await engine.start();
    followups = Followups(store.database, engine, location);
    await followups.sweep();
    await followups.sweep();
    final row = (await followups.list()).single;
    expect(row['id'], registration['id']);
    expect(row['origin'], 'harness_cli');
    expect(row['invocationId'], 'register-constraint');
    expect(row['state'], 'ready');
    expect(row['reason'], contains('not running'));
    expect((row['trigger'] as Map)['state'], 'succeeded');
    expect(((row['trigger'] as Map)['receipt'] as Map)['verification'],
        'verified');
    expect((await engine.get(job.jobId)).receipt!.toJson(), original);
    final events = await store.database.query('followup_events',
        where: 'type=?', whereArgs: ['followup.triggered']);
    expect(events, hasLength(1));
    expect(await store.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('cancel is durable, idempotent and preserves registration history',
      () async {
    final row = await followups.register({
      'when': {'event': 'library.file_added', 'objectId': '/fixture/video.mp4'},
      'instruction': 'Inspect this file',
    }, Invocation(origin: 'harness_cli'));
    final origin = Invocation(origin: 'gui', id: 'cancel-constraint');
    await followups.cancel(row['id'] as String, origin);
    await followups.cancel(row['id'] as String, origin);
    await followups.hookEvent('library.file_added', '/fixture/video.mp4',
        {'event': 'library.file_added'});
    await followups.sweep();
    expect((await followups.list()).single['state'], 'cancelled');
    final events =
        await store.database.query('followup_events', orderBy: 'sequence');
    expect(events.map((e) => e['type']),
        ['followup.registered', 'followup.cancelled']);
    expect(events.last['origin'], 'gui');
    expect(events.last['invocation_id'], 'cancel-constraint');
  });

  test('helper recovery preserves one return and cancellation without a host',
      () async {
    await followups.close();
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final helpers = Helpers();
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [helpers]);
    followups = Followups(store.database, engine, location);
    helpers.engine = engine;
    helpers.followups = followups;
    followups.helpers = helpers;
    await engine.start();
    final job =
        await engine.submit(type: 'agent.helper', title: '补齐弹幕', input: {
      'parentThreadId': 'original-thread',
      'repository': root.path,
      'instruction': '保留已有的轨道',
    });
    while ((await engine.get(job.jobId)).state != JobState.waitingRetry) {
      await engine.wait(job.jobId, timeout: const Duration(seconds: 1));
    }
    expect((await followups.list()).single['threadId'], 'original-thread');
    await engine.cancel(job.jobId);
    while (!(await engine.get(job.jobId)).state.isTerminal) {
      await engine.wait(job.jobId, timeout: const Duration(seconds: 1));
    }
    await followups.sweep();
    final rows = await followups.list();
    expect(rows, hasLength(1));
    expect(rows.single['state'], 'ready');
    expect((rows.single['trigger'] as Map)['state'], 'cancelled');
    expect(
        ((rows.single['trigger'] as Map)['receipt'] as Map)['details']
            ['summary'],
        '帮手任务已停止');
  });

  for (final state in [JobState.failed, JobState.cancelled]) {
    test(
        '${state.wireName} trigger preserves its unverified receipt and outcome',
        () async {
      final job = await engine
          .submit(type: 'test', title: 'Unsuccessful task', input: {});
      final context = await executor.entered.future;
      await followups.register({
        'when': {'jobId': job.jobId},
        'instruction': 'Inspect the outcome'
      }, Invocation(origin: 'harness_cli'));
      final receipt = JobReceipt(
          verification: VerificationLevel.unverified,
          details: {'reason': state.wireName});
      if (state == JobState.failed) {
        await context.fail(
            const Failure(FailureCode.unavailable, 'Fixture failure'), receipt);
      } else {
        await engine.cancel(job.jobId);
        await context.cancelled(receipt);
      }
      await followups.sweep();
      final trigger = (await followups.list()).single['trigger'] as Map;
      expect(trigger['state'], state.wireName);
      expect((trigger['receipt'] as Map)['verification'], 'unverified');
      expect(((trigger['receipt'] as Map)['details'] as Map)['reason'],
          state.wireName);
      expect(trigger['errorCode'],
          state == JobState.failed ? 'unavailable' : null);
      expect(
          await store.database.query('followup_events',
              where: 'type=?', whereArgs: ['followup.triggered']),
          hasLength(1));
    });
  }

  test('invalid or unknown conditions leave no durable registration', () async {
    for (final condition in [
      <String, Object?>{},
      {'jobId': 'missing'},
      {'jobId': 'missing', 'event': 'playback.started'},
      {'jobId': 'missing', 'objectId': 'file'},
    ]) {
      await expectLater(
          followups.register({'when': condition, 'instruction': 'test'},
              Invocation(origin: 'harness_cli')),
          throwsA(isA<Failure>()));
    }
    expect(await followups.list(), isEmpty);
    expect(await store.database.query('followup_events'), isEmpty);
  });

  test('native wait consumption is durable and never rewrites the receipt', () async {
    final job = await engine.submit(type: 'test', title: '原生帮手');
    final context = await executor.entered.future;
    final row = await followups.register({
      'when': {'jobId': job.jobId}, 'threadId': 'parent', 'instruction': '交回结果'
    }, Invocation(origin: 'codex_native:child'));
    await context.succeed(verified(details: {'summary': '每集完整表格'}));
    await followups.sweep();
    final receipt = (await engine.get(job.jobId)).receipt!.toJson();
    final taken = <String, Object?>{'threadId': 'parent', 'turnId': 'wait-turn',
      'itemId': 'wait-item', 'helperTurnId': 'child-turn'};
    await followups.consumeHelperResult(job.jobId, taken);
    await followups.consumeHelperResult(job.jobId, taken);
    await followups.close();
    followups = Followups(store.database, engine, location);
    await followups.sweep();
    final saved = (await followups.list()).single;
    expect(saved['id'], row['id']);
    expect(saved['state'], 'cancelled');
    expect(saved['consumedBy'], taken);
    expect((await engine.get(job.jobId)).receipt!.toJson(), receipt);
    expect(await store.database.query('followup_events',
        where: 'type=?', whereArgs: ['followup.consumed']), hasLength(1));
  });

  test('main identifiers survive selections, reopen, and harness changes',
      () async {
    var sessions = SessionStore(store.database);
    await sessions.select(root.path, 'main-thread');
    await sessions.select(root.path, 'another-thread');
    await sessions.select('${root.path}/other', 'other-main');
    await followups.close();
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [FakeExecutor()]);
    await engine.start();
    followups = Followups(store.database, engine, location);
    sessions = SessionStore(store.database);
    expect(await sessions.main(root.path), 'main-thread');
    expect(await sessions.main('${root.path}/other'), 'other-main');
    expect(
        (await store.database.query('harness_sessions',
                where: 'repository=?', whereArgs: [root.path]))
            .single['current_thread'],
        'another-thread');
  });

  test(
      'wake retains facts while unavailable and discovery retains caller provenance',
      () async {
    final invocation =
        Invocation(origin: 'hook:fixture-job', id: 'wake-constraint');
    final wake = await followups.wake({
      'instruction': 'Inspect the change',
      'facts': {'version': '2', 'cookie': 'private-cookie'}
    }, invocation);
    await followups.sweep();
    await followups.sweep();
    final row = (await followups.list()).single;
    expect(row['id'], wake['id']);
    expect(row['state'], 'ready');
    expect(row['threadId'], isNull);
    expect(row['origin'], invocation.origin);
    expect(((row['trigger'] as Map)['facts'] as Map)['version'], '2');
    expect(((row['trigger'] as Map)['facts'] as Map)['cookie'], '[redacted]');
    await followups.discover({
      'title': 'A version appeared',
      'source': 'fixture',
      'facts': {'version': '2', 'cookie': 'private-cookie'}
    }, invocation);
    final discovery =
        (await store.database.query('harness_discoveries')).single;
    expect(discovery['origin'], invocation.origin);
    expect(discovery['invocation_id'], invocation.id);
    expect(discovery['facts'], isNot(contains('private-cookie')));
    expect(await store.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
