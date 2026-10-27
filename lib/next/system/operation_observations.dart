import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import '../harness_redaction.dart';
import '../capabilities/classic_action.dart';

/// Process observations, correlated with the durable invocation/job/commit IDs.
/// Missing observations never prove that an operation did not execute.
final class OperationObservations {
  OperationObservations(
      {this.capacity = 512,
      this.ttl = const Duration(minutes: 30),
      DateTime Function()? clock})
      : assert(capacity > 0),
        _clock = clock ?? DateTime.now;
  static final current = OperationObservations();
  final int capacity;
  final Duration ttl;
  final DateTime Function() _clock;
  final _records = <String, JsonMap>{};
  int _sequence = 0;
  int _discardedThrough = 0;
  late final String session =
      'process-${_clock().toUtc().microsecondsSinceEpoch}';

  void _expire() {
    final cutoff = _clock().subtract(ttl);
    _records.removeWhere((_, row) {
      final expired =
          DateTime.parse(row['updatedAt'] as String).isBefore(cutoff);
      if (expired) _discarded(row);
      return expired;
    });
  }

  void _discarded(JsonMap row) {
    final sequence = row['sequence'] as int;
    if (sequence > _discardedThrough) _discardedThrough = sequence;
  }

  void record(String key, String stage, JsonMap facts) {
    _expire();
    final old = _records.remove(key);
    while (_records.length >= capacity) {
      _discarded(_records.remove(_records.keys.first)!);
    }
    final at = _clock().toUtc().toIso8601String();
    // Only schema-selected facts enter here; never parameters, URLs or tokens.
    final safe = publicHarnessFacts(facts) as JsonMap;
    final bounded = utf8.encode(jsonEncode(safe)).length <= 8192
        ? safe
        : <String, Object?>{'factsOmitted': 'size_limit'};
    final stages = <Object?>[
      ...?old?['stages'] as List?,
      {'stage': stage, 'at': at}
    ];
    _records[key] = {
      ...?old,
      ...bounded,
      'key': key,
      'stage': stage,
      'sequence': ++_sequence,
      'startedAt': old?['startedAt'] ?? at,
      'updatedAt': at,
      'stages': stages.length > 12 ? stages.sublist(stages.length - 12) : stages
    };
  }

  JsonMap read(JsonMap input) {
    _expire();
    final sessionChanged =
        input['session'] != null && input['session'] != session;
    final after = sessionChanged ? 0 : input['after'] as int? ?? 0;
    final rows = _records.values
        .where((row) =>
            (input['invocationId'] == null ||
                row['invocationId'] == input['invocationId'] ||
                row['parentInvocationId'] == input['invocationId']) &&
            (input['peerId'] == null || row['peerId'] == input['peerId']) &&
            (input['action'] == null || row['action'] == input['action']) &&
            (input['jobId'] == null || row['jobId'] == input['jobId']) &&
            (input['commitId'] == null ||
                row['commitId'] == input['commitId']) &&
            (input['requestKey'] == null ||
                row['previewId'] == input['requestKey'] ||
                row['requestId'] == input['requestKey'] ||
                row['requestKey'] == input['requestKey']) &&
            (row['sequence'] as int) > after)
        .toList();
    final limit = (input['limit'] as int? ?? 50).clamp(1, 100);
    final selected = rows.take(limit).toList();
    return {
      'session': session,
      'scope': 'current_process',
      'sessionChanged': sessionChanged,
      'historyGap': sessionChanged || after < _discardedThrough,
      'observedAt': _clock().toUtc().toIso8601String(),
      'retention': {
        'maxRecords': capacity,
        'maxAgeSeconds': ttl.inSeconds,
        'maxStagesPerRecord': 12
      },
      'records': selected,
      'truncated': rows.length > limit,
      'next': rows.length > limit ? selected.last['sequence'] : _sequence,
      'absenceMeans': 'unknown',
      'coverage': {
        'capabilities': 'execution_after_input_validation',
        'mesh': 'control_requests_and_bulk_read_failures',
        'domainSubsteps': 'only_where_explicitly_instrumented',
        'transactionCommit': 'query_owner_domain_receipt',
        'inputValidationFailures': 'query_invocation_journal',
        'durableHistory': false,
      },
      'commitEvidence':
          'Use db.receipt, merge receipts or task status on the owning device. A transport or action outcome alone is not a transaction receipt.'
    };
  }

  static JsonMap references(JsonMap value) => {
        for (final key in const [
          'previewId',
          'requestId',
          'requestKey',
          'commitId',
          'jobId',
          'entityId',
          'fileId',
          'episodeId'
        ])
          if (value[key] is String && (value[key] as String).length <= 256)
            key: value[key],
      };

  static JsonMap failure(Failure value) => {
        'failureCode': value.code.wireName,
        'retryable': value.retryable,
        for (final key in const [
          'reason',
          'stage',
          'execution',
          'invocationId'
        ])
          if (value.details[key] is String)
            switch (key) {
              'stage' => 'failureStage',
              'invocationId' => 'failureInvocationId',
              _ => key,
            }: value.details[key],
      };
}

/// Shared by graphical and headless hosts; querying observations is itself
/// excluded from observation so polling cannot evict the evidence it reads.
final class OperationObservationsCapability implements Capability {
  const OperationObservationsCapability();
  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'diagnostics.operations',
                title: '查询调用过程与关联标识',
                description:
                    '查询当前进程能力执行与 Mesh 阶段；按 invocationId、action、peerId、jobId、commitId 或原请求键 requestKey 筛选。分页携 session 和 after=next；sessionChanged 或 historyGap 表示历史不连续。最多 512 条、30 分钟、每条 12 个阶段，不含原始参数和凭据。缺失表示未知，action_completed 不证明提交，发送响应不证明对端收到。持久提交查源设备 db.receipt，长期任务查 task。查询本身不进入过程记录。',
                effect: Effect.read,
                input: ObjectSchema({
                  'invocationId': StringSchema(minLength: 1, maxLength: 256),
                  'action': StringSchema(minLength: 1, maxLength: 256),
                  'peerId': StringSchema(minLength: 1, maxLength: 256),
                  'jobId': StringSchema(minLength: 1, maxLength: 256),
                  'commitId': StringSchema(minLength: 1, maxLength: 256),
                  'requestKey': StringSchema(minLength: 1, maxLength: 256),
                  'session': StringSchema(minLength: 1, maxLength: 256),
                  'after': IntegerSchema(minimum: 0),
                  'limit': IntegerSchema(minimum: 1, maximum: 100),
                }),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) async => OperationObservations.current.read(input)),
      ];
}
