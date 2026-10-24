part of '../kernel.dart';

enum JobState {
  queued,
  running,
  paused,
  needsDecision,
  waitingUser,
  waitingRetry,
  interrupted,
  cancelling,
  succeeded,
  failed,
  cancelled;

  String get wireName => switch (this) {
        needsDecision => 'needs_decision',
        waitingUser => 'waiting_user',
        waitingRetry => 'waiting_retry',
        _ => name,
      };

  bool get isTerminal =>
      this == succeeded || this == failed || this == cancelled;

  bool canTransitionTo(JobState next) => switch (this) {
        queued => {running, paused, cancelling, failed}.contains(next),
        running => {
            paused,
            needsDecision,
            waitingUser,
            waitingRetry,
            interrupted,
            cancelling,
            succeeded,
            failed
          }.contains(next),
        paused => {queued, interrupted, cancelling}.contains(next),
        needsDecision =>
          {queued, interrupted, cancelling, failed}.contains(next),
        waitingUser =>
          {running, interrupted, cancelling, failed}.contains(next),
        waitingRetry =>
          {queued, paused, interrupted, cancelling, failed}.contains(next),
        interrupted => {
            running,
            paused,
            needsDecision,
            waitingUser,
            waitingRetry,
            cancelling,
            succeeded,
            failed,
            cancelled
          }.contains(next),
        cancelling =>
          {interrupted, succeeded, failed, cancelled}.contains(next),
        succeeded || failed || cancelled => false,
      };
}

enum VerificationLevel { verified, acknowledged, unverified }

final class JobProgress implements JsonEncodable {
  JobProgress({required this.completed, this.total, required this.unit}) {
    if (!completed.isFinite ||
        completed < 0 ||
        unit.isEmpty ||
        (total != null && (!total!.isFinite || total! < completed))) {
      throw ArgumentError('Invalid job progress.');
    }
  }
  final num completed;
  final num? total;
  final String unit;

  factory JobProgress.fromJson(JsonMap json) => JobProgress(
        completed: json['completed'] as num,
        total: json['total'] as num?,
        unit: json['unit'] as String,
      );

  @override
  JsonMap toJson() =>
      {'completed': completed, if (total != null) 'total': total, 'unit': unit};
}

final class JobReceipt implements JsonEncodable {
  JobReceipt({required this.verification, required JsonMap details})
      : details = _freezeJson(details);
  final VerificationLevel verification;
  final JsonMap details;

  factory JobReceipt.fromJson(JsonMap json) => JobReceipt(
        verification:
            VerificationLevel.values.byName(json['verification'] as String),
        details: json['details'] as JsonMap,
      );

  @override
  JsonMap toJson() => {'verification': verification.name, 'details': details};
}

/// Immutable persisted snapshot. revision is the cursor used by task.wait.
final class Job implements JsonEncodable {
  Job({
    required this.jobId,
    required this.type,
    required this.title,
    required this.state,
    required this.phase,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
    required this.ownerDeviceId,
    required this.revision,
    JsonMap input = const {},
    JsonMap checkpoint = const {},
    JsonMap details = const {},
    JsonMap? origin,
    this.error,
    Decision? decision,
    this.receipt,
    this.retryAt,
    this.cancelRequestedAt,
    this.cancelRequestedPhase,
    this.cancelAfterCommit = false,
    this.sideEffectCommitted = false,
  })  : input = _freezeJson(input),
        checkpoint = _freezeJson(checkpoint),
        details = _freezeJson(details),
        origin = origin == null ? null : _freezeJson(origin),
        decision = decision == null
            ? null
            : _decodeDecision(_freezeJson(decision.toJson())) {
    if (jobId.isEmpty ||
        type.isEmpty ||
        title.isEmpty ||
        ownerDeviceId.isEmpty ||
        revision < 0 ||
        !createdAt.isUtc ||
        !updatedAt.isUtc ||
        (retryAt != null && !retryAt!.isUtc) ||
        (cancelRequestedAt != null && !cancelRequestedAt!.isUtc)) {
      throw ArgumentError('Invalid job identity, revision or timestamps.');
    }
    const reserved = {
      'jobId',
      'type',
      'title',
      'state',
      'phase',
      'progress',
      'createdAt',
      'updatedAt',
      'ownerDeviceId',
      'revision',
      'error',
      'decision',
      'receipt',
      'input',
      'checkpoint',
      'details',
      'origin',
      'retryAt',
      'cancelRequestedAt',
      'cancelRequestedPhase',
      'cancelAfterCommit',
      'sideEffectCommitted',
    };
    if (details.keys.any(reserved.contains)) {
      throw ArgumentError('Public details cannot shadow kernel fields.');
    }
    if ((state == JobState.needsDecision) != (this.decision != null) ||
        (state == JobState.waitingRetry) != (retryAt != null) ||
        (state == JobState.failed && error == null) ||
        state.isTerminal != (receipt != null)) {
      throw ArgumentError(
          'Job state requires matching decision, retry, error and receipt.');
    }
    if (state == JobState.succeeded &&
        receipt!.verification != VerificationLevel.verified) {
      throw ArgumentError('Success requires a verified receipt.');
    }
  }

  final String jobId, type, title, phase, ownerDeviceId;
  final JobState state;
  final JobProgress progress;
  final DateTime createdAt, updatedAt;
  final int revision;
  final JsonMap input, checkpoint, details;

  /// Who submitted the job, recorded at submission; null when not recorded.
  final JsonMap? origin;
  final Failure? error;
  final Decision? decision;
  final JobReceipt? receipt;
  final DateTime? retryAt, cancelRequestedAt;
  final String? cancelRequestedPhase;
  final bool sideEffectCommitted, cancelAfterCommit;

  /// Decodes the complete storage representation from toStorageJson().
  factory Job.fromJson(JsonMap json) => Job(
        jobId: json['jobId'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        state: JobState.values.singleWhere((s) => s.wireName == json['state']),
        phase: json['phase'] as String,
        progress: JobProgress.fromJson(json['progress'] as JsonMap),
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
        ownerDeviceId: json['ownerDeviceId'] as String,
        revision: json['revision'] as int,
        input: json['input'] as JsonMap,
        checkpoint: json['checkpoint'] as JsonMap,
        details: (json['details'] as JsonMap?) ?? const {},
        origin: json['origin'] as JsonMap?,
        error: json['error'] == null
            ? null
            : _decodeFailure(json['error'] as JsonMap),
        decision: json['decision'] == null
            ? null
            : _decodeDecision(json['decision'] as JsonMap),
        receipt: json['receipt'] == null
            ? null
            : JobReceipt.fromJson(json['receipt'] as JsonMap),
        retryAt: _date(json['retryAt']),
        cancelRequestedAt: _date(json['cancelRequestedAt']),
        cancelRequestedPhase: json['cancelRequestedPhase'] as String?,
        cancelAfterCommit: json['cancelAfterCommit'] as bool,
        sideEffectCommitted: json['sideEffectCommitted'] as bool,
      );

  late final JsonMap _json = Map<String, Object?>.unmodifiable({
    ...details,
    'jobId': jobId,
    'type': type,
    'title': title,
    'state': state.wireName,
    'phase': phase,
    'progress': _freezeJson(progress.toJson()),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'ownerDeviceId': ownerDeviceId,
    'revision': revision,
    if (origin != null) 'origin': origin,
    if (error != null) 'error': _freezeJson(error!.toJson()),
    if (decision != null) 'decision': _freezeJson(decision!.toJson()),
    // The receipt's details were frozen when it was made; copying them again
    // for every job's first toJson grows with a download's file list.
    if (receipt != null)
      'receipt': Map<String, Object?>.unmodifiable({
        ...receipt!.toJson(),
        if (cancelRequestedAt != null)
          'cancellation': Map<String, Object?>.unmodifiable({
            'requestedAt': cancelRequestedAt!.toIso8601String(),
            'phase': cancelRequestedPhase,
            'sideEffectCommitted': sideEffectCommitted,
            'afterCommit': cancelAfterCommit,
          }),
      }),
  });

  @override
  JsonMap toJson() => _json;

  /// Storage-only data is kept out of task action results.
  JsonMap toStorageJson() => {
        ...toJson(),
        'input': input,
        'checkpoint': checkpoint,
        'details': details,
        'sideEffectCommitted': sideEffectCommitted,
        'cancelAfterCommit': cancelAfterCommit,
        if (retryAt != null) 'retryAt': retryAt!.toIso8601String(),
        if (cancelRequestedAt != null)
          'cancelRequestedAt': cancelRequestedAt!.toIso8601String(),
        if (cancelRequestedPhase != null)
          'cancelRequestedPhase': cancelRequestedPhase,
      };
}

final class JobEvent implements JsonEncodable {
  JobEvent(
      {required this.jobId,
      required this.revision,
      required this.kind,
      required this.at,
      required JsonMap snapshot})
      : snapshot = _freezeJson(snapshot);
  final String jobId, kind;
  final int revision;
  final DateTime at;
  final JsonMap snapshot;
  @override
  JsonMap toJson() => {
        'jobId': jobId,
        'revision': revision,
        'kind': kind,
        'at': at.toIso8601String(),
        'snapshot': snapshot
      };
}

/// commit must atomically write the snapshot and event. expectedRevision=null
/// inserts; otherwise it must reject stale writes with Failure(conflict).
abstract interface class JobStore {
  Future<Job?> get(String jobId);
  Future<List<Job>> list({JobState? state, String? type});
  Future<void> commit(Job job, JobEvent event,
      {required int? expectedRevision});
  Future<List<JobEvent>> events(String jobId, {int afterRevision = -1});
  Future<void> close();
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toUtc();
Failure _decodeFailure(JsonMap json) => Failure(
      FailureCode.values.singleWhere((c) => c.wireName == json['code']),
      json['message'] as String,
      retryable: json['retryable'] as bool,
    );
Decision _decodeDecision(JsonMap json) => Decision(
      prompt: json['prompt'] as String,
      options: List.unmodifiable((json['options'] as List).map((value) {
        final option = value as JsonMap;
        final call = option['call'] as JsonMap;
        return DecisionOption(
            label: option['label'] as String,
            detail: option['detail'] as String?,
            call:
                ActionCall(call['action'] as String, call['input'] as JsonMap));
      })),
    );
JsonMap _freezeJson(JsonMap value) => _freezeValue(value) as JsonMap;
Object? _freezeValue(Object? value) => switch (value) {
      Map() when value.keys.every((k) => k is String) =>
        Map<String, Object?>.unmodifiable({
          for (final entry in value.entries)
            entry.key as String: _freezeValue(entry.value)
        }),
      List() => List<Object?>.unmodifiable(
          [for (final item in value) _freezeValue(item)]),
      null || bool() || int() || String() => value,
      double() when value.isFinite => value,
      _ => _freezeValue(jsonDecode(jsonEncode(value))),
    };
