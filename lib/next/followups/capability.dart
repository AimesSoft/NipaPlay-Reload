import 'package:nipa_harness/nipa_harness.dart';

import '../harness_hooks.dart';
import 'service.dart';

final class FollowupCapability implements Capability {
  FollowupCapability(Followups service)
      : actions = [
          _FollowupAction(service, 'register'),
          _FollowupAction(service, 'list'),
          _FollowupAction(service, 'cancel'),
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

final class _FollowupAction extends Action<_Json, _Json> {
  const _FollowupAction(this.service, this.operation);
  final Followups service;
  final String operation;
  @override
  ActionSpec get spec => ActionSpec(
        id: 'followup.$operation',
        title: switch (operation) {
          'register' => '登记任务结束或事件发生后的 Agent 后续',
          'cancel' => '取消尚未执行的后续',
          _ => '查询后续与等待条件',
        },
        description: switch (operation) {
          'register' =>
            'Persist a one-shot followup and end this turn without waiting for the background task. '
                'when.jobId wakes you on any terminal state (succeeded/failed/cancelled), with the receipt. '
                'Alternatively when.event awaits the next hook event, optionally for objectId. '
                'instruction says what to consider next; title is a short progress label. '
                'Defaults to this embedded chat thread via NIPAPLAY_CHAT; outside chat, omit threadId to create a new thread in the active harness. '
                'An active turn is never interrupted. Host unavailability remains visible in state.query followups.',
          'cancel' =>
            'Cancel waiting, ready or failed delivery; does not interrupt an already started turn.',
          _ =>
            'List durable followups, actual thread/turn IDs, trigger facts and delivery errors. Also query the followups state view.',
        },
        effect: operation == 'list' ? Effect.read : Effect.write,
        input: switch (operation) {
          'register' => ObjectSchema({
              'when': ObjectSchema({
                'jobId': const StringSchema(minLength: 1),
                'event': StringSchema(values: HarnessHooks.events.toList()),
                'objectId': const StringSchema(minLength: 1),
              }),
              'instruction': const StringSchema(minLength: 1),
              'title': const StringSchema(minLength: 1),
              'threadId': const StringSchema(minLength: 1),
            }, required: const [
              'when',
              'instruction'
            ]),
          'cancel' => const ObjectSchema({'id': StringSchema(minLength: 1)},
              required: ['id']),
          _ => const ObjectSchema({}),
        },
        output: operation == 'list'
            ? const ObjectSchema({'followups': ArraySchema(followupFields)},
                required: ['followups'])
            : const ObjectSchema({'followup': followupFields},
                required: ['followup']),
      );
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async =>
      Completed(_Json(switch (operation) {
        'register' => {
            'followup': await service.register(input.value, invocation)
          },
        'cancel' => {
            'followup':
                await service.cancel(input.value['id'] as String, invocation)
          },
        _ => {'followups': await service.list()},
      }));
}
