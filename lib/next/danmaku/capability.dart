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
const importProvenanceSchema = ObjectSchema({
  'platform': _text,
  'platformVideoId': _text,
  'actor': _text,
  'origin': _text,
  'importedAt': _text,
  'filePath': _text,
  'note': StringSchema(nullable: true),
}, required: [
  'platform',
  'platformVideoId',
  'actor',
  'origin',
  'importedAt',
  'filePath',
  'note'
]);
const _coverage = ObjectSchema({
  'chunk_index': IntegerSchema(),
  'start_ms': IntegerSchema(),
  'end_ms': IntegerSchema(),
  'coverage': StringSchema(),
  'fetched_at': StringSchema(),
  'file_path': StringSchema(nullable: true),
  'entry_count': IntegerSchema(nullable: true),
  'byte_count': IntegerSchema(nullable: true),
  'storage_kind': StringSchema(nullable: true)
}, required: [
  'chunk_index',
  'start_ms',
  'end_ms',
  'coverage',
  'fetched_at'
]);
const _track = ObjectSchema({
  'trackId': StringSchema(),
  'origin': StringSchema(),
  'provenance': importProvenanceSchema,
  'platform': StringSchema(),
  'platformVideoId': StringSchema(nullable: true),
  'filePath': StringSchema(nullable: true),
  'source': StringSchema(),
  'name': StringSchema(),
  'count': IntegerSchema(),
  'bindingId': StringSchema(nullable: true),
  'bindingIds': ArraySchema(StringSchema()),
  'entityId': _text,
  'revision': IntegerSchema(),
  'status': StringSchema(),
  'stale': BooleanSchema(),
  'video': _video,
  'enabled': BooleanSchema(
      description: 'Track display switch; not proof of visible comments.'),
  'deduplicate': BooleanSchema(),
  'displayFold': BooleanSchema(),
  'offsetMs': IntegerSchema(),
  'alignment': _alignment,
  'evidence': _evidence,
  'boundBy': StringSchema(),
  'cacheKey': StringSchema(nullable: true),
  'loaded': BooleanSchema(
      description: 'Mounted in the player track registry, including '
          'Erika native danmaku. Does not prove comments are visible at the current position.'),
  'coverage': ArraySchema(_coverage)
}, required: [
  'entityId',
  'loaded',
  'origin',
  'platform',
  'platformVideoId'
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
  'historyFetch': BooleanSchema()
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
  'historyFetch'
]);
const _fetchFields = {
  'video': _video,
  'requestId': _text,
  'startMs': IntegerSchema(minimum: 0),
  'endMs': IntegerSchema(minimum: 1),
  'localDurationMs': IntegerSchema(minimum: 1, maximum: 7200000),
  'refresh': BooleanSchema()
};
const _change = ObjectSchema({
  'bindingId': _text,
  'trackId': _text,
  'expectedRevision': IntegerSchema(minimum: 0),
  'enabled': BooleanSchema(),
  'offsetMs': IntegerSchema(),
  'displayFold': BooleanSchema(),
  'reason': _text
}, oneOfRequired: [
  ['bindingId'],
  ['trackId']
]);
const _updateValue = ObjectSchema({
  'bindingId': _text,
  'trackId': _text,
  'revision': IntegerSchema(),
  'enabled': BooleanSchema(),
  'offsetMs': IntegerSchema(),
  'displayFold': BooleanSchema(),
  'persistence': StringSchema(values: ['binding', 'playback'])
}, required: [
  'enabled',
  'offsetMs',
  'displayFold',
  'persistence'
]);
const _failure = ObjectSchema(
    {'code': _text, 'message': StringSchema(), 'retryable': BooleanSchema()},
    required: ['code', 'message', 'retryable']);
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
      'danmaku.import',
      Effect.write,
      const ObjectSchema({
        'filePath': _text,
        'platform': _text,
        'platformVideoId': _text,
        'entityId': _text,
        'path': _text,
        'current': BooleanSchema(),
        'note': StringSchema(),
      }, required: [
        'filePath',
        'platform',
        'platformVideoId'
      ]),
      const ObjectSchema({
        'bindingId': _text,
        'revision': IntegerSchema(),
        'count': IntegerSchema(),
        'loaded': BooleanSchema(),
        'provenance': importProvenanceSchema,
      }, required: [
        'bindingId',
        'revision',
        'count',
        'loaded',
        'provenance'
      ]),
      'Import acquired danmaku using Classic local XML/JSON parsing and encoding support, including ARGB colors. '
          'Also accepts normalized JSON arrays (or {comments:[...]}): sourceTimeMs (nonnegative integer milliseconds), text, mode (positive integer), colorRgb (nonnegative integer, converted to RGB); '
          'optional platformId, sourceEntryId, originSource, sender, sentAt (strings), fontSize (positive integer). '
          'No registered source is required. Supply platform/platformVideoId; host records actor, origin and timestamp. '
          'Target entityId (file or episode), path, or current playback (default). '
          'Reimport replaces the same platform/video pool atomically, preserving track settings; empty or malformed files are rejected and leave the old track unchanged. '
          'Mounted immediately when the target is playing. File data stays in host storage; do not send large comment arrays through tool arguments.'),
  _spec(
      'danmaku.sources',
      Effect.read,
      const ObjectSchema({}),
      const ObjectSchema({'sources': ArraySchema(_descriptor)},
          required: ['sources']),
      'List registered sources and capabilities. No network or persistence.'),
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
      const ObjectSchema(
          {'results': ArraySchema(_video), 'page': IntegerSchema()},
          required: ['results', 'page']),
      'Read a finite catalogue page. Zero duration means unknown duration. Acquisition requires a finite range within a known media duration.'),
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
      'Create a cancellable segmented acquisition/cache task for one explicit video/range. Does not modify player tracks. requestId makes retries idempotent. A failed acquisition receipt also reports available Classic cache, assigned/partial Next cache and currently loaded matching player tracks; existing comments do not prove this request succeeded.'),
  _spec(
      'danmaku.attach',
      Effect.write,
      const ObjectSchema({
        'video': _video,
        'requestId': _text,
        'entityId': _text,
        'path': _text,
        'current': BooleanSchema(),
        'refresh': BooleanSchema(),
        'reason': _text,
        'url': StringSchema(nullable: true)
      }, required: [
        'video',
        'reason',
        'requestId'
      ]),
      const ObjectSchema({
        'bindingId': StringSchema(nullable: true),
        'jobId': StringSchema(nullable: true),
        'status': StringSchema(),
        'trackId': StringSchema()
      }, required: [
        'bindingId',
        'jobId'
      ]),
      'Bind a platform video to entityId, path or the current file (default). Existing platform/video tracks are reused; Classic dandanplay reuse records a binding, with jobId=null. Local pools prevent online acquisition. refresh=true fetches and replaces. When video.durationMs is 0 (search results do not know it), NipaPlay measures the entity\'s file on this device; an episode with no file yet is attached all the same (dandanplay returns its whole pool at once), so its comments are there when the file arrives. Invalid required local ranges fail without mounting; outside-range errors are reported separately. Credentials are opaque host references.'),
  _spec(
      'danmaku.tracks',
      Effect.read,
      const ObjectSchema(
          {'entityId': _text, 'path': _text, 'current': BooleanSchema()}),
      const ObjectSchema({'tracks': ArraySchema(_track)}, required: ['tracks']),
      'List bindings and all current player tracks, including Classic and local pools with origin/platform/platformVideoId. loaded means mounted in the player registry, including Erika native danmaku; enabled is a track display switch. Neither reports whether comments are currently visible on screen. Accept entityId, path or current (default). Missing file locations are indexed without inferring work identity; no fetch or binding is created.'),
  for (final field in ['enabled', 'deduplicate'])
    _spec(
        field == 'enabled' ? 'danmaku.set_enabled' : 'danmaku.set_dedup',
        Effect.write,
        ObjectSchema(
            {..._bindingInput.properties, field: const BooleanSchema()},
            required: ['bindingId', 'revision', field]),
        const ObjectSchema({'bindingId': _text, 'revision': IntegerSchema()},
            required: ['bindingId', 'revision']),
        'Compatibility alias for danmaku.update: set absolute $field with a binding revision check. deduplicate controls displayFold only; original source cache is preserved.'),
  _spec(
      'danmaku.offset',
      Effect.write,
      const ObjectSchema({
        'bindingId': _text,
        'revision': IntegerSchema(minimum: 0),
        'offsetMs': IntegerSchema()
      }, required: [
        'bindingId',
        'revision',
        'offsetMs'
      ]),
      const ObjectSchema({'bindingId': _text, 'revision': IntegerSchema()},
          required: ['bindingId', 'revision']),
      'Compatibility alias for danmaku.update: set an absolute fixed offset in integer milliseconds, positive advances, zero resets. Does not refetch or accumulate offsets.'),
  _spec(
      'danmaku.detach',
      Effect.write,
      _bindingInput,
      const ObjectSchema({'bindingId': _text, 'revision': IntegerSchema()},
          required: ['bindingId', 'revision']),
      'Revoke this managed binding; unreferenced imported content files are deleted, provenance remains. Recoverable source cache remains subject to the cache budget. Classic local, automatic and Dandanplay tracks remain loaded with their managed binding detached. Other managed tracks are removed.'),
  _spec(
      'danmaku.analyze_alignment',
      Effect.read,
      const ObjectSchema({'bindingId': _text, 'anchors': ArraySchema(_anchor)},
          required: ['bindingId', 'anchors']),
      const ObjectSchema({
        'bindingId': _text,
        'observedRevision': IntegerSchema(),
        'currentOffsetMs': IntegerSchema(),
        'estimateOffsetMs': IntegerSchema(nullable: true),
        'anchorOffsetsMs': ArraySchema(IntegerSchema()),
        'residualsMs': ArraySchema(IntegerSchema()),
        'maxResidualMs': IntegerSchema(nullable: true),
        'anchorSpanMs': IntegerSchema(),
        'method': StringSchema(values: ['median']),
        'anchors': ArraySchema(_anchor),
        'evidence': ArraySchema(StringSchema()),
        'confidence':
            StringSchema(values: ['consistentAnchors', 'insufficientEvidence']),
        'limitations': ArraySchema(StringSchema())
      }, required: [
        'bindingId',
        'observedRevision',
        'currentOffsetMs',
        'estimateOffsetMs',
        'anchorOffsetsMs',
        'residualsMs',
        'maxResidualMs',
        'anchorSpanMs',
        'method',
        'anchors',
        'evidence',
        'confidence',
        'limitations'
      ]),
      'Estimate a fixed offset from up to 100 supplied source/media time anchors. Returns the upper median, absolute residuals in input order, span, evidence and confidence limits. Reads the binding revision; no task, Decision or persistence. Positive integer milliseconds advance danmaku (display time = source time - offsetMs).'),
  _spec(
      'danmaku.update',
      Effect.write,
      const ObjectSchema({'changes': ArraySchema(_change)},
          required: ['changes']),
      const ObjectSchema({
        'results': ArraySchema(ObjectSchema({
          'index': IntegerSchema(),
          'status': StringSchema(values: ['completed', 'failed']),
          'result': _updateValue,
          'error': _failure
        }, required: [
          'index',
          'status'
        ], oneOfRequired: [
          ['result'],
          ['error']
        ]))
      }, required: [
        'results'
      ]),
      'Update 1 to 100 bindings or current player tracks in input order. Each item sets enabled, offsetMs and/or displayFold absolutely; positive integer milliseconds advance, negative delay, zero resets. Any explicit offset in the supported range is accepted independently of analysis estimates. Persistent bindings (including bound trackId targets) require expectedRevision; each item is atomic and returns its own result or failure, without rolling back earlier items. Unbound tracks last for the current playback and have no binding revision. displayFold affects display grouping only; original caches remain unchanged.'),
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
      'Retired compatibility lookup for existing alignment requestId tasks. New requests return unavailable with migration to danmaku.analyze_alignment and danmaku.update.'),
  for (final operation in ['apply', 'keep'])
    _spec(
        'danmaku.align_$operation',
        Effect.write,
        const ObjectSchema(
            {'jobId': _text, 'revision': IntegerSchema(minimum: 0)},
            required: ['jobId', 'revision']),
        _job,
        'Legacy recovery only: execute an existing persisted alignment decision option with a task revision check. New analysis returns data and offsets are set through danmaku.update.'),
  _spec(
      'danmaku.cache_prune',
      Effect.write,
      const ObjectSchema({'maxBytes': IntegerSchema(minimum: 0)}),
      const ObjectSchema({}, additionalProperties: true),
      'Collect unreferenced content files only. All saved danmaku pools, including online fetches and playback imports, are persistent and retained. maxBytes is a legacy compatibility parameter and never evicts saved pools. Defers while acquisition tasks are active; use cache_delete only for an explicit deletion.'),
  _spec(
      'danmaku.cache_delete',
      Effect.destructive,
      const ObjectSchema({'cacheKey': _text}, required: ['cacheKey']),
      const ObjectSchema({'deleted': BooleanSchema()}, required: ['deleted']),
      'Explicitly delete a saved danmaku pool and unload bindings using it. This removes persistent media data, including online acquisitions. Binding evidence remains.'),
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
      : actions = [for (final spec in _specs) _Action(service, spec),
          for (final spec in _specs)
            if (const {'danmaku.fetch', 'danmaku.attach', 'danmaku.import'}.contains(spec.id))
              _BatchAction(service, spec)];
  @override
  final List<Action> actions;
}

final class _BatchAction extends Action<_Data, _Data> {
  const _BatchAction(this.service, this.single);
  final DanmakuService service;
  final ActionSpec single;
  @override
  ActionSpec get spec => ActionSpec(id: '${single.id}_batch',
      title: '${single.title} batch',
      description: 'Independent entries in input order using ${single.id}. '
          'All schemas are validated before execution. atomic=false; each index '
          'returns its complete outcome (including binding/job IDs, decisions or failure). '
          'Successful entries are retained when another fails. Each requestId is '
          'scoped exactly as in the single action; credentials remain host references.',
      effect: single.effect,
      input: ObjectSchema({'entries': ArraySchema(single.input,
          description: '1–100 independent entries.')}, required: ['entries']),
      output: const ObjectSchema({'atomic': BooleanSchema(),
          'entries': ArraySchema(ObjectSchema({}, additionalProperties: true))}, required: ['atomic', 'entries']));
  @override
  _Data decodeInput(JsonMap json) => _Data(json);
  @override
  Future<Outcome<_Data>> run(_Data input, Invocation invocation) async {
    final harness = Harness([_SingleCapability(_Action(service, single))]);
    final entries = (input.value['entries'] as List).cast<JsonMap>();
    if (entries.isEmpty || entries.length > 100) {
      throw const Failure(FailureCode.invalidInput, 'Batch requires 1–100 entries.');
    }
    return Completed(_Data({'atomic': false, 'entries': [
      for (var i = 0; i < entries.length; i++) {
        'index': i,
        ...(await harness.invokeJson(single.id, entries[i], invocation)).toEnvelope(),
      }
    ]}));
  }
}
final class _SingleCapability implements Capability {
  const _SingleCapability(this.action);
  final Action action;
  @override
  List<Action> get actions => [action];
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
    try {
      switch (spec.id) {
        case 'danmaku.import':
          return result(await service.importFile(j, invocation));
        case 'danmaku.sources':
          return result({
            'sources': [
              for (final s in service.sources.values) s.describe.toJson()
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
            'page': page
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
              startMs: j['startMs'] as int? ?? 0,
              endMs: j['endMs'] as int?,
              localDurationMs: j['localDurationMs'] as int?,
              refresh: j['refresh'] == true,
              requestId: j['requestId'] as String);
          return result({'jobId': job.jobId});
        case 'danmaku.attach':
          return result(await service.attach(
              await service.resolveEntity(j),
              DanmakuVideo.fromJson(
                  Map<String, Object?>.from(j['video'] as Map)),
              j['reason'] as String,
              j['url'] as String?,
              j['requestId'] as String,
              invocation,
              refresh: j['refresh'] == true));
        case 'danmaku.tracks':
          return result(await service.tracks(await service.resolveEntity(j)));
        case 'danmaku.analyze_alignment':
          return result(await service.analyzeAlignment(
              j['bindingId'] as String, [
            for (final a in j['anchors'] as List)
              Map<String, Object?>.from(a as Map)
          ]));
        case 'danmaku.update':
          return result(await service.update([
            for (final change in j['changes'] as List)
              Map<String, Object?>.from(change as Map)
          ], invocation));
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
        case 'danmaku.cache_prune':
          final pruned = await service.store.files
              .prune(maxBytes: j['maxBytes'] as int? ?? 128 * 1024 * 1024);
          await service.refreshCurrent();
          return result(pruned);
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
          if (spec.id != 'danmaku.detach') {
            final updated = await service.updateProperties({
              'bindingId': id,
              'expectedRevision': revision,
              if (spec.id == 'danmaku.set_enabled') 'enabled': j['enabled'],
              if (spec.id == 'danmaku.set_dedup')
                'displayFold': j['deduplicate'],
              if (spec.id == 'danmaku.offset') 'offsetMs': j['offsetMs']
            }, invocation);
            return result({'bindingId': id, 'revision': updated['revision']});
          }
          final updated = await service.store
              .change(id, revision, {'status': 'revoked'}, invocation);
          service.player.remove(id);
          await service.refreshCurrent();
          return result({'bindingId': id, 'revision': updated['revision']});
      }
    } on SourceFailure catch (e) {
      throw Failure(FailureCode.unavailable, '${j['sourceId']}: ${e.message}',
          retryable: e.status == SourceStatus.rateLimited ||
              e.status == SourceStatus.transportFailed);
    }
  }
}
