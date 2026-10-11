import 'package:nipa_harness/nipa_harness.dart';

import '../harness_hooks.dart';
import 'service.dart';

final class FollowupCapability implements Capability {
  FollowupCapability(Followups service)
      : actions = [
          _FollowupAction(service, 'register'),
          _FollowupAction(service, 'list'),
          _FollowupAction(service, 'cancel'),
          _FollowupAction(service, 'wake'),
          _FollowupAction(service, 'discover'),
          for (final operation in ['main', 'new', 'list', 'switch'])
            _SessionAction(service, operation),
        ];
  @override
  final List<Action> actions;
}

final class _SessionAction extends Action<_Json, _Json> {
  const _SessionAction(this.service, this.operation);
  final Followups service;
  final String operation;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'chat.session.$operation',
      title: '会话 $operation',
      description:
          'Codex sessions in the active harness. main selects the durable main thread; '
          'new explicitly creates another conversation; list marks main/current; switch selects threadId. '
        'Selection is rejected while busy; transcripts belong to Codex.',
      effect: operation == 'list' ? Effect.read : Effect.write,
      input: ObjectSchema({
        'threadId': const StringSchema(minLength: 1),
        'cursor': const StringSchema(),
      }, required: operation == 'switch' ? const ['threadId'] : const []),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap input) => _Json(input);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async =>
      Completed(_Json(await service.session(operation,
          threadId: input.value['threadId'] as String?,
          cursor: input.value['cursor'] as String?)));
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
        id: operation == 'wake'
            ? 'agent.wake'
            : operation == 'discover'
                ? 'activity.report'
                : 'followup.$operation',
        title: switch (operation) {
          'register' => '登记任务结束或事件发生后的 Agent 后续',
          'cancel' => '取消尚未执行的后续',
          'wake' => '唤醒 Agent 的主会话或指定会话',
          'discover' => '记录有来源的发现',
          _ => '查询后续与等待条件',
        },
        description: switch (operation) {
          'register' =>
            'Persist a one-shot followup and end this turn without waiting for the background task. '
                'when.jobId wakes you on any terminal state (succeeded/failed/cancelled), with the receipt. '
                'Alternatively when.event awaits the next hook event, optionally for objectId. '
                'instruction says what to consider next; title is a short progress label. '
                'Defaults to this embedded chat thread via NIPAPLAY_CHAT; outside chat, omit threadId to return to the main thread of the active harness. '
                'An active turn is never interrupted. Host unavailability remains visible in state.query followups.',
          'cancel' =>
            'Cancel waiting, ready or failed delivery; does not interrupt an already started turn.',
          'wake' =>
            'Queue a new Agent turn with instruction and trigger facts. Defaults to the main thread even when called from another conversation; optional threadId targets that conversation. Busy turns are never interrupted. Uses the durable followup dispatcher.',
          'discover' =>
            'Record a discovery with a source and arbitrary facts in activity. Does not wake the Agent. Source is supplied evidence; origin records the actual caller.',
          _ =>
            'List durable followups, actual thread/turn IDs, trigger facts and delivery errors. Also query the followups state view.',
        },
        effect: operation == 'list' ? Effect.read : Effect.write,
        input: switch (operation) {
          'wake' => const ObjectSchema({
              'instruction': StringSchema(minLength: 1),
              'title': StringSchema(minLength: 1),
              'threadId': StringSchema(minLength: 1),
              'facts': ObjectSchema({}, additionalProperties: true),
            }, required: [
              'instruction',
              'facts'
            ]),
          'discover' => const ObjectSchema({
              'title': StringSchema(minLength: 1),
              'source': StringSchema(minLength: 1),
              'facts': ObjectSchema({}, additionalProperties: true),
            }, required: [
              'title',
              'source',
              'facts'
            ]),
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
        output: operation == 'discover'
            ? const ObjectSchema({}, additionalProperties: true)
            : operation == 'list'
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
        'wake' => {'followup': await service.wake(input.value, invocation)},
        'discover' => await service.discover(input.value, invocation),
        _ => {'followups': await service.list()},
      }));
}
