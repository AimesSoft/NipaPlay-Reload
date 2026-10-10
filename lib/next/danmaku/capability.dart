import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import 'service.dart';
import 'source.dart';

const _text = StringSchema(minLength: 1);
const _video = ObjectSchema({
  'sourceId': _text,
  'videoId': _text,
  'title': StringSchema(),
  'durationMs': IntegerSchema(minimum: 0, maximum: 7200000),
  'objectType': _text
}, required: [
  'sourceId',
  'videoId',
  'title',
  'durationMs',
  'objectType'
]);
const _job = ObjectSchema({'jobId': _text}, required: ['jobId']);
const _anchor = ObjectSchema({
  'sourceTimeMs': IntegerSchema(minimum: 0, maximum: 7200000),
  'mediaTimeMs': IntegerSchema(minimum: 0, maximum: 7200000),
  'evidence': _text
}, required: [
  'sourceTimeMs',
  'mediaTimeMs',
  'evidence'
]);
const _alignment = ObjectSchema({
  'method': _text,
  'confirmed': BooleanSchema(),
  'offsetMs': IntegerSchema(nullable: true),
  'anchors': ArraySchema(_anchor),
  'maxResidualMs': IntegerSchema(nullable: true),
  'confidence': StringSchema(),
  'applicableRange': StringSchema(),
  'autoApply': BooleanSchema(),
  'confirmedBy': StringSchema()
}, required: [
  'method',
  'confirmed'
]);
const _bindingInput = ObjectSchema(
    {'bindingId': _text, 'revision': IntegerSchema(minimum: 0)},
    required: ['bindingId', 'revision']);
const _evidence = ObjectSchema(
    {'reason': _text, 'url': StringSchema(nullable: true)},
    required: ['reason', 'url']);
const _coverage = ObjectSchema({
  'chunk_index': IntegerSchema(),
  'start_ms': IntegerSchema(),
  'end_ms': IntegerSchema(),
  'coverage': StringSchema(),
  'fetched_at': StringSchema()
}, required: [
  'chunk_index',
  'start_ms',
  'end_ms',
  'coverage',
  'fetched_at'
]);
const _track = ObjectSchema({
  'bindingId': _text,
  'entityId': _text,
  'revision': IntegerSchema(),
  'status': StringSchema(),
  'stale': BooleanSchema(),
  'video': _video,
  'enabled': BooleanSchema(),
  'deduplicate': BooleanSchema(),
  'offsetMs': IntegerSchema(),
  'alignment': _alignment,
  'evidence': _evidence,
  'boundBy': StringSchema(),
  'cacheKey': StringSchema(nullable: true),
  'loaded': BooleanSchema(),
  'coverage': ArraySchema(_coverage)
}, required: [
  'bindingId',
  'entityId',
  'revision',
  'status',
  'stale',
  'video',
  'enabled',
  'deduplicate',
  'offsetMs',
  'alignment',
  'evidence',
  'boundBy',
  'cacheKey',
  'loaded',
  'coverage'
]);
const _descriptor = ObjectSchema({
  'sourceId': _text,
  'contractVersion': IntegerSchema(),
  'implementationVersion': StringSchema(),
  'platform': StringSchema(),
  'runtimePlatforms': ArraySchema(StringSchema()),
  'access': StringSchema(),
  'allowedHosts': ArraySchema(StringSchema()),
  'requestProfiles': ArraySchema(StringSchema()),
  'search': BooleanSchema(),
  'listEpisodes': BooleanSchema(),
  'resolve': BooleanSchema(),
  'segmentedFetch': BooleanSchema(),
  'rangeFetch': BooleanSchema(),
  'resumableFetch': BooleanSchema(),
  'cursorFetch': BooleanSchema(),
  'supportedModes': ArraySchema(IntegerSchema()),
  'aggregation': BooleanSchema(),
  'compositionKnown': BooleanSchema(),
  'concurrency': IntegerSchema(),
  'requestBudget': IntegerSchema(),
  'responseBytes': IntegerSchema(),
  'itemCount': IntegerSchema(),
  'historyFetch': BooleanSchema(),
  'sessionAvailable': BooleanSchema()
}, required: [
  'sourceId',
  'contractVersion',
  'implementationVersion',
  'platform',
  'runtimePlatforms',
  'access',
  'allowedHosts',
  'requestProfiles',
  'search',
  'listEpisodes',
  'resolve',
  'segmentedFetch',
  'rangeFetch',
  'resumableFetch',
  'cursorFetch',
  'supportedModes',
  'aggregation',
  'compositionKnown',
  'concurrency',
  'requestBudget',
  'responseBytes',
  'itemCount',
  'historyFetch',
  'sessionAvailable'
]);
const _fetchFields = {
  'video': _video,
  'credentialRef': _text,
  'requestId': _text,
  'startMs': IntegerSchema(minimum: 0),
  'endMs': IntegerSchema(minimum: 1)
};
ActionSpec _spec(String id, Effect effect, ObjectSchema input,
        ObjectSchema output, String description) =>
    ActionSpec(
        id: id,
        title: id,
        description: description,
        effect: effect,
        input: input,
        output: output);
final _specs = [
  _spec(
      'danmaku.sources',
      Effect.read,
      const ObjectSchema({}),
      const ObjectSchema({'sources': ArraySchema(_descriptor)},
          required: ['sources']),
      'List registered plugin-ready sources, capabilities and host session availability. No network or persistence.'),
  _spec(
      'danmaku.search',
      Effect.read,
      const ObjectSchema({'sourceId': _text, 'query': _text},
          required: ['sourceId', 'query']),
      const ObjectSchema({'results': ArraySchema(_video)},
          required: ['results']),
      'Bounded transient title search. Unsupported sources report unavailable; no binding or task is created.'),
  _spec(
      'danmaku.episodes',
      Effect.read,
      const ObjectSchema({
        'sourceId': _text,
        'workId': _text,
        'page': IntegerSchema(minimum: 1, maximum: 100)
      }, required: [
        'sourceId',
        'workId'
      ]),
      const ObjectSchema({
        'results': ArraySchema(_video),
        'page': IntegerSchema(),
        'mayHaveMore': BooleanSchema()
      }, required: [
        'results',
        'page',
        'mayHaveMore'
      ]),
      'Read a finite catalogue page. A zero duration requires an explicit known media duration before fetching.'),
  _spec(
      'danmaku.resolve',
      Effect.read,
      const ObjectSchema(
          {'sourceId': _text, 'locator': _text, 'selectionVideoId': _text},
          required: ['sourceId', 'locator']),
      const ObjectSchema({'video': _video}, required: ['video']),
      'Resolve a public URL or platform ID. Multiple parts return executable selection decisions. No persistence.'),
  _spec(
      'danmaku.fetch',
      Effect.write,
      const ObjectSchema(_fetchFields, required: ['video', 'requestId']),
      _job,
      'Create a cancellable segmented acquisition/cache task for one explicit video/range. Does not modify player tracks. requestId makes retries idempotent.'),
  _spec(
      'danmaku.attach',
      Effect.write,
      const ObjectSchema({
        'video': _video,
        'credentialRef': _text,
        'requestId': _text,
        'entityId': _text,
        'reason': _text,
        'url': StringSchema(nullable: true)
      }, required: [
        'video',
        'entityId',
        'reason',
        'requestId'
      ]),
      const ObjectSchema({'bindingId': _text, 'jobId': _text},
          required: ['bindingId', 'jobId']),
      'Bind an explicit platform video to an MA file/episode with provenance and create its acquisition task. Whole requested pool must validate before mounting. Credentials are opaque host references.'),
  _spec(
      'danmaku.tracks',
      Effect.read,
      const ObjectSchema({'entityId': _text}, required: ['entityId']),
      const ObjectSchema({'tracks': ArraySchema(_track)}, required: ['tracks']),
      'Read persistent bindings, revision, source coverage and current loaded state, without restoring or fetching.'),
  for (final field in ['enabled', 'deduplicate'])
    _spec(
        field == 'enabled' ? 'danmaku.set_enabled' : 'danmaku.set_dedup',
        Effect.write,
        ObjectSchema(
            {..._bindingInput.properties, field: const BooleanSchema()},
            required: ['bindingId', 'revision', field]),
        const ObjectSchema({'bindingId': _text, 'revision': IntegerSchema()},
            required: ['bindingId', 'revision']),
        'Set absolute $field with a binding revision check. Original source cache is preserved.'),
  _spec(
      'danmaku.offset',
      Effect.write,
      const ObjectSchema({
        'bindingId': _text,
        'revision': IntegerSchema(minimum: 0),
        'offsetMs': IntegerSchema(minimum: -7200000, maximum: 7200000)
      }, required: [
        'bindingId',
        'revision',
        'offsetMs'
      ]),
      const ObjectSchema({'bindingId': _text, 'revision': IntegerSchema()},
          required: ['bindingId', 'revision']),
      'Set an absolute fixed offset in integer milliseconds: positive advances, zero resets. Does not refetch or accumulate offsets.'),
  _spec(
      'danmaku.detach',
      Effect.write,
      _bindingInput,
      const ObjectSchema({'bindingId': _text, 'revision': IntegerSchema()},
          required: ['bindingId', 'revision']),
      'Revoke this managed binding and remove its player track; source cache and provenance remain available.'),
  _spec(
      'danmaku.align',
      Effect.write,
      const ObjectSchema({
        'bindingId': _text,
        'requestId': _text,
        'anchors': ArraySchema(ObjectSchema({
          'sourceTimeMs': IntegerSchema(minimum: 0, maximum: 7200000),
          'mediaTimeMs': IntegerSchema(minimum: 0, maximum: 7200000),
          'evidence': _text
        }, required: [
          'sourceTimeMs',
          'mediaTimeMs',
          'evidence'
        ]))
      }, required: [
        'bindingId',
        'anchors',
        'requestId'
      ]),
      _job,
      'Create an anchor-based alignment task. It stores a fixed-offset estimate and requests an explicit choice; it never applies guesses automatically.'),
  for (final operation in ['apply', 'keep'])
    _spec(
        'danmaku.align_$operation',
        Effect.write,
        const ObjectSchema(
            {'jobId': _text, 'revision': IntegerSchema(minimum: 0)},
            required: ['jobId', 'revision']),
        _job,
        'Execute the exact current alignment decision option with a task revision check.'),
  _spec(
      'danmaku.cache_delete',
      Effect.destructive,
      const ObjectSchema({'cacheKey': _text}, required: ['cacheKey']),
      const ObjectSchema({'deleted': BooleanSchema()}, required: ['deleted']),
      'Delete a specific source cache object and unload bindings using it. Binding evidence remains.'),
  _spec(
      'danmaku.export',
      Effect.write,
      const ObjectSchema({
        'bindingId': _text,
        'path': _text,
        'view': StringSchema(values: ['raw', 'mapped'])
      }, required: [
        'bindingId',
        'path',
        'view'
      ]),
      const ObjectSchema({
        'path': _text,
        'count': IntegerSchema(),
        'bytes': IntegerSchema(),
        'sha256': _text,
        'view': _text
      }, required: [
        'path',
        'count',
        'bytes',
        'sha256',
        'view'
      ]),
      'Export one committed binding as JSON to a new file in an authorized media folder. raw preserves original source fields; mapped applies its fixed offset without player filters. Readback is verified.'),
];

final class DanmakuCapability implements Capability {
  DanmakuCapability(DanmakuService service)
      : actions = [for (final spec in _specs) _Action(service, spec)];
  @override
  final List<Action> actions;
}

final class _Data implements JsonEncodable {
  const _Data(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Action extends Action<_Data, _Data> {
  const _Action(this.service, this.spec);
  final DanmakuService service;
  @override
  final ActionSpec spec;
  @override
  _Data decodeInput(JsonMap json) => _Data(json);
  @override
  Future<Outcome<_Data>> run(_Data input, Invocation invocation) async {
    final j = input.value;
    final cancel = DanmakuCancellation();
    Completed<_Data> result(JsonMap value) => Completed(_Data(value));
    DanmakuAccess? access() => j['credentialRef'] == null
        ? null
        : DanmakuAccess(j['credentialRef'] as String);
    try {
      switch (spec.id) {
        case 'danmaku.sources':
          return result({
            'sources': [
              for (final s in service.sources.values)
                {
                  ...s.describe.toJson(),
                  'sessionAvailable':
                      service.host.sessionAvailable(s.describe.id)
                }
            ]
          });
        case 'danmaku.search':
          return result({
            'results': [
              for (final v in await service
                  .source(j['sourceId'] as String)
                  .search(j['query'] as String, cancel))
                v.toJson()
            ]
          });
        case 'danmaku.episodes':
          final page = j['page'] as int? ?? 1;
          final videos = await service
              .source(j['sourceId'] as String)
              .listEpisodes(j['workId'] as String, page, cancel);
          return result({
            'results': [for (final v in videos) v.toJson()],
            'page': page,
            'mayHaveMore': j['sourceId'] == 'youku' && videos.length == 100
          });
        case 'danmaku.resolve':
          final videos = await service
              .source(j['sourceId'] as String)
              .resolve(j['locator'] as String, cancel);
          final selected = j['selectionVideoId'] as String?;
          final choices = selected == null
              ? videos
              : videos.where((v) => v.videoId == selected).toList();
          if (choices.isEmpty) {
            throw const Failure(
                FailureCode.notFound, 'No matching video part.');
          }
          if (choices.length == 1) {
            return result({'video': choices.single.toJson()});
          }
          return NeedsDecision(Decision(
              prompt: 'Choose the exact platform video part before binding.',
              options: [
                for (final v in choices)
                  DecisionOption(
                      label: v.title,
                      detail: jsonEncode(v.toJson()),
                      call: ActionCall('danmaku.resolve', {
                        'sourceId': j['sourceId'],
                        'locator': j['locator'],
                        'selectionVideoId': v.videoId
                      }))
              ]));
        case 'danmaku.fetch':
          final job = await service.fetch(
              DanmakuVideo.fromJson(
                  Map<String, Object?>.from(j['video'] as Map)),
              access: access(),
              startMs: j['startMs'] as int? ?? 0,
              endMs: j['endMs'] as int?,
              requestId: j['requestId'] as String);
          return result({'jobId': job.jobId});
        case 'danmaku.attach':
          return result(await service.attach(
              j['entityId'] as String,
              DanmakuVideo.fromJson(
                  Map<String, Object?>.from(j['video'] as Map)),
              j['reason'] as String,
              j['url'] as String?,
              access(),
              j['requestId'] as String,
              invocation));
        case 'danmaku.tracks':
          return result(await service.tracks(j['entityId'] as String));
        case 'danmaku.align':
          final anchors = [
            for (final a in j['anchors'] as List)
              Map<String, Object?>.from(a as Map)
          ];
          if (anchors.length > 100) {
            throw const Failure(
                FailureCode.invalidInput, 'At most 100 alignment anchors.');
          }
          return result({
            'jobId': (await service.align(j['bindingId'] as String, anchors,
                    j['requestId'] as String))
                .jobId
          });
        case 'danmaku.align_apply':
        case 'danmaku.align_keep':
          return result({
            'jobId': (await service.chooseAlignment(
                    j['jobId'] as String,
                    j['revision'] as int,
                    spec.id == 'danmaku.align_apply',
                    invocation))
                .jobId
          });
        case 'danmaku.cache_delete':
          await service.deleteCache(j['cacheKey'] as String);
          return result({'deleted': true});
        case 'danmaku.export':
          final exporter = service.exporter;
          if (exporter == null) {
            throw const Failure(FailureCode.unavailable,
                'The host has not configured an export directory boundary.');
          }
          return result(await exporter.export(j['bindingId'] as String,
              j['path'] as String, j['view'] as String));
        default:
          final id = j['bindingId'] as String, revision = j['revision'] as int;
          final values = switch (spec.id) {
            'danmaku.set_enabled' => {'enabled': j['enabled'] == true ? 1 : 0},
            'danmaku.set_dedup' => {
                'deduplicate': j['deduplicate'] == true ? 1 : 0
              },
            'danmaku.offset' => {'offset_ms': j['offsetMs']},
            'danmaku.detach' => {'status': 'revoked'},
            _ => throw StateError('Unregistered danmaku action')
          };
          final updated =
              await service.store.change(id, revision, values, invocation,
                  alignment: spec.id == 'danmaku.offset'
                      ? {
                          'method': 'manualOffset',
                          'confirmed': true,
                          'offsetMs': j['offsetMs'],
                          'confirmedBy':
                              invocation.origin == 'gui' ? 'user' : 'agent'
                        }
                      : null);
          if (spec.id == 'danmaku.detach') service.player.remove(id);
          await service.refreshCurrent();
          return result({'bindingId': id, 'revision': updated['revision']});
      }
    } on SourceFailure catch (e) {
      throw Failure(
          FailureCode.unavailable, '${j['sourceId']}: ${e.status.name}',
          retryable: e.status == SourceStatus.rateLimited ||
              e.status == SourceStatus.transportFailed);
    }
  }
}
