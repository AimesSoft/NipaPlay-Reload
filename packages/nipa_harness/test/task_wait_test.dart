import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:test/test.dart';

import 'task_support.dart';

void main() {
  late MemoryJobStore store;
  late FakeExecutor executor;
  late TaskEngine engine;
  late JobContext context;
  setUp(() async {
    store = MemoryJobStore();
    executor = FakeExecutor();
    engine =
        TaskEngine(store: store, ownerDeviceId: 'local', executors: [executor]);
    await engine.start();
    await engine.submit(type: 'test', title: 'Wait');
    context = await executor.entered.future;
  });
  tearDown(() => engine.close());

  test(
      'progress bursts do not wake default wait; timeout returns latest progress',
      () async {
    final baseline = context.job;
    var returned = false;
    final waiting = engine.wait(baseline.jobId,
        afterRevision: baseline.revision,
        timeout: const Duration(milliseconds: 30));
    unawaited(waiting.then((_) => returned = true));
    for (var bytes = 1; bytes <= 10; bytes++) {
      await context.report(
          progress: JobProgress(completed: bytes, unit: 'bytes'));
    }
    await context
        .report(checkpoint: {'handle': 'effect'}, details: {'count': 1});
    await context.markSideEffectCommitted();
    await Future<void>.delayed(Duration.zero);
    expect(returned, false);
    final timedOut = await waiting;
    expect(timedOut.progress.completed, 10);
    expect(timedOut.revision, context.job.revision);
  });

  test('explicit progress wait ignores unchanged progress and wakes on change',
      () async {
    var returned = false;
    final waiting = engine.wait(context.job.jobId, includeProgress: true);
    unawaited(waiting.then((_) => returned = true));
    await Future<void>.delayed(Duration.zero);
    await context.report(progress: context.job.progress);
    await Future<void>.delayed(Duration.zero);
    expect(returned, false);
    await context.report(progress: JobProgress(completed: 1, unit: 'bytes'));
    expect((await waiting).progress.completed, 1);
  });

  test('older cursor with only progress changes waits for a phase change',
      () async {
    final baseline = context.job;
    await context.report(progress: JobProgress(completed: 1, unit: 'bytes'));
    var returned = false;
    final waiting =
        engine.wait(baseline.jobId, afterRevision: baseline.revision);
    unawaited(waiting.then((_) => returned = true));
    await Future<void>.delayed(Duration.zero);
    expect(returned, false);
    await context.report(phase: 'verifying');
    expect((await waiting).phase, 'verifying');
  });

  test('older cursor catches a phase transition away and back', () async {
    final baseline = context.job;
    await context.report(phase: 'verifying');
    await context.report(phase: baseline.phase);
    var returned = false;
    final waiting =
        engine.wait(baseline.jobId, afterRevision: baseline.revision);
    unawaited(waiting.then((_) => returned = true));
    await Future<void>.delayed(Duration.zero);
    expect(returned, true);
    await waiting;
  });

  test('state changes wake even with unchanged phase', () async {
    final waiting = engine.wait(context.job.jobId);
    await Future<void>.delayed(Duration.zero);
    await engine.pause(context.job.jobId);
    expect((await waiting).state, JobState.paused);
  });

  test(
      'decision changes in persisted history wake with unchanged state and phase',
      () async {
    Decision decision(String label) => Decision(prompt: 'Choose', options: [
          DecisionOption(
              label: label, call: ActionCall('test.choose', {'value': label}))
        ]);
    final baseline = await context.needsDecision(decision('first'));
    final updated = Job.fromJson({
      ...baseline.toStorageJson(),
      'revision': baseline.revision + 1,
      'decision': decision('second').toJson()
    });
    await store.commit(
        updated,
        JobEvent(
            jobId: updated.jobId,
            revision: updated.revision,
            kind: 'decision',
            at: updated.updatedAt,
            snapshot: updated.toJson()),
        expectedRevision: baseline.revision);
    var returned = false;
    final waiting =
        engine.wait(updated.jobId, afterRevision: baseline.revision);
    unawaited(waiting.then((_) => returned = true));
    await Future<void>.delayed(Duration.zero);
    expect(returned, true);
    expect((await waiting).decision!.options.single.label, 'second');
  });

  test('task.wait exposes and forwards includeProgress', () async {
    final harness = Harness([TaskCapability(engine)]);
    final waiting = harness.invokeJson(
        'task.wait',
        {
          'jobId': context.job.jobId,
          'afterRevision': context.job.revision,
          'includeProgress': true,
          'timeoutMs': 1000
        },
        Invocation(origin: 'test'));
    await Future<void>.delayed(Duration.zero);
    await context.report(progress: JobProgress(completed: 7, unit: 'bytes'));
    final outcome = await waiting as Completed<JsonEncodable>;
    expect((outcome.value.toJson()['job'] as JsonMap)['progress'],
        containsPair('completed', 7));
    final bad = await harness.invokeJson(
        'task.wait',
        {'jobId': context.job.jobId, 'includeProgress': 'yes'},
        Invocation(origin: 'test')) as Failed;
    expect(bad.failure.code, FailureCode.invalidInput);
  });

  test('meaningful changes during snapshot read are not lost', () async {
    await engine.close();
    final delayed = _DelayedReadStore();
    executor = FakeExecutor();
    engine = TaskEngine(
        store: delayed, ownerDeviceId: 'local', executors: [executor]);
    await engine.start();
    final job = await engine.submit(type: 'test', title: 'Read gap');
    final worker = await executor.entered.future;
    delayed.blockNextRead = true;
    final waiting = engine.wait(job.jobId, afterRevision: worker.job.revision);
    await delayed.entered.future;
    final change = worker.report(phase: 'verifying');
    delayed.release.complete();
    await change;
    expect((await waiting).phase, 'verifying');
  });
}

final class _DelayedReadStore implements JobStore {
  final delegate = MemoryJobStore();
  final entered = Completer<void>(), release = Completer<void>();
  bool blockNextRead = false;
  @override
  Future<Job?> get(String jobId) async {
    final snapshot = await delegate.get(jobId);
    if (blockNextRead) {
      blockNextRead = false;
      entered.complete();
      await release.future;
    }
    return snapshot;
  }

  @override
  Future<List<Job>> list({JobState? state, String? type}) =>
      delegate.list(state: state, type: type);
  @override
  Future<List<Job>> listActive() => delegate.listActive();
  @override
  Future<List<Job>> listRecent(
          {JobState? state, String? type, int limit = 20, int offset = 0}) =>
      delegate.listRecent(
          state: state, type: type, limit: limit, offset: offset);
  @override
  Future<void> commit(Job job, JobEvent event,
          {required int? expectedRevision}) =>
      delegate.commit(job, event, expectedRevision: expectedRevision);
  @override
  Future<List<JobEvent>> events(String jobId, {int afterRevision = -1}) =>
      delegate.events(jobId, afterRevision: afterRevision);
  @override
  Future<void> close() => delegate.close();
}
