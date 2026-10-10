import 'dart:async';
import 'package:nipa_harness/nipa_harness.dart';

final class MemoryJobStore implements JobStore {
  final jobs = <String, Job>{};
  final history = <String, List<JobEvent>>{};
  @override
  Future<Job?> get(String id) async => jobs[id];
  @override
  Future<List<Job>> list({JobState? state, String? type}) async => jobs.values
      .where((job) =>
          (state == null || job.state == state) &&
          (type == null || job.type == type))
      .toList();
  @override
  Future<void> commit(Job job, JobEvent event,
      {required int? expectedRevision}) async {
    if (jobs[job.jobId]?.revision != expectedRevision) {
      throw const Failure(FailureCode.conflict, 'Stale revision.');
    }
    jobs[job.jobId] = Job.fromJson(job.toStorageJson());
    (history[job.jobId] ??= []).add(event);
  }

  @override
  Future<List<JobEvent>> events(String id, {int afterRevision = -1}) async =>
      (history[id] ?? [])
          .where((event) => event.revision > afterRevision)
          .toList();
  @override
  Future<void> close() async {}
}

final class FakeExecutor implements JobExecutor {
  FakeExecutor({this.type = 'test', this.onExecute, this.onRecover});
  @override
  final String type;
  final Future<void> Function(JobContext)? onExecute, onRecover;
  final entered = Completer<JobContext>();
  final recovered = Completer<JobContext>();
  final release = Completer<void>();
  final releaseRecovery = Completer<void>();
  int executions = 0, recoveries = 0;
  @override
  Future<void> execute(JobContext context) async {
    executions++;
    if (!entered.isCompleted) entered.complete(context);
    if (onExecute != null) {
      await onExecute!(context);
    } else {
      await release.future;
    }
  }

  @override
  Future<void> recover(JobContext context) async {
    recoveries++;
    if (!recovered.isCompleted) recovered.complete(context);
    if (onRecover != null) {
      await onRecover!(context);
    } else {
      await releaseRecovery.future;
    }
  }
}

JobReceipt verified({JsonMap details = const {'checked': true}}) =>
    JobReceipt(verification: VerificationLevel.verified, details: details);

Future<Job> untilState(TaskEngine engine, String id, JobState state) async {
  var job = await engine.get(id);
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (job.state != state) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Expected $state, got ${job.state}');
    }
    job = await engine.wait(id,
        afterRevision: job.revision, timeout: const Duration(milliseconds: 20));
  }
  return job;
}

final class ChoiceCapability implements Capability {
  ChoiceCapability(TaskEngine engine) : actions = [_ChoiceAction(engine)];
  @override
  final List<Action> actions;
}

final class _ChoiceAction extends Action<_ChoiceInput, NoInput> {
  _ChoiceAction(this.engine);
  final TaskEngine engine;
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'test.choose',
      title: 'Choose',
      description: 'Apply a persisted test decision.',
      effect: Effect.write,
      input: ObjectSchema({
        'jobId': StringSchema(),
        'revision': IntegerSchema(minimum: 0),
        'choice': StringSchema()
      }, required: [
        'jobId',
        'revision',
        'choice'
      ]),
      output: ObjectSchema({}));
  @override
  _ChoiceInput decodeInput(JsonMap json) => _ChoiceInput(json);
  @override
  Future<Outcome<NoInput>> run(
      _ChoiceInput input, Invocation invocation) async {
    await engine.resolveDecision(input.json['jobId'] as String,
        revision: (input.json['revision'] as num).toInt(),
        call: ActionCall('test.choose', input.json),
        checkpoint: {'choice': input.json['choice']});
    return const Completed(NoInput());
  }
}

final class _ChoiceInput implements JsonEncodable {
  _ChoiceInput(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}
