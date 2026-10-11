import 'package:nipa_harness/nipa_harness.dart';

import 'service.dart';

const _text = StringSchema(minLength: 1);
const _ref = StringSchema(minLength: 1);
const _card = ObjectSchema({
  'kind': StringSchema(
      values: ['work', 'episode', 'candidates', 'preparation', 'task']),
  'workId': _ref,
  'episodeId': _ref,
  'taskId': _ref,
  'title': _text,
  'items': ArraySchema(
    ObjectSchema({'workId': _ref, 'reason': _text}, required: ['workId']),
  ),
  'steps': ArraySchema(
    ObjectSchema({
      'label': _text,
      'detail': _text,
      'entityId': _ref,
      'taskId': _ref,
      'followupId': _ref
    }, required: [
      'label'
    ]),
  ),
}, required: [
  'kind'
]);

final class UiDataCapability implements Capability {
  UiDataCapability(UiDataService service)
      : actions = [
          _UiAction(service, 'present'),
          _UiAction(service, 'shelves.put'),
          _UiAction(service, 'shelves.remove')
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

final class _UiAction extends Action<_Json, _Json> {
  const _UiAction(this.service, this.operation);
  final UiDataService service;
  final String operation;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'ui.$operation',
      title: switch (operation) {
        'present' => '把卡片放到当前对话',
        'shelves.put' => '把作品放到首页',
        _ => '从首页移除作品'
      },
      description: switch (operation) {
        'present' =>
          'Append cards to your current NIPAPLAY_CHAT turn. kind=work uses workId; episode uses episodeId; task uses taskId (jobId); candidates uses items:[{workId,reason?}]; preparation uses title, optional workId and steps:[{label,detail?, exactly one entityId/taskId/followupId}]. All references must exist. States/progress are resolved live; do not supply them. Viewer text is a natural short sentence without IDs or process details.',
        'shelves.put' =>
          'Replace hero (zero or one item, optional note) or an Agent shelf (stable id, title, items). items:[{workId,note?}]. Empty items removes the placement. Shelf item note becomes its caption. Reference existing library.works IDs; viewer text contains no IDs, paths, source chains or debugging details.',
        _ =>
          'Remove a whole Agent shelf/hero by id, or a single workId from it. UiShelf.id is the shelf id. A GUI-origin removal is recorded in activity as a user action.'
      },
      effect: Effect.write,
      input: switch (operation) {
        'present' => const ObjectSchema({'cards': ArraySchema(_card)},
            required: ['cards']),
        'shelves.put' => const ObjectSchema({
            'placement': StringSchema(values: ['hero', 'shelf']),
            'id': _ref,
            'title': _text,
            'note': _text,
            'items': ArraySchema(ObjectSchema({'workId': _ref, 'note': _text},
                required: ['workId']))
          }, required: [
            'placement',
            'items'
          ]),
        _ => const ObjectSchema({'id': _ref, 'workId': _ref}, required: ['id'])
      },
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    if (operation == 'shelves.remove') {
      await service.removeShelf(input.value['id'] as String,
          workId: input.value['workId'] as String?, invocation: invocation);
      return Completed(_Json({'id': input.value['id'], 'removed': true}));
    }
    return Completed(_Json(operation == 'present'
        ? await service.present(input.value, invocation)
        : await service.putShelf(input.value, invocation)));
  }
}
