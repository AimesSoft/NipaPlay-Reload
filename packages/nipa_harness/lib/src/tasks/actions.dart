part of '../kernel.dart';

final class TaskCapability implements Capability {
  TaskCapability(TaskEngine engine)
      : actions = [
          for (final operation in ['list', 'get', 'wait', 'cancel'])
            _TaskAction(engine, operation),
        ];
  @override
  final List<Action> actions;
}

final class _TaskInput implements JsonEncodable {
  const _TaskInput(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _TaskOutput implements JsonEncodable {
  const _TaskOutput(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _TaskAction extends Action<_TaskInput, _TaskOutput> {
  _TaskAction(this.engine, this.operation);
  final TaskEngine engine;
  final String operation;

  @override
  ActionSpec get spec => ActionSpec(
        id: 'task.$operation',
        title: '${operation[0].toUpperCase()}${operation.substring(1)} task',
        description: switch (operation) {
          'list' =>
            'List persisted task snapshots, optionally filtering by state or type.',
          'get' =>
            'Read the complete task snapshot. succeeded means verification finished; '
                'use receipt for verified results. needs_decision contains executable option calls.',
          'wait' => 'Wait for a terminal state, a state/phase/decision change after afterRevision, or timeout. '
              'Progress alone does not wake the wait unless includeProgress is true. '
              'timeoutMs defaults to 60000 and is bounded to 0–60000. Without afterRevision, '
              'wait for the next meaningful change. Pass the last snapshot revision to avoid missing changes '
              'between calls. Returns the current job; use repeated bounded waits for long tasks.',
          _ =>
            'Request cancellation for jobId or jobIds and return accepted snapshots with individual batch failures. cancelling is not '
                'confirmation of stopping. Committed effects are still verified and recorded in receipt. Does not remove downloads or delete files.',
        },
        effect: operation == 'cancel' ? Effect.write : Effect.read,
        input: operation == 'list'
            ? ObjectSchema({
                'state': StringSchema(
                    values: [for (final s in JobState.values) s.wireName]),
                'type': const StringSchema(minLength: 1),
              })
            : ObjectSchema({
                'jobId': const StringSchema(minLength: 1),
                if (operation == 'cancel')
                  'jobIds': const ArraySchema(StringSchema(minLength: 1)),
                if (operation == 'wait') ...{
                  'afterRevision': const IntegerSchema(minimum: 0),
                  'timeoutMs': const IntegerSchema(minimum: 0, maximum: 60000),
                  'includeProgress': const BooleanSchema(),
                },
              },
                required: [
                    if (operation != 'cancel') 'jobId'
                  ],
                oneOfRequired: operation == 'cancel'
                    ? const [
                        ['jobId'],
                        ['jobIds']
                      ]
                    : const []),
        output: operation == 'list'
            ? ObjectSchema({'jobs': ArraySchema(jobSnapshotSchema)},
                required: const ['jobs'])
            : ObjectSchema({
                'job': jobSnapshotSchema,
                if (operation == 'cancel')
                  'results': ArraySchema(ObjectSchema({
                    'index': const IntegerSchema(minimum: 0),
                    'jobId': const StringSchema(),
                    'status':
                        const StringSchema(values: ['completed', 'failed']),
                    'job': jobSnapshotSchema,
                    'error': const ObjectSchema({}, additionalProperties: true),
                  }, required: const [
                    'index',
                    'jobId',
                    'status'
                  ], oneOfRequired: const [
                    ['job'],
                    ['error']
                  ])),
              },
                required: [
                    if (operation != 'cancel') 'job'
                  ],
                oneOfRequired: operation == 'cancel'
                    ? const [
                        ['job'],
                        ['results']
                      ]
                    : const []),
      );

  @override
  _TaskInput decodeInput(JsonMap json) => _TaskInput(json);

  @override
  Future<Outcome<_TaskOutput>> run(
      _TaskInput input, Invocation invocation) async {
    final json = input.json;
    if (operation == 'list') {
      final state = json['state'] as String?;
      final jobs = await engine.list(
          type: json['type'] as String?,
          state: state == null
              ? null
              : JobState.values.singleWhere((s) => s.wireName == state));
      return Completed(_TaskOutput({
        'jobs': [for (final job in jobs) job.toJson()]
      }));
    }
    if (operation == 'cancel' && json.containsKey('jobIds')) {
      final ids = (json['jobIds'] as List).cast<String>();
      final results = <JsonMap>[];
      for (var i = 0; i < ids.length; i++) {
        final identity = {'index': i, 'jobId': ids[i]};
        try {
          results.add({
            ...identity,
            'status': 'completed',
            'job': (await engine.cancel(ids[i])).toJson()
          });
        } on Failure catch (failure) {
          results.add(
              {...identity, 'status': 'failed', 'error': failure.toJson()});
        } catch (error) {
          results.add({
            ...identity,
            'status': 'failed',
            'error':
                Failure(FailureCode.internal, 'Cancellation failed: $error')
                    .toJson()
          });
        }
      }
      return Completed(_TaskOutput({'results': results}));
    }
    final id = json['jobId'] as String;
    final job = switch (operation) {
      'wait' => await engine.wait(id,
          afterRevision: (json['afterRevision'] as num?)?.toInt(),
          includeProgress: json['includeProgress'] as bool? ?? false,
          timeout: Duration(
              milliseconds: (json['timeoutMs'] as num?)?.toInt() ?? 60000)),
      'cancel' => await engine.cancel(id),
      _ => await engine.get(id),
    };
    return Completed(_TaskOutput({'job': job.toJson()}));
  }
}

final jobSnapshotSchema = ObjectSchema({
  'jobId': const StringSchema(),
  'type': const StringSchema(),
  'title': const StringSchema(),
  'state': StringSchema(values: [for (final s in JobState.values) s.wireName]),
  'phase': const StringSchema(),
  'progress': const ObjectSchema({
    'completed': NumberSchema(minimum: 0),
    'total': NumberSchema(minimum: 0),
    'unit': StringSchema()
  }, required: [
    'completed',
    'unit'
  ]),
  'createdAt': const StringSchema(),
  'updatedAt': const StringSchema(),
  'ownerDeviceId': const StringSchema(),
  'revision': const IntegerSchema(minimum: 0),
  'error': const ObjectSchema({
    'code': StringSchema(),
    'message': StringSchema(),
    'retryable': BooleanSchema()
  }, required: [
    'code',
    'message',
    'retryable'
  ]),
  'decision': const ObjectSchema({
    'prompt': StringSchema(),
    'options': ArraySchema(ObjectSchema({
      'label': StringSchema(),
      'detail': StringSchema(),
      'call': ObjectSchema(
          {'action': StringSchema(), 'input': _TaskJsonSchema()},
          required: ['action', 'input'])
    }, required: [
      'label',
      'call'
    ]))
  }, required: [
    'prompt',
    'options'
  ]),
  'receipt': const ObjectSchema({
    'verification':
        StringSchema(values: ['verified', 'acknowledged', 'unverified']),
    'details': _TaskJsonSchema(),
    'cancellation': ObjectSchema({
      'requestedAt': StringSchema(),
      'phase': StringSchema(),
      'sideEffectCommitted': BooleanSchema(),
      'afterCommit': BooleanSchema()
    }, required: [
      'requestedAt',
      'phase',
      'sideEffectCommitted',
      'afterCommit'
    ]),
  }, required: [
    'verification',
    'details'
  ]),
}, required: const [
  'jobId',
  'type',
  'title',
  'state',
  'phase',
  'progress',
  'createdAt',
  'updatedAt',
  'ownerDeviceId',
  'revision'
], additionalProperties: true);

/// Domain receipts and option inputs have type-specific JSON contracts.
final class _TaskJsonSchema extends Schema {
  const _TaskJsonSchema();
}
