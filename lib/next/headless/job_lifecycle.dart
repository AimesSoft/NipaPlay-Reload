import 'dart:async';
import 'package:nipa_harness/nipa_harness.dart';

/// The host closes the shared database after every domain worker has returned.
final class HeadlessJobStore implements JobStore {
  const HeadlessJobStore(this.delegate);
  final JobStore delegate;
  @override
  Future<Job?> get(String id) => delegate.get(id);
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
  Future<List<JobEvent>> events(String id, {int afterRevision = -1}) =>
      delegate.events(id, afterRevision: afterRevision);
  @override
  Future<void> close() async {}
}

final class HeadlessExecutor implements JobExecutor {
  HeadlessExecutor(this.delegate);
  final JobExecutor delegate;
  final _active = <Future<void>>{};
  @override
  String get type => delegate.type;
  Future<void> _run(JobContext context, bool recover) async {
    final done = Completer<void>();
    _active.add(done.future);
    try {
      await (recover ? delegate.recover(context) : delegate.execute(context));
    } finally {
      _active.remove(done.future);
      done.complete();
    }
  }

  @override
  Future<void> execute(JobContext context) => _run(context, false);
  @override
  Future<void> recover(JobContext context) => _run(context, true);
  Future<void> drain() => Future.wait(_active.toList());
}
