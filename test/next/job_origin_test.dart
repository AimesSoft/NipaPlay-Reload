import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/state/change_history.dart';
import 'package:nipaplay/next/tasks/job_origin.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';

void main() {
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late JobOrigins origins;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-origins-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    origins = JobOrigins();
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'device-test',
        originOf: origins.of,
        executors: [
          FakeExecutor(),
          FakeExecutor(type: 'harness.hook'),
        ]);
    origins.lookup = engine.get;
    await engine.start();
  });
  tearDown(() async {
    await engine.close();
    await root.delete(recursive: true);
  });

  Future<Job> submitAs(String? origin,
      {String type = 'test', Map<String, Object?> details = const {}, JsonMap input = const {}}) {
    Future<Job> run() => engine.submit(
        type: type, title: 'T $origin', details: details, input: input);
    return origin == null
        ? run()
        : runZoned(run, zoneValues: {
            BodyChanges.invocationKey: Invocation(origin: origin)
          });
  }

  test('origin follows the invocation that submitted, and survives storage',
      () async {
    origins.threadFor = (origin) =>
        origin == 'harness_cli:chat:s1' ? 'thread-main' : null;
    expect((await submitAs('gui')).origin, {'kind': 'user'});
    final chat = await submitAs('harness_cli:chat:s1');
    expect(chat.origin,
        {'kind': 'conversation', 'sessionId': 's1', 'threadId': 'thread-main'});
    expect((await submitAs('harness_cli:helper:j9')).origin,
        {'kind': 'subagent', 'helperJobId': 'j9'});
    expect((await submitAs('codex_native:t7')).origin,
        {'kind': 'subagent', 'threadId': 't7'});
    expect((await submitAs('mesh:dev-2')).origin,
        {'kind': 'device', 'deviceId': 'dev-2'});
    expect((await submitAs(null)).origin, {'kind': 'host'});
    expect((await submitAs('application')).origin,
        {'kind': 'host', 'source': 'application'});

    final stored = await store.get(chat.jobId);
    expect(stored!.origin, chat.origin);
    expect(stored.toJson()['origin'], chat.origin);
    final events = await store.events(chat.jobId);
    expect(events.first.snapshot['origin'], chat.origin);

    final harness = Harness([TaskCapability(engine)]);
    for (final action in ['get', 'list']) {
      final outcome = await harness.invokeJson(
          'task.$action',
          action == 'list' ? {} : {'jobId': chat.jobId},
          Invocation(origin: 'test')) as Completed<JsonEncodable>;
      final result = outcome.value.toJson();
      final snapshot = action == 'list'
          ? (result['jobs'] as List)
              .cast<JsonMap>()
              .singleWhere((j) => j['jobId'] == chat.jobId)
          : result['job'] as JsonMap;
      expect(snapshot['origin'], chat.origin);
      expect(harness.lookup('task.$action')!.spec.output.validate(result),
          isEmpty);
    }
  });

  test('calls from a hook or schedule program say which run they belong to',
      () async {
    final hook = await submitAs(null,
        type: 'harness.hook',
        details: {'event': 'download.completed', 'objectId': 'x'});
    expect(hook.origin, {
      'kind': 'host',
      'trigger': 'hook',
      'event': 'download.completed'
    });
    final schedule = await submitAs(null,
        type: 'harness.hook',
        details: {'event': 'schedule', 'objectId': 'nightly'},
        input: {'scheduleId': 'nightly'});
    expect(schedule.origin!['scheduleId'], 'nightly');

    final fromHook = await submitAs('hook:${hook.jobId}');
    expect(fromHook.origin, {
      'kind': 'script',
      'hookJobId': hook.jobId,
      'event': 'download.completed'
    });
    final fromSchedule = await submitAs('hook:${schedule.jobId}');
    expect(fromSchedule.origin!['kind'], 'script');
    expect(fromSchedule.origin!['scheduleId'], 'nightly');
    final gone = await submitAs('hook:job-missing');
    expect(gone.origin, {'kind': 'script', 'hookJobId': 'job-missing'});
  });

  test('tasks stored before origins existed show no origin', () async {
    final job = await submitAs('gui');
    final legacy = Map<String, Object?>.from(job.toStorageJson())
      ..remove('origin');
    final old = Job.fromJson(legacy);
    expect(old.origin, isNull);
    expect(old.toJson().containsKey('origin'), isFalse);
    expect(old.toStorageJson().containsKey('origin'), isFalse);
  });
}
