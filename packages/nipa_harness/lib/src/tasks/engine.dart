part of '../kernel.dart';

/// Executors own domain effects and verification. recover must reconcile the
/// persisted checkpoint with the real world before choosing a disposition.
abstract interface class JobExecutor {
  String get type;
  Future<void> execute(JobContext context);
  Future<void> recover(JobContext context);
}

final class JobContext {
  JobContext._(this._engine, this._job);
  final TaskEngine _engine;
  Job _job;
  Job get job => _job;
  final _stop = Completer<void>();
  bool _retired = false;

  /// Completes on cancellation, pause or engine shutdown. Read snapshot() to
  /// distinguish controls; cancellation does not invalidate verification writes.
  Future<void> get stopRequested => _stop.future;
  Future<Job> snapshot() => _engine.get(job.jobId);

  Future<Job> report(
          {String? phase,
          JobProgress? progress,
          JsonMap? checkpoint,
          JsonMap? details}) =>
      _update('progress',
          phase: phase,
          progress: progress,
          checkpoint: checkpoint,
          details: details);

  Future<Job> markSideEffectCommitted({JsonMap? checkpoint}) =>
      _update('effect_committed', checkpoint: checkpoint, committed: true);

  Future<Job> running({String? phase}) =>
      _update('running', state: JobState.running, phase: phase);

  Future<Job> needsDecision(Decision decision, {JsonMap? checkpoint}) {
    if (decision.options.isEmpty) {
      throw ArgumentError('A decision needs executable options.');
    }
    return _update('needs_decision',
        state: JobState.needsDecision,
        decision: decision,
        checkpoint: checkpoint);
  }

  Future<Job> retryAt(DateTime at, Failure error, {JsonMap? checkpoint}) =>
      _update('waiting_retry',
          state: JobState.waitingRetry,
          retryAt: at.toUtc(),
          error: error,
          checkpoint: checkpoint);

  Future<Job> succeed(JobReceipt receipt) =>
      _update('succeeded', state: JobState.succeeded, receipt: receipt);

  Future<Job> fail(Failure error, JobReceipt receipt) =>
      _update('failed', state: JobState.failed, error: error, receipt: receipt);

  Future<Job> cancelled(JobReceipt receipt) =>
      _update('cancelled', state: JobState.cancelled, receipt: receipt);

  Future<Job> _update(
    String kind, {
    JobState? state,
    String? phase,
    JobProgress? progress,
    JsonMap? checkpoint,
    JsonMap? details,
    bool? committed,
    Decision? decision,
    DateTime? retryAt,
    Failure? error,
    JobReceipt? receipt,
  }) async {
    final updated = await _engine._edit(job.jobId, kind, (current) {
      if (_retired || !identical(_engine._active[current.jobId], this)) {
        throw const Failure(
            FailureCode.conflict, 'This executor is no longer active.');
      }
      return _change(current,
          state: state,
          phase: phase,
          progress: progress,
          checkpoint: checkpoint,
          details: details,
          committed: committed,
          decision: decision,
          retryAt: retryAt,
          error: error,
          receipt: receipt);
    });
    _job = updated;
    return updated;
  }

  void _signal({bool retire = false}) {
    _retired = _retired || retire;
    if (!_stop.isCompleted) _stop.complete();
  }
}

final class TaskEngine {
  TaskEngine(
      {required this.store,
      required this.ownerDeviceId,
      Iterable<JobExecutor> executors = const []}) {
    for (final executor in executors) {
      if (_executors.containsKey(executor.type)) {
        throw ArgumentError('Duplicate executor type: ${executor.type}');
      }
      _executors[executor.type] = executor;
    }
  }

  final JobStore store;
  final String ownerDeviceId;
  final Map<String, JobExecutor> _executors = {};
  final Map<String, JobContext> _active = {};
  final Map<String, Timer> _retries = {};
  final _changes = StreamController<Job>.broadcast(sync: true);

  /// Persisted changes, emitted only after snapshot and event commit.
  Stream<Job> get changes => _changes.stream;
  Future<void> _tail = Future.value();
  bool _started = false, _closed = false;

  Future<T> _serial<T>(Future<T> Function() operation,
      {bool allowClosed = false}) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      if (_closed && !allowClosed) {
        throw const Failure(FailureCode.unavailable, 'Task engine is closed.');
      }
      return await operation();
    } finally {
      done.complete();
    }
  }

  Future<void> start() async {
    await _serial(() async {
      if (_started) return;
      for (final job in await store.list()) {
        if (job.ownerDeviceId != ownerDeviceId) continue;
        if (job.state == JobState.running || job.state == JobState.cancelling) {
          await _commit(
              _change(job, state: JobState.interrupted), job, 'interrupted');
        }
      }
      _started = true;
    });
    for (final job in await list()) {
      _schedule(job);
    }
  }

  Future<Job> submit(
      {required String type,
      required String title,
      JsonMap input = const {},
      JsonMap details = const {},
      String phase = 'queued',
      String? jobId}) async {
    if (!_executors.containsKey(type)) {
      throw Failure(
          FailureCode.unavailable, 'No executor registered for $type.');
    }
    final job = await _serial(() async {
      final now = DateTime.now().toUtc();
      final job = Job(
          jobId: jobId ?? _newJobId(),
          type: type,
          title: title,
          state: JobState.queued,
          phase: phase,
          progress: JobProgress(completed: 0, unit: 'items'),
          createdAt: now,
          updatedAt: now,
          ownerDeviceId: ownerDeviceId,
          revision: 0,
          input: input,
          details: details);
      await _commit(job, null, 'submitted');
      return job;
    });
    _schedule(job);
    return job;
  }

  Future<Job> get(String jobId) => _serial(() => _get(jobId));
  Future<Job> _get(String jobId) async =>
      await store.get(jobId) ??
      (throw Failure(FailureCode.notFound, 'Unknown job: $jobId.'));

  Future<List<Job>> list({JobState? state, String? type}) =>
      _serial(() => store.list(state: state, type: type));

  Future<Job> _edit(String id, String kind, Job Function(Job) edit) =>
      _serial(() async {
        final current = await _get(id);
        if (current.ownerDeviceId != ownerDeviceId) {
          throw const Failure(
              FailureCode.conflict, 'Job belongs to another device.');
        }
        final updated = edit(current);
        if (identical(updated, current)) return current;
        await _commit(updated, current, kind);
        return updated;
      });

  Future<void> _commit(Job job, Job? previous, String kind) async {
    await store.commit(
        job,
        JobEvent(
            jobId: job.jobId,
            revision: job.revision,
            kind: kind,
            at: job.updatedAt,
            snapshot: job.toJson()),
        expectedRevision: previous?.revision);
    final context = _active[job.jobId];
    if (context != null) {
      context._job = job;
      if (job.state.isTerminal ||
          job.state == JobState.needsDecision ||
          job.state == JobState.waitingRetry) {
        context._retired = true;
      }
    }
    _changes.add(job);
  }

  Future<Job> cancel(String jobId) async {
    final job = await _edit(jobId, 'cancel_requested', (job) {
      if (job.state.isTerminal || job.cancelRequestedAt != null) return job;
      var next = _change(job,
          state: JobState.cancelling,
          cancelRequestedAt: DateTime.now().toUtc());
      // Only a never-started job has no external effects to reconcile.
      if (job.state == JobState.queued && job.revision == 0) {
        next = _change(next,
            state: JobState.cancelled,
            receipt: JobReceipt(
                verification: VerificationLevel.unverified,
                details: {'reason': 'cancelled_before_start'}));
        next = Job.fromJson(
            {...next.toStorageJson(), 'revision': job.revision + 1});
      }
      return next;
    });
    _active[jobId]?._signal();
    _schedule(job);
    return job;
  }

  Future<Job> pause(String jobId) async {
    final job = await _edit(
        jobId, 'paused', (job) => _change(job, state: JobState.paused));
    _active[jobId]?._signal(retire: true);
    _retries.remove(jobId)?.cancel();
    return job;
  }

  /// A paused execution is reconciled rather than blindly repeated.
  Future<Job> resume(String jobId) async {
    final job = await _edit(jobId, 'resumed', (job) {
      if (job.state != JobState.paused) {
        throw const Failure(FailureCode.conflict, 'Job is not paused.');
      }
      return _change(job, state: JobState.interrupted);
    });
    _schedule(job);
    return job;
  }

  /// Domain actions call this after applying the chosen option. Revision and
  /// exact call matching prevent an old decision from resuming a newer one.
  Future<Job> resolveDecision(String jobId,
      {required int revision,
      required ActionCall call,
      JsonMap? checkpoint}) async {
    final job = await _edit(jobId, 'decision_resolved', (job) {
      if (job.state != JobState.needsDecision ||
          job.revision != revision ||
          !job.decision!.options.any(
              (option) => _sameJson(option.call.toJson(), call.toJson()))) {
        throw const Failure(FailureCode.conflict,
            'Decision is stale or call is not an option.');
      }
      return _change(job, state: JobState.interrupted, checkpoint: checkpoint);
    });
    _schedule(job);
    return job;
  }

  /// Subscribe before reading, so a committed change cannot fall into the gap
  /// between obtaining the snapshot and installing the waiter.
  Future<Job> wait(String jobId,
      {int? afterRevision,
      bool includeProgress = false,
      Duration timeout = const Duration(seconds: 60)}) async {
    if (timeout < Duration.zero ||
        timeout > const Duration(seconds: 60) ||
        (afterRevision != null && afterRevision < 0)) {
      throw const Failure(FailureCode.invalidInput,
          'Wait is bounded to 0–60 seconds and a nonnegative revision.');
    }
    final changed = Completer<void>();
    final pending = <Job>[];
    JsonMap? previous;
    var cursor = -1;
    void observe(JsonMap snapshot) {
      final revision = snapshot['revision'] as int;
      if (revision <= cursor) return;
      final meaningful = snapshot['state'] != previous!['state'] ||
          snapshot['phase'] != previous!['phase'] ||
          !_sameJson(snapshot['decision'], previous!['decision']) ||
          (includeProgress &&
              !_sameJson(snapshot['progress'], previous!['progress']));
      previous = snapshot;
      cursor = revision;
      final terminal = JobState.values
          .singleWhere((state) => state.wireName == snapshot['state'])
          .isTerminal;
      if ((terminal || meaningful) && !changed.isCompleted) changed.complete();
    }

    final subscription = _changes.stream.listen((job) {
      if (job.jobId != jobId) return;
      if (previous == null) {
        pending.add(job);
      } else {
        observe(job.toJson());
      }
    }, onDone: () {
      if (!changed.isCompleted) changed.complete();
    });
    Timer? timer;
    try {
      final current = await get(jobId);
      final baseline = afterRevision ?? current.revision;
      if (afterRevision != null && afterRevision > current.revision) {
        throw const Failure(
            FailureCode.invalidInput, 'Revision is ahead of the job.');
      }
      if (current.state.isTerminal) return current;
      if (baseline < current.revision) {
        final events = await store.events(jobId, afterRevision: baseline - 1);
        previous = events.firstWhere((e) => e.revision == baseline).snapshot;
        cursor = baseline;
        for (final event in events) {
          observe(event.snapshot);
        }
      } else {
        previous = current.toJson();
        cursor = baseline;
      }
      for (final job in pending) {
        observe(job.toJson());
      }
      if (changed.isCompleted) return await get(jobId);
      timer = Timer(timeout, () {
        if (!changed.isCompleted) changed.complete();
      });
      await changed.future;
      return await get(jobId);
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
  }

  void _schedule(Job job) {
    _retries.remove(job.jobId)?.cancel();
    if (!_started ||
        _closed ||
        job.ownerDeviceId != ownerDeviceId ||
        _active.containsKey(job.jobId) ||
        !_executors.containsKey(job.type)) {
      return;
    }
    if (job.state == JobState.waitingRetry) {
      _retries[job.jobId] =
          Timer(job.retryAt!.difference(DateTime.now().toUtc()), () {
        _launch(job, retry: true);
      });
    } else if ({JobState.queued, JobState.interrupted, JobState.cancelling}
        .contains(job.state)) {
      _launch(job);
    }
  }

  void _launch(Job job, {bool retry = false}) {
    if (_closed || _active.containsKey(job.jobId)) return;
    final context = JobContext._(this, job);
    if (job.cancelRequestedAt != null) context._signal();
    _active[job.jobId] = context;
    unawaited(_run(context, retry: retry));
  }

  Future<void> _run(JobContext context, {required bool retry}) async {
    final action = _ExecutorAction(() async {
      final current = await get(context.job.jobId);
      context._job = current;
      if (current.state.isTerminal || current.state == JobState.paused) return;
      final executor = _executors[current.type]!;
      if (current.state == JobState.queued ||
          (retry && current.state == JobState.waitingRetry)) {
        if (retry) {
          await context._update('retry_due', state: JobState.interrupted);
          await executor.recover(context);
        } else {
          await context.running();
          await executor.execute(context);
        }
      } else {
        await executor.recover(context);
      }
      if (!context._retired &&
          !_closed &&
          {JobState.running, JobState.interrupted, JobState.cancelling}
              .contains(context.job.state)) {
        throw const Failure(FailureCode.internal,
            'Executor returned without a persisted disposition.');
      }
    });
    // Harness remains the sole catch-all exception boundary, including workers.
    final outcome = await Harness(const [])
        .invoke(action, const NoInput(), Invocation(origin: 'task_engine'));
    await _serial(() async {
      if (!_closed) {
        final current = await _get(context.job.jobId);
        if (outcome case Failed<NoInput>(:final failure)) {
          if (!context._retired && !current.state.isTerminal) {
            await _commit(
                _change(current,
                    state: JobState.failed,
                    error: failure,
                    receipt: JobReceipt(
                        verification: VerificationLevel.unverified,
                        details: {'reason': 'executor_failed'})),
                current,
                'failed');
          }
        }
        _active.remove(context.job.jobId);
        _schedule(await _get(context.job.jobId));
      } else {
        _active.remove(context.job.jobId);
      }
    }, allowClosed: true);
  }

  Future<void> close() async {
    await _serial(() async {
      _closed = true;
      for (final timer in _retries.values) {
        timer.cancel();
      }
      _retries.clear();
      for (final context in _active.values) {
        context._signal(retire: true);
      }
      await _changes.close();
      await store.close();
    });
  }
}

Job _change(Job job,
    {JobState? state,
    String? phase,
    JobProgress? progress,
    JsonMap? checkpoint,
    JsonMap? details,
    bool? committed,
    Decision? decision,
    DateTime? retryAt,
    Failure? error,
    JobReceipt? receipt,
    DateTime? cancelRequestedAt}) {
  final next = state ?? job.state;
  if (job.state.isTerminal ||
      (next != job.state && !job.state.canTransitionTo(next))) {
    throw Failure(FailureCode.conflict,
        'Illegal job transition: ${job.state.wireName} → ${next.wireName}.');
  }
  if (next == JobState.cancelled && job.cancelRequestedAt == null) {
    throw const Failure(
        FailureCode.conflict, 'Cancellation must be requested first.');
  }
  final json = job.toStorageJson();
  if (next != JobState.needsDecision) json.remove('decision');
  if (next != JobState.waitingRetry) json.remove('retryAt');
  if (next != JobState.failed && next != JobState.waitingRetry) {
    json.remove('error');
  }
  return Job.fromJson({
    ...json,
    'state': next.wireName,
    'revision': job.revision + 1,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    if (phase != null) 'phase': phase,
    if (progress != null) 'progress': progress.toJson(),
    if (checkpoint != null) 'checkpoint': checkpoint,
    if (details != null) 'details': details,
    if (committed != null) 'sideEffectCommitted': committed,
    if (decision != null) 'decision': decision.toJson(),
    if (retryAt != null) 'retryAt': retryAt.toIso8601String(),
    if (error != null) 'error': error.toJson(),
    if (receipt != null) 'receipt': receipt.toJson(),
    if (cancelRequestedAt != null) ...{
      'cancelRequestedAt': cancelRequestedAt.toIso8601String(),
      'cancelRequestedPhase': job.phase,
      'cancelAfterCommit': job.sideEffectCommitted,
    },
  });
}

String _newJobId() {
  final random = Random.secure();
  return 'job-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

bool _sameJson(Object? left, Object? right) {
  if (left is JsonMap && right is JsonMap) {
    return left.length == right.length &&
        left.entries.every((entry) =>
            right.containsKey(entry.key) &&
            _sameJson(entry.value, right[entry.key]));
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(
                left.length, (index) => _sameJson(left[index], right[index]))
            .every((equal) => equal);
  }
  return left == right;
}

final class _ExecutorAction extends Action<NoInput, NoInput> {
  _ExecutorAction(this.execute);
  final Future<void> Function() execute;
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'task_worker.execute',
      title: 'Execute task worker',
      description: 'Internal executor boundary.',
      effect: Effect.write,
      input: ObjectSchema({}),
      output: ObjectSchema({}));
  @override
  NoInput decodeInput(JsonMap json) => const NoInput();
  @override
  Future<Outcome<NoInput>> run(NoInput input, Invocation invocation) async {
    await execute();
    return const Completed(NoInput());
  }
}
