import 'package:nipa_harness/nipa_harness.dart';

import 'registry.dart';

const _valueSchema = ObjectSchema({
  'key': StringSchema(),
  'revision': IntegerSchema(minimum: 0),
  'scope': StringSchema(values: ['user', 'device']),
  'apply': StringSchema(
      values: ['immediate', 'reload_player', 'reload_server', 'restart_app']),
  'provenance': ObjectSchema({}, nullable: true, additionalProperties: true),
  'effectiveState':
      StringSchema(values: ['same', 'differs', 'inactive', 'unknown']),
  'effectiveSource':
      StringSchema(values: ['live', 'startup', 'storage'], nullable: true),
  'effectiveReason': StringSchema(nullable: true),
  'effectiveDetail': StringSchema(nullable: true),
}, required: [
  'key',
  'value',
  'revision',
  'scope',
  'apply',
  'provenance',
  'effectiveState'
], additionalProperties: true);

const _rowSchema = ObjectSchema({}, additionalProperties: true);
const _keysSchema = ArraySchema(StringSchema(minLength: 1));
const _pageProperties = {
  'offset': IntegerSchema(minimum: 0),
  'limit': IntegerSchema(minimum: 1, maximum: 1000),
};
const _descriptionFields = [
  'key',
  'title',
  'description',
  'type',
  'enum',
  'enumNames',
  'format',
  'minimum',
  'maximum',
  'minLength',
  'pattern',
  'items',
  'properties',
  'required',
  'additionalProperties',
  'oneOf',
  'default',
  'scope',
  'apply',
  'effect',
  'readOnly',
  'step',
  'storage',
  'value',
  'revision',
  'provenance',
  'effective',
  'effectiveState',
  'effectiveSource',
  'effectiveReason',
  'effectiveDetail',
];
const _historyFields = [
  'key',
  'previousValue',
  'value',
  'changedAt',
  'changedBy',
  'origin',
  'reason',
  'invocationId',
  'revision',
];

final class SettingsCapability implements Capability {
  SettingsCapability(SettingsRegistry registry)
      : actions = [
          for (final verb in ['describe', 'get', 'set', 'reset', 'history'])
            _SettingsAction(registry, verb),
        ];
  @override
  final List<Action> actions;
}

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _SettingsAction extends Action<_Json, _Json> {
  _SettingsAction(this.registry, this.verb);
  final SettingsRegistry registry;
  final String verb;

  ObjectSchema get changeSchema => ObjectSchema({
        'key': const StringSchema(minLength: 1),
        'reason': const StringSchema(),
        'expectedRevision': const IntegerSchema(minimum: 0),
      }, required: [
        'key',
        if (verb == 'set') 'value'
      ], additionalProperties: verb == 'set');

  Map<String, Schema> get properties => switch (verb) {
        'describe' => {
            'domain': const StringSchema(),
            'keyword': const StringSchema(),
            'keys': _keysSchema,
            ..._pageProperties,
            'fields':
                const ArraySchema(StringSchema(values: _descriptionFields)),
          },
        'history' => {
            'key': const StringSchema(),
            'keys': _keysSchema,
            'from': const StringSchema(
                description: 'Inclusive ISO-8601 timestamp with timezone.'),
            'to': const StringSchema(
                description: 'Inclusive ISO-8601 timestamp with timezone.'),
            ..._pageProperties,
            'fields': const ArraySchema(StringSchema(values: _historyFields)),
          },
        'set' || 'reset' => {
            ...changeSchema.properties,
            'changes': ArraySchema(changeSchema),
          },
        _ => {'key': const StringSchema(), 'keys': _keysSchema},
      };

  @override
  ActionSpec get spec => ActionSpec(
        id: 'settings.$verb',
        title: 'Settings $verb',
        description: switch (verb) {
          'describe' =>
            'List locally visible setting contracts and values, each with the stored value and the effective value (fields as in get). Supports keys, domain, keyword, fields and offset/limit pagination.',
          'get' =>
            'Read key or keys with values, revisions, apply modes and latest provenance. value is the stored value. effective is the value in use while the application runs: effectiveState same, differs, inactive or unknown; effectiveSource live (read from the running component), startup (the stored value as the application started, for settings read only at start) or storage (no separate running value is observable; the setter that saves it is the one the running component uses). When state is differs, effectiveReason and effectiveDetail say why: restart_required, reload_required or runtime_adjusted (the player adjusted the value), speed_boost_active. inactive means the stored value is not in use and effective is null: overridden, inactive_dependency or kernel_unsupported, naming the other setting or kernel. unknown means the running value cannot be read and effective is null: applies_at_next_open, loaded_when_page_created, player_not_attached, no_runtime_probe or probe_failed. Batch results preserve input order and individual failures.',
          'set' =>
            'Save key/value or ordered changes using Classic setters. Each change has its own expectedRevision and reason. Batch results include revision, apply and individual failures; successful changes are not rolled back.',
          'reset' =>
            'Restore platform defaults for key or ordered changes with per-item revision checks, provenance and apply modes. Successful changes are not rolled back.',
          _ =>
            'Read append-only setting changes newest first, filtered by key or keys and inclusive from/to times, with fields and offset/limit pagination.',
        },
        effect: verb == 'set' || verb == 'reset' ? Effect.write : Effect.read,
        input: ObjectSchema(properties,
            oneOfRequired: switch (verb) {
              'get' => [
                  ['key'],
                  ['keys']
                ],
              'set' => [
                  ['key', 'value'],
                  ['changes']
                ],
              'reset' => [
                  ['key'],
                  ['changes']
                ],
              _ => [],
            },
            additionalProperties: verb == 'set'),
        output: switch (verb) {
          'describe' => const ObjectSchema({
              'settings': ArraySchema(_rowSchema),
              'nextOffset': IntegerSchema(minimum: 0, nullable: true),
            }, required: [
              'settings',
              'nextOffset'
            ]),
          'history' => const ObjectSchema({
              'changes': ArraySchema(_rowSchema),
              'nextOffset': IntegerSchema(minimum: 0, nullable: true),
            }, required: [
              'changes',
              'nextOffset'
            ]),
          _ => ObjectSchema({
              ..._valueSchema.properties,
              'results': const ArraySchema(_rowSchema),
            }, oneOfRequired: const [
              [
                'key',
                'value',
                'revision',
                'scope',
                'apply',
                'provenance',
                'effectiveState'
              ],
              ['results']
            ], additionalProperties: true),
        },
      );

  void _checkFields(JsonMap json, {bool change = false}) {
    final allowed = change ? changeSchema.properties : properties;
    final unknown = json.keys.where((key) =>
        !allowed.containsKey(key) && !(verb == 'set' && key == 'value'));
    if (unknown.isNotEmpty) {
      throw Failure(
          FailureCode.invalidInput, 'Unknown fields: ${unknown.join(', ')}');
    }
  }

  @override
  _Json decodeInput(JsonMap json) {
    _checkFields(json);
    if (json.containsKey('changes') &&
        (json.containsKey('reason') || json.containsKey('expectedRevision'))) {
      throw const Failure(FailureCode.invalidInput,
          'Batch reason and expectedRevision belong to each change.');
    }
    if (verb == 'history' &&
        json.containsKey('key') &&
        json.containsKey('keys')) {
      throw const Failure(FailureCode.invalidInput, 'Use key or keys.');
    }
    return _Json(json);
  }

  Future<JsonMap> _change(JsonMap json, Invocation invocation) {
    _checkFields(json, change: true);
    return registry.set(json['key'] as String, json['value'], invocation,
        reason: json['reason'] as String?,
        expectedRevision: (json['expectedRevision'] as num?)?.toInt(),
        reset: verb == 'reset');
  }

  Future<JsonMap> _item(JsonMap json, int index, Invocation invocation) async {
    try {
      final value = verb == 'get'
          ? await registry.get(json['key'] as String)
          : await _change(json, invocation);
      return {'index': index, 'status': 'completed', ...value};
    } on Failure catch (failure) {
      return {
        'index': index,
        'key': json['key'],
        'status': 'failed',
        'error': Failure(failure.code, failure.message,
            retryable: failure.retryable,
            violations: [
              for (final violation in failure.violations)
                SchemaViolation(
                    '/changes/$index/value${violation.path == '/value' ? '' : violation.path}',
                    violation.message),
            ]).toJson()
      };
    } catch (error) {
      return {
        'index': index,
        'key': json['key'],
        'status': 'failed',
        'error':
            Failure(FailureCode.internal, 'Setting operation failed: $error')
                .toJson()
      };
    }
  }

  DateTime? _time(JsonMap json, String field) {
    final value = json[field] as String?;
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc) {
      throw Failure(FailureCode.invalidInput,
          '$field requires an ISO-8601 timestamp with timezone.');
    }
    return parsed;
  }

  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final json = input.value;
    if (verb == 'describe' || verb == 'history') {
      final offset = (json['offset'] as num?)?.toInt() ?? 0;
      final limit =
          (json['limit'] as num?)?.toInt() ?? (verb == 'describe' ? 1000 : 50);
      final keys = (json['keys'] as List?)?.cast<String>();
      final from = _time(json, 'from'), to = _time(json, 'to');
      if (from != null && to != null && from.isAfter(to)) {
        throw const Failure(
            FailureCode.invalidInput, 'from must not be after to.');
      }
      final rows = verb == 'describe'
          ? await registry.describe(
              domain: json['domain'] as String?,
              keyword: json['keyword'] as String?,
              keys: keys,
              offset: offset,
              limit: limit + 1)
          : await registry.history(
              key: json['key'] as String?,
              keys: keys,
              from: from,
              to: to,
              offset: offset,
              limit: limit);
      final hasMore = verb == 'describe'
          ? rows.length > limit
          : rows.length == limit &&
              (await registry.history(
                      key: json['key'] as String?,
                      keys: keys,
                      from: from,
                      to: to,
                      offset: offset + limit,
                      limit: 1))
                  .isNotEmpty;
      final fields = (json['fields'] as List?)?.cast<String>();
      return Completed(_Json({
        verb == 'describe' ? 'settings' : 'changes': [
          for (final row in rows.take(limit))
            if (fields == null)
              row
            else
              {
                for (final field in fields)
                  if (row.containsKey(field)) field: row[field],
              },
        ],
        'nextOffset': hasMore ? offset + limit : null,
      }));
    }
    if (json.containsKey('keys') || json.containsKey('changes')) {
      final changes = verb == 'get'
          ? [
              for (final key in json['keys'] as List)
                <String, Object?>{'key': key}
            ]
          : (json['changes'] as List).cast<JsonMap>();
      return Completed(_Json({
        'results': [
          for (var i = 0; i < changes.length; i++)
            await _item(changes[i], i, invocation),
        ]
      }));
    }
    return Completed(_Json(verb == 'get'
        ? await registry.get(json['key'] as String)
        : await _change(json, invocation)));
  }
}
