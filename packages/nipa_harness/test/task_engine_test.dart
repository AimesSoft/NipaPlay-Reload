import 'package:nipa_harness/nipa_harness.dart';
import 'package:test/test.dart';
import 'task_support.dart';

void main() {
  late MemoryJobStore store;
  late FakeExecutor executor;
  late TaskEngine engine;
  setUp(() {
    store = MemoryJobStore();
    executor = FakeExecutor();
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
  });
  tearDown(() => engine.close());

  test('verified lifecycle persists progress, phases, checkpoint and receipt',
      () async {
    await engine.start();
    final submitted = await engine.submit(type: 'test', title: 'Lifecycle');
    final context = await executor.entered.future;
    await context.report(
        phase: 'downloading',
        progress: JobProgress(completed: 5, total: 10, unit: 'bytes'),
        checkpoint: {'nativeId': 42});
    await context.markSideEffectCommitted();
    await context.report(
        phase: 'verifying',
        progress: JobProgress(completed: 1, total: 1, unit: 'files'));
    final completed = await context.succeed(verified(details: {
      'files': [
        {'path': '/out/video', 'expectedSize': 10, 'actualSize': 10}
      ]
    }));
    expect(completed.jobId, submitted.jobId);
    expect(completed.state, JobState.succeeded);
    expect((await engine.get(submitted.jobId)).checkpoint, {'nativeId': 42});
    final events = await store.events(submitted.jobId);
    expect(events.map((e) => e.kind), [
      'submitted',
      'running',
      'progress',
      'effect_committed',
      'progress',
      'succeeded'
    ]);
    expect(events.last.snapshot, completed.toJson());
    expect(completed.toJson().containsKey('input'), isFalse);
  });

  test('illegal transitions and unverified success do not change durable state',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Invalid');
    final context = await executor.entered.future;
    await expectLater(context.cancelled(verified()), throwsA(isA<Failure>()));
    for (final level in [
      VerificationLevel.acknowledged,
      VerificationLevel.unverified
    ]) {
      await expectLater(
          context.succeed(JobReceipt(verification: level, details: {})),
          throwsArgumentError);
    }
    expect((await engine.get(job.jobId)).state, JobState.running);
    await context.succeed(verified());
    await expectLater(engine.pause(job.jobId), throwsA(isA<Failure>()));
    expect((await store.events(job.jobId)), hasLength(3));
  });

  test('wait returns for change, timeout, already terminal and older cursor',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Wait');
    final context = await executor.entered.future;
    final baseline = await engine.get(job.jobId);
    final changed = engine.wait(job.jobId, afterRevision: baseline.revision);
    await context.report(phase: 'testing');
    expect((await changed).phase, 'testing');
    expect(
        (await engine.wait(job.jobId, afterRevision: baseline.revision)).phase,
        'testing');
    final timeout =
        await engine.wait(job.jobId, timeout: const Duration(milliseconds: 10));
    expect(timeout.state, JobState.running);
    final terminal = engine.wait(job.jobId, afterRevision: timeout.revision);
    await context.succeed(verified());
    expect((await terminal).state, JobState.succeeded);
    expect((await engine.wait(job.jobId)).state, JobState.succeeded);
    await expectLater(
        engine.wait(job.jobId, timeout: const Duration(seconds: 61)),
        throwsA(isA<Failure>()));
    await expectLater(
        engine.wait(job.jobId, afterRevision: 999), throwsA(isA<Failure>()));
  });

  test('restarts running as interrupted and reconciles instead of replaying',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Recover');
    final old = await executor.entered.future;
    await old.markSideEffectCommitted(checkpoint: {'externalId': 'existing'});
    await engine.close();
    final recoveredExecutor = FakeExecutor(onRecover: (context) async {
      expect(context.job.state, JobState.interrupted);
      expect(context.job.checkpoint, {'externalId': 'existing'});
      await context.report(phase: 'verifying');
      await context.succeed(verified());
    });
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'device-test',
        executors: [recoveredExecutor]);
    await engine.start();
    final completed = await untilState(engine, job.jobId, JobState.succeeded);
    expect(completed.jobId, job.jobId);
    expect(recoveredExecutor.executions, 0);
    expect(recoveredExecutor.recoveries, 1);
    expect((await store.events(job.jobId)).map((e) => e.snapshot['state']),
        containsAllInOrder(['running', 'interrupted', 'succeeded']));
    await expectLater(old.report(phase: 'late'), throwsA(isA<Failure>()));
  });

  test('cancellation before dispatch is terminal and idempotent', () async {
    final job = await engine.submit(type: 'test', title: 'Queued');
    final cancelled = await engine.cancel(job.jobId);
    expect(cancelled.state, JobState.cancelled);
    expect(cancelled.receipt!.verification, VerificationLevel.unverified);
    expect((await engine.cancel(job.jobId)).revision, cancelled.revision);
    await engine.start();
    expect(executor.executions, 0);
  });

  test('running cancellation is acknowledged by executor', () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Cancel');
    final context = await executor.entered.future;
    expect((await engine.cancel(job.jobId)).state, JobState.cancelling);
    await context.stopRequested;
    final cancelled = await context.cancelled(JobReceipt(
        verification: VerificationLevel.unverified,
        details: {'stopped': true}));
    expect(cancelled.state, JobState.cancelled);
    expect((cancelled.toJson()['receipt'] as JsonMap)['cancellation'],
        containsPair('phase', 'queued'));
  });

  for (final level in VerificationLevel.values) {
    test('cancel after commit preserves a ${level.name} receipt', () async {
      await engine.start();
      final job = await engine.submit(type: 'test', title: 'Committed');
      final context = await executor.entered.future;
      await context.report(phase: 'publishing');
      await context.markSideEffectCommitted(checkpoint: {'handle': 'effect-1'});
      await engine.cancel(job.jobId);
      final details = {'effect': 'effect-1', 'retained': true};
      final completed = await context
          .cancelled(JobReceipt(verification: level, details: details));
      expect(completed.state, JobState.cancelled);
      expect(completed.error, isNull);
      expect(completed.receipt!.verification, level);
      expect(completed.receipt!.details, details);
      expect(
          (completed.toJson()['receipt'] as JsonMap)['cancellation'],
          allOf(
              containsPair('sideEffectCommitted', true),
              containsPair('afterCommit', true),
              containsPair('phase', 'publishing')));
      expect((await store.events(job.jobId)).last.snapshot, completed.toJson());
    });
  }

  test('retry deadline survives restart and resumes through recovery',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Retry');
    final context = await executor.entered.future;
    await context.retryAt(
        DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
        const Failure(FailureCode.unavailable, 'Try later', retryable: true),
        checkpoint: {'attempt': 1});
    await engine.close();
    final second =
        FakeExecutor(onRecover: (context) => context.succeed(verified()));
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [second]);
    await engine.start();
    await untilState(engine, job.jobId, JobState.succeeded);
    expect(second.recoveries, 1);
    expect(second.executions, 0);
  });

  test('pause fences late writes, resume waits for old worker and reconciles',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Pause');
    final context = await executor.entered.future;
    await engine.pause(job.jobId);
    executor.release.complete();
    await expectLater(context.report(phase: 'late'), throwsA(isA<Failure>()));
    await engine.resume(job.jobId);
    final recovered = await executor.recovered.future;
    expect(recovered.job.state, JobState.interrupted);
    await recovered.succeed(verified());
    expect(executor.executions, 1);
  });

  test('worker exceptions persist failures and never become success', () async {
    engine = TaskEngine(store: store, ownerDeviceId: 'device-test', executors: [
      FakeExecutor(onExecute: (_) async => throw StateError('broken')),
    ]);
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Throws');
    final failed = await untilState(engine, job.jobId, JobState.failed);
    expect(failed.error!.code, FailureCode.internal);
    expect(failed.error!.message, contains('broken'));
    expect(failed.receipt!.verification, VerificationLevel.unverified);
  });

  test('returning Future without verification fails explicitly', () async {
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'device-test',
        executors: [FakeExecutor(onExecute: (_) async {})]);
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Incomplete');
    expect(
        (await untilState(engine, job.jobId, JobState.failed)).error!.message,
        contains('without a persisted disposition'));
  });

  test('batch cancellation accepts each request and preserves single-job calls',
      () async {
    final api = Harness([TaskCapability(engine)]);
    final first = await engine.submit(type: 'test', title: 'First');
    final second = await engine.submit(type: 'test', title: 'Second');
    final outcome = await api.invokeJson(
        'task.cancel',
        {
          'jobIds': [first.jobId, 'missing', second.jobId, first.jobId],
        },
        Invocation(origin: 'mcp')) as Completed;
    final result = outcome.value.toJson();
    expect(api.lookup('task.cancel')!.spec.output.validate(result), isEmpty);
    final rows = (result['results'] as List).cast<Map>();
    expect(rows.map((row) => row['status']),
        ['completed', 'failed', 'completed', 'completed']);
    expect((rows[1]['error'] as Map)['code'], 'not_found');
    expect((rows.first['job'] as Map)['state'], 'cancelled');
    expect(
        (rows.first['job'] as Map)['receipt'],
        containsPair(
            'details', containsPair('reason', 'cancelled_before_start')));
    expect((rows.last['job'] as Map)['revision'],
        (rows.first['job'] as Map)['revision']);
    final legacy = await api.invokeJson(
            'task.cancel', {'jobId': second.jobId}, Invocation(origin: 'gui'))
        as Completed;
    expect(legacy.value.toJson()['job'], rows[2]['job']);
    final ambiguous = await api.invokeJson(
        'task.cancel',
        {
          'jobId': first.jobId,
          'jobIds': [second.jobId],
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(ambiguous.failure.code, FailureCode.invalidInput);
  });

  test('task actions expose matching contracts, filters and input failures',
      () async {
    final harness = Harness([TaskCapability(engine)]);
    final job = await engine.submit(type: 'test', title: 'Actions');
    expect(harness.catalog.map((s) => s.id),
        ['task.cancel', 'task.get', 'task.list', 'task.wait']);
    for (final call in <String, JsonMap>{
      'task.get': {'jobId': job.jobId},
      'task.wait': {'jobId': job.jobId, 'timeoutMs': 0},
      'task.list': {'state': 'queued', 'type': 'test'},
      'task.cancel': {'jobId': job.jobId}
    }.entries) {
      final outcome = await harness.invokeJson(
          call.key, call.value, Invocation(origin: 'test'));
      expect(outcome, isA<Completed<JsonEncodable>>());
      expect(
          harness
              .lookup(call.key)!
              .spec
              .output
              .validate((outcome as Completed).value.toJson()),
          isEmpty);
    }
    final bad = await harness.invokeJson(
        'task.wait',
        {'jobId': job.jobId, 'timeoutMs': 60001},
        Invocation(origin: 'test')) as Failed;
    expect(bad.failure.code, FailureCode.invalidInput);
    final missing = await harness.invokeJson(
        'task.get', {'jobId': 'missing'}, Invocation(origin: 'test')) as Failed;
    expect(missing.failure.code, FailureCode.notFound);
    expect(await engine.list(type: 'other'), isEmpty);
  });

  test('decision input and checkpoint remain immutable across callers',
      () async {
    final input = <String, Object?>{
      'values': [1]
    };
    final job =
        await engine.submit(type: 'test', title: 'Immutable', input: input);
    (input['values'] as List).add(2);
    expect(job.input['values'], [1]);
    expect(() => (job.input['values'] as List).add(3), throwsUnsupportedError);
    expect(
        JobProgress(completed: 0, unit: 'items').toJson().containsKey('total'),
        isFalse);
    expect(() => JobProgress(completed: 2, total: 1, unit: 'files'),
        throwsArgumentError);
  });

  test('persisted decision resumes by its call and rejects a different option',
      () async {
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Decision');
    final context = await executor.entered.future;
    final call = ActionCall('test.choose', {
      'jobId': job.jobId,
      'revision': context.job.revision + 1,
      'choice': 'accepted'
    });
    final waiting = await context.needsDecision(Decision(
        prompt: 'Choose source',
        options: [DecisionOption(label: 'Source', call: call)]));
    await expectLater(
        context.report(phase: 'late_progress'), throwsA(isA<Failure>()));
    expect((await engine.get(job.jobId)).revision, waiting.revision);
    executor.release.complete();
    final persisted =
        Job.fromJson((await store.get(job.jobId))!.toStorageJson());
    expect(persisted.decision!.toJson(), waiting.decision!.toJson());
    final harness = Harness([TaskCapability(engine), ChoiceCapability(engine)]);
    final invalid = await harness.invokeJson(
        'test.choose',
        {...call.input, 'choice': 'other'},
        Invocation(origin: 'test')) as Failed;
    expect(invalid.failure.code, FailureCode.conflict);
    expect((await engine.get(job.jobId)).state, JobState.needsDecision);
    // JSON object field ordering is not part of an option's identity.
    final input = <String, Object?>{
      'choice': 'accepted',
      'revision': call.input['revision'],
      'jobId': job.jobId
    };
    expect(
        await harness.invokeJson(
            call.actionId, input, Invocation(origin: 'test')),
        isA<Completed>());
    final recovered = await executor.recovered.future;
    expect(recovered.job.checkpoint, {'choice': 'accepted'});
    await recovered.succeed(verified());
    final stale = await harness.invokeJson(
        call.actionId, input, Invocation(origin: 'test')) as Failed;
    expect(stale.failure.code, FailureCode.conflict);
  });

  test('shutdown releases bounded waiters without timer errors', () async {
    final job = await engine.submit(type: 'test', title: 'Close wait');
    final waiting =
        expectLater(engine.wait(job.jobId), throwsA(isA<Failure>()));
    await engine.close();
    await waiting;
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [executor]);
  });

  test('cancel interrupted job is reconciled and acknowledged without replay',
      () async {
    await engine.start();
    final job =
        await engine.submit(type: 'test', title: 'Interrupted cancellation');
    await executor.entered.future;
    await engine.cancel(job.jobId);
    await engine.close();
    final second = FakeExecutor(onRecover: (context) async {
      await context.stopRequested;
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.unverified,
          details: {'stopped': true}));
    });
    engine = TaskEngine(
        store: store, ownerDeviceId: 'device-test', executors: [second]);
    await engine.start();
    final cancelled = await untilState(engine, job.jobId, JobState.cancelled);
    expect(cancelled.toJson()['receipt'],
        containsPair('cancellation', containsPair('afterCommit', false)));
    expect(second.executions, 0);
  });
}
