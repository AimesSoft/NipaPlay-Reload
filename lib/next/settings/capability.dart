import 'package:nipa_harness/nipa_harness.dart';

import 'registry.dart';

const _changeSchema = ObjectSchema({
  'key': StringSchema(),
  'changedAt': StringSchema(),
  'changedBy': StringSchema(),
  'origin': StringSchema(),
  'reason': StringSchema(nullable: true),
  'invocationId': StringSchema(),
  'revision': IntegerSchema(minimum: 1),
}, required: [
  'key',
  'changedAt',
  'changedBy',
  'origin',
  'reason',
  'invocationId',
  'revision',
  'value',
  'previousValue'
], additionalProperties: true);

const _valueSchema = ObjectSchema({
  'key': StringSchema(),
  'revision': IntegerSchema(minimum: 0),
  'scope': StringSchema(values: ['user', 'device']),
  'apply': StringSchema(
      values: ['immediate', 'reload_player', 'reload_server', 'restart_app']),
  'provenance': ObjectSchema({}, nullable: true, additionalProperties: true),
}, required: [
  'key',
  'value',
  'revision',
  'scope',
  'apply',
  'provenance'
], additionalProperties: true);

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

  Map<String, Schema> get properties => switch (verb) {
        'describe' => {
            'domain': const StringSchema(),
            'keyword': const StringSchema(),
          },
        'history' => {
            'key': const StringSchema(),
            'limit': const IntegerSchema(minimum: 1, maximum: 1000),
          },
        'set' || 'reset' => {
            'key': const StringSchema(),
            'reason': const StringSchema(),
            'expectedRevision': const IntegerSchema(minimum: 0),
          },
        _ => {'key': const StringSchema()},
      };

  @override
  ActionSpec get spec => ActionSpec(
        id: 'settings.$verb',
        title: 'Settings $verb',
        description: switch (verb) {
          'describe' =>
            'List locally visible settings, contracts and current values; filter by domain or keyword.',
          'get' =>
            'Read a setting, revision, apply mode and latest provenance.',
          'set' =>
            'Validate and save value using the Classic setter. Optional expectedRevision guards concurrent edits. Reason is descriptive only. Does not restart the app.',
          'reset' =>
            'Restore the platform default, with the same provenance and revision checks as set.',
          _ =>
            'Read append-only setting changes for a key or recent changes, newest first.',
        },
        effect: verb == 'set' || verb == 'reset' ? Effect.write : Effect.read,
        input: ObjectSchema(properties,
            required: switch (verb) {
              'describe' || 'history' => [],
              'set' => ['key', 'value'],
              _ => ['key'],
            },
            // The kernel has no union/any schema; the selected setting validates value.
            additionalProperties: verb == 'set'),
        output: switch (verb) {
          'describe' => const ObjectSchema(
              {'settings': ArraySchema(_valueSchema)},
              required: ['settings']),
          'history' => const ObjectSchema(
              {'changes': ArraySchema(_changeSchema)},
              required: ['changes']),
          _ => _valueSchema,
        },
      );

  @override
  _Json decodeInput(JsonMap json) {
    final unknown = json.keys.where((key) =>
        !properties.containsKey(key) && !(verb == 'set' && key == 'value'));
    if (unknown.isNotEmpty) {
      throw Failure(
          FailureCode.invalidInput, 'Unknown fields: ${unknown.join(', ')}');
    }
    return _Json(json);
  }

  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final json = input.value;
    return Completed(_Json(switch (verb) {
      'describe' => {
          'settings': await registry.describe(
              domain: json['domain'] as String?,
              keyword: json['keyword'] as String?)
        },
      'get' => await registry.get(json['key'] as String),
      'set' || 'reset' => await registry.set(
          json['key'] as String, json['value'], invocation,
          reason: json['reason'] as String?,
          expectedRevision: (json['expectedRevision'] as num?)?.toInt(),
          reset: verb == 'reset'),
      _ => {
          'changes': await registry.history(
              key: json['key'] as String?,
              limit: (json['limit'] as num?)?.toInt() ?? 50)
        },
    }));
  }
}
