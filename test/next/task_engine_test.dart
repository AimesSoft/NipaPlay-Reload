import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/tasks/device_identity.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';

void main() {
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late FakeExecutor executor;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-tasks-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor();
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
  });
  tearDown(() async {
    await engine.close();
    await root.delete(recursive: true);
  });

  test('SQLite reopens snapshots, receipts, events and filters in next.db',
      () async {
    await engine.start();
    final job = await engine.submit(
        type: 'test',
        title: 'Persistence',
        input: {'source': 'magnet:?xt=test'});
    final context = await executor.entered.future;
    await context.report(
        phase: 'verifying',
        progress: JobProgress(completed: 4, total: 4, unit: 'bytes'),
        checkpoint: {'externalId': 7});
    await context.succeed(verified(details: {
      'files': [
        {
          'path': '/out/test.mkv',
          'expectedSize': 4,
          'actualSize': 4,
          'imported': false
        }
      ]
    }));
    final expected = await engine.get(job.jobId);
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
    await engine.start();
    expect((await engine.get(job.jobId)).toStorageJson(),
        expected.toStorageJson());
    expect(await File('${root.path}/next.db').exists(), isTrue);
    expect(await engine.list(state: JobState.succeeded, type: 'test'),
        hasLength(1));
    expect(await engine.list(state: JobState.failed), isEmpty);
    expect((await store.events(job.jobId, afterRevision: 1)).map((e) => e.kind),
        ['progress', 'succeeded']);
    expect(executor.executions, 1);
  });

  test('event insertion failure rolls back the updated snapshot', () async {
    final job = await engine.submit(type: 'test', title: 'Atomic');
    final database = await databaseFactoryFfi.openDatabase(
        '${root.path}/next.db',
        options: OpenDatabaseOptions(singleInstance: false));
    await database.execute(
        "CREATE TRIGGER reject_event BEFORE INSERT ON job_events "
        "WHEN NEW.kind = 'reject' BEGIN SELECT RAISE(ABORT, 'event rejected'); END");
    await database.close();
    final next = Job.fromJson(
        {...job.toStorageJson(), 'revision': 1, 'phase': 'must_rollback'});
    await expectLater(
        store.commit(
            next,
            JobEvent(
                jobId: next.jobId,
                revision: 1,
                kind: 'reject',
                at: next.updatedAt,
                snapshot: next.toJson()),
            expectedRevision: 0),
        throwsA(isA<DatabaseException>()));
    expect((await store.get(job.jobId))!.phase, 'queued');
    expect((await store.get(job.jobId))!.revision, 0);
    expect(await store.events(job.jobId), hasLength(1));
  });

  test(
      'CAS rejects duplicate submissions and stale updates without extra events',
      () async {
    final job = await engine.submit(type: 'test', title: 'CAS');
    await expectLater(
        engine.submit(type: 'test', title: 'Duplicate', jobId: job.jobId),
        throwsA(isA<Failure>()));
    final next =
        Job.fromJson({...job.toStorageJson(), 'revision': 1, 'phase': 'first'});
    final event = JobEvent(
        jobId: next.jobId,
        revision: 1,
        kind: 'progress',
        at: next.updatedAt,
        snapshot: next.toJson());
    await store.commit(next, event, expectedRevision: 0);
    await expectLater(store.commit(next, event, expectedRevision: 0),
        throwsA(isA<Failure>()));
    expect((await store.get(job.jobId))!.phase, 'first');
    expect(await store.events(job.jobId), hasLength(2));
  });

  test(
      'running restart records interrupted before executor reconciles actual effect',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Crash');
    final context = await executor.entered.future;
    await context.markSideEffectCommitted(checkpoint: {'nativeId': 'present'});
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor(onRecover: (context) async {
      expect(context.job.state, JobState.interrupted);
      expect(context.job.checkpoint['nativeId'], 'present');
      expect((await store.events(job.jobId)).last.kind, 'interrupted');
      await context.report(phase: 'verifying');
      await context
          .succeed(verified(details: {'externalEffectReadBack': true}));
    });
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
    await engine.start();
    final recovered = await untilState(engine, job.jobId, JobState.succeeded);
    expect(recovered.jobId, job.jobId);
    expect(executor.executions, 0);
    expect(executor.recoveries, 1);
  });

  test('pending decision survives restart and its call resumes via Harness',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Decision');
    final context = await executor.entered.future;
    final running = context.job;
    final call = ActionCall('test.choose', {
      'jobId': job.jobId,
      'revision': running.revision + 1,
      'choice': 'version-b'
    });
    final waiting = await context.needsDecision(
        Decision(prompt: 'Choose version', options: [
          DecisionOption(
              label: 'Version B', detail: 'Verified source', call: call),
        ]),
        checkpoint: {
          'candidates': ['version-a', 'version-b']
        });
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor(onRecover: (context) async {
      expect(context.job.checkpoint, {'choice': 'version-b'});
      await context.running(phase: 'verifying');
      await context.succeed(verified(details: {'choice': 'version-b'}));
    });
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
    await engine.start();
    final persisted = await engine.get(job.jobId);
    expect(persisted.state, JobState.needsDecision);
    expect(persisted.toJson(), waiting.toJson());
    expect(executor.recoveries, 0);
    final harness = Harness([TaskCapability(engine), ChoiceCapability(engine)]);
    final queried = await harness.invokeJson(
            'task.get', {'jobId': job.jobId}, Invocation(origin: 'test'))
        as Completed;
    expect(
        harness
            .lookup('task.get')!
            .spec
            .output
            .validate(queried.value.toJson()),
        isEmpty);
    final option = persisted.decision!.options.single.call;
    final resumed = await harness.invokeJson(
        option.actionId, option.input, Invocation(origin: 'gui'));
    expect(resumed, isA<Completed>());
    await untilState(engine, job.jobId, JobState.succeeded);
    final stale = await harness.invokeJson(
        option.actionId, option.input, Invocation(origin: 'gui')) as Failed;
    expect(stale.failure.code, FailureCode.conflict);
    expect(executor.recoveries, 1);
  });

  test(
      'cancelling restart reconciles and keeps cancellation in terminal receipt',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Cancellation');
    final context = await executor.entered.future;
    await context.report(phase: 'publishing');
    await context.markSideEffectCommitted();
    await engine.cancel(job.jobId);
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor(onRecover: (context) async {
      expect(context.job.state, JobState.interrupted);
      expect(context.job.cancelRequestedAt, isNotNull);
      await context
          .cancelled(verified(details: {'retainedEffect': 'effect-1'}));
    });
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
    await engine.start();
    final completed = await untilState(engine, job.jobId, JobState.cancelled);
    expect(
        (completed.toJson()['receipt'] as JsonMap)['cancellation'],
        allOf(containsPair('phase', 'publishing'),
            containsPair('sideEffectCommitted', true)));
    expect(completed.receipt!.details, {'retainedEffect': 'effect-1'});
    expect(completed.error, isNull);
    expect((await store.events(job.jobId)).last.snapshot, completed.toJson());
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
    await engine.start();
    expect((await engine.get(job.jobId)).toJson(), completed.toJson());
  });

  test('worker start persistence failure produces an honest failed receipt',
      () async {
    final database = await databaseFactoryFfi.openDatabase(
        '${root.path}/next.db',
        options: OpenDatabaseOptions(singleInstance: false));
    await database.execute(
        "CREATE TRIGGER reject_start BEFORE INSERT ON job_events "
        "WHEN NEW.kind = 'running' BEGIN SELECT RAISE(ABORT, 'start rejected'); END");
    await database.close();
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Start failure');
    final failed = await untilState(engine, job.jobId, JobState.failed);
    expect(failed.error!.message, contains('start rejected'));
    expect(failed.receipt!.verification, VerificationLevel.unverified);
    expect(executor.executions, 0);
    expect((await store.events(job.jobId)).map((event) => event.kind),
        ['submitted', 'failed']);
  });

  test('bounded wait over SQLite returns change, timeout and terminal receipt',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'SQLite wait');
    final context = await executor.entered.future;
    final current = await engine.get(job.jobId);
    final waiting = engine.wait(job.jobId, afterRevision: current.revision);
    await context.report(phase: 'verifying');
    final changed = await waiting;
    expect(changed.phase, 'verifying');
    final timedOut = await engine.wait(job.jobId,
        afterRevision: changed.revision,
        timeout: const Duration(milliseconds: 10));
    expect(timedOut.revision, changed.revision);
    final terminal = engine.wait(job.jobId, afterRevision: changed.revision);
    await context.succeed(verified());
    expect((await terminal).receipt!.verification, VerificationLevel.verified);
  });

  test('task actions are listed and invoked through the real MCP endpoint',
      () async {
    final harness = Harness([TaskCapability(engine)]);
    final job = await engine.submit(type: 'test', title: 'MCP');
    final endpoint = AgentEndpoint(
        harness: harness,
        root: root,
        appVersion: 'test',
        agentsMd: '# Test',
        port: 0);
    addTearDown(endpoint.stop);
    final running = await endpoint.start() as AgentEndpointRunning;
    final token =
        (jsonDecode(await File('${root.path}/endpoint.json').readAsString())
            as JsonMap)['token'] as String;
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    Future<JsonMap> rpc(String method, JsonMap params) async {
      final request = await client.postUrl(running.url);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(
          {'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}));
      final response = await request.close();
      expect(response.statusCode, 200);
      return (jsonDecode(await utf8.decoder.bind(response).join())
          as JsonMap)['result'] as JsonMap;
    }

    final catalog = await rpc('tools/list', {});
    expect((catalog['tools'] as List).map((tool) => (tool as JsonMap)['name']),
        ['task_cancel', 'task_get', 'task_list', 'task_wait']);
    final result = await rpc('tools/call', {
      'name': 'task_wait',
      'arguments': {'jobId': job.jobId, 'timeoutMs': 0}
    });
    expect(result['isError'], false);
    expect(result['structuredContent'], {
      'status': 'completed',
      'result': {'job': job.toJson()}
    });
    expect(await File('${running.workspace.path}/.codex/config.toml').exists(),
        isTrue);
  });

  test('installation identity is stable and rejects corrupt persisted data',
      () async {
    final id = await loadDeviceIdentity(root);
    expect(id, matches(RegExp(r'^device-[a-f0-9]{32}$')));
    expect(await loadDeviceIdentity(root), id);
    expect(await File('${root.path}/device.json.tmp').exists(), isFalse);
    await File('${root.path}/device.json').writeAsString('{"deviceId":""}');
    await expectLater(loadDeviceIdentity(root), throwsFormatException);
    await File('${root.path}/device.json').writeAsString('{');
    await expectLater(loadDeviceIdentity(root), throwsFormatException);
  });
}
