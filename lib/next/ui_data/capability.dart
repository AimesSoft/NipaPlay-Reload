import 'package:nipa_harness/nipa_harness.dart';

import 'service.dart';
import 'metadata_facts.dart';
import '../capabilities/classic_action.dart';

const _text = StringSchema(minLength: 1);
const _ref = StringSchema(minLength: 1);

/// A work outside the library, as media.metadata.search/get return it.
const _workRef = ObjectSchema({
  'provider': StringSchema(values: ['tmdb', 'bangumi', 'dandanplay']),
  'objectType': StringSchema(values: ['tv', 'movie', 'subject', 'anime']),
  'externalId': _ref,
  'scope': StringSchema(
      values: [''], description: 'A work has no scope: "" or omitted.'),
}, required: [
  'provider',
  'objectType',
  'externalId'
], description: 'tmdb tv/movie, bangumi subject or dandanplay anime.');
const _card = ObjectSchema({
  'kind': StringSchema(
      values: ['work', 'episode', 'candidates', 'preparation', 'task', 'choices']),
  'workId': _ref,
  'ref': _workRef,
  'episodeId': _ref,
  'taskId': _ref,
  'title': _text,
  'items': ArraySchema(
    ObjectSchema({'workId': _ref, 'ref': _workRef, 'reason': _text},
        oneOfRequired: [
          ['workId'],
          ['ref']
        ]),
  ),
  'question': _text,
  'options': ArraySchema(
    ObjectSchema({'label': _text, 'detail': _text, 'recommended': BooleanSchema()},
        required: ['label']),
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
          _UiAction(service, 'shelves.remove'),
          _MetadataAction(service, false),
          _MetadataAction(service, true)
          , ClassicAction(const ActionSpec(
              id: 'media.artwork.clear', title: '清除图片覆盖',
              description: 'Atomically clear explicit artwork overrides and reveal the source artwork. Keeps cached/local copies and edit provenance. Does not delete disk files.',
              effect: Effect.write, input: ObjectSchema({'entries': ArraySchema(ObjectSchema({
                'entityId': _ref, 'kind': StringSchema(values: ['backdrop','poster','logo','still'])
              }, required: ['entityId','kind']))}, required: ['entries']),
              output: ObjectSchema({}, additionalProperties: true)), (input, invocation) async {
                final entries = (input['entries'] as List).cast<JsonMap>();
                for(final e in entries) {
                  final entity = await service.media.store.entity(e['entityId'] as String);
                  if(entity['kind'] != (e['kind'] == 'still' ? 'episode' : 'work')) {
                    throw const Failure(FailureCode.invalidInput, 'Artwork kind does not match entity kind.');
                  }
                }
                await service.media.store.overrideFields([for(final e in entries)
                  {'entityId':e['entityId'], 'field':'artwork.${e['kind']}', 'value':null, 'mode':'clear'}], invocation);
                return {'atomic':true, 'entries':[for(final e in entries) {...e,'cleared':true,'copyRetained':true}]};
              }),
          ClassicAction(const ActionSpec(
              id: 'media.metadata.ui_facts_batch', title: '批量读取资料完整情况',
              description: 'Read the same metadata facts for multiple works. Each item returns facts or a structured failure; atomic:false.',
              effect: Effect.read, input: ObjectSchema({'workIds': ArraySchema(_ref)}, required: ['workIds']),
              output: ObjectSchema({}, additionalProperties: true)), (input, _) async {
                final results = <JsonMap>[];
                for(final id in (input['workIds'] as List).cast<String>()) {
                  try { results.add({'workId':id,'facts':await service.metadataFacts(id)}); }
                  on Failure catch(e) { results.add({'workId':id,'error':e.toJson()}); }
                }
                return {'atomic':false,'entries':results};
              })
        ];
  @override
  final List<Action> actions;
}

final class _MetadataAction extends Action<_Json, _Json> {
  const _MetadataAction(this.service, this.write);
  final UiDataService service;
  final bool write;
  @override
  ActionSpec get spec => ActionSpec(
      id: write ? 'media.artwork.set' : 'media.metadata.ui_facts',
      title: write ? '设置作品与剧集图片' : '读取界面元数据完整情况',
      description: write
          ? 'Set independent persistent artwork overrides in one atomic batch. backdrop/poster/logo require entityId of a work; still requires an episode. Each entry supplies exactly one HTTP(S) url without userinfo or absolute local file, plus source:{label,url?}. Images are decoded and cached by X26 before commit; local files are copied. Source, actor and invocation are retained in metadata edits/activity. Overrides survive metadata refresh and need no provider identity or credentials. Text title/overview use media.metadata.override.'
          : 'Read the same NextUiData work/episodes as the viewer: availability, actual values/local image paths, source provenance, synopsis/title language, ratings, per-episode titles/stills/danmaku and subtitles (languages, embedded/external origin, availability, provenance and selection), and coverage counts. Includes heroImage fallback and tint. Missing fields remain explicit. Language uses observed Japanese kana when present, otherwise declared language or unknown; declaredLanguage is retained. Does not change domain metadata; reading may populate the disposable image cache.',
      effect: write ? Effect.write : Effect.read,
      input: write
          ? const ObjectSchema({
              'entries': ArraySchema(ObjectSchema({
                'entityId': _ref,
                'kind': StringSchema(
                    values: ['backdrop', 'poster', 'logo', 'still']),
                'url': _ref,
                'file': _ref,
                'source': ObjectSchema({'label': _text, 'url': _text},
                    required: ['label'])
              }, required: [
                'entityId',
                'kind',
                'source'
              ]))
            }, required: [
              'entries'
            ])
          : const ObjectSchema({'workId': _ref}, required: ['workId']),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async =>
      Completed(_Json(write
          ? await service.setArtwork(input.value, invocation)
          : await service.metadataFacts(input.value['workId'] as String)));
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
          'Append cards to your current NIPAPLAY_CHAT turn. kind=work uses workId or ref; episode uses episodeId; task uses taskId (jobId); candidates uses items:[{workId or ref, reason?}]; preparation uses title, optional workId and steps:[{label,detail?, exactly one entityId/taskId/followupId}]. ref is a work outside the library, {provider, objectType, externalId, scope:""} as media.metadata.search/get return it: tmdb tv/movie, bangumi subject, dandanplay anime. Its title, poster, year, episode count and rating are read from the provider when presented and kept for the card; its page offers to prepare it. A ref the library already holds as an accepted identity shows and opens the library work. All references must exist: an unknown workId, or a ref its provider does not return, rejects the whole batch. The result lists each ref with its library workId (null when outside) and title. States/progress are resolved live; do not supply them. Viewer text is a natural short sentence without IDs or process details.',
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
