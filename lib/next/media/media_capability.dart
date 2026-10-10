import 'package:nipa_harness/nipa_harness.dart';

import 'identity_store.dart';
import 'media_service.dart';
import 'metadata_provider.dart';

const _text = StringSchema(minLength: 1);
const _refSchema = ObjectSchema({
  'provider': _text,
  'objectType': _text,
  'externalId': _text,
  'scope': StringSchema()
}, required: [
  'provider',
  'objectType',
  'externalId',
  'scope'
]);
const _scopeSchema = ObjectSchema({
  'order': StringSchema(),
  'season': IntegerSchema(nullable: true),
  'cour': IntegerSchema(nullable: true),
  'numbers': ArraySchema(StringSchema(nullable: true)),
  'startMs': IntegerSchema(nullable: true),
  'endMs': IntegerSchema(nullable: true)
}, required: [
  'order',
  'season',
  'cour',
  'numbers',
  'startMs',
  'endMs'
]);
const _probeSchema = ObjectSchema({
  'size': IntegerSchema(),
  'modifiedAt': StringSchema(),
  'headMd5': StringSchema()
}, required: [
  'size',
  'modifiedAt',
  'headMd5'
]);
const _evidenceSchema = ObjectSchema({
  'reason': StringSchema(),
  'url': StringSchema(nullable: true),
  'fileRevision': IntegerSchema(),
  'probe': _probeSchema
}, required: [
  'reason',
  'url',
  'fileRevision',
  'probe'
]);
ObjectSchema _recordSchema(int depth) => ObjectSchema({
      'ref': _refSchema,
      'title': const StringSchema(),
      'kind': const StringSchema(),
      'originalTitle': const StringSchema(nullable: true),
      'overview': const StringSchema(nullable: true),
      'imageUrl': const StringSchema(nullable: true),
      'year': const IntegerSchema(nullable: true),
      'number': const StringSchema(nullable: true),
      'season': const IntegerSchema(nullable: true),
      'episodeType': const StringSchema(),
      'order': const StringSchema(),
      'language': const StringSchema(),
      'fetchedAt': const StringSchema(),
      'episodes': ArraySchema(
          depth == 0 ? const ObjectSchema({}) : _recordSchema(depth - 1))
    }, required: [
      'ref',
      'title',
      'kind',
      'originalTitle',
      'overview',
      'imageUrl',
      'year',
      'number',
      'season',
      'episodeType',
      'order',
      'language',
      'fetchedAt',
      'episodes'
    ]);
final _candidateSchema = ObjectSchema({
  'candidateId': const StringSchema(),
  'state': const StringSchema(),
  'source': const StringSchema(),
  'fileRevision': const IntegerSchema(),
  'bindingRevision': const IntegerSchema(),
  'work': _recordSchema(2),
  'release': _recordSchema(1),
  'episodes': ArraySchema(_recordSchema(0)),
  'workId': const StringSchema(nullable: true),
  'relation': const StringSchema(),
  'scope': _scopeSchema,
  'evidence': _evidenceSchema
}, required: [
  'candidateId',
  'state',
  'source',
  'fileRevision',
  'bindingRevision',
  'work',
  'release',
  'episodes',
  'workId',
  'relation',
  'scope',
  'evidence'
]);
const _signalsSchema = ObjectSchema({
  'raw': StringSchema(),
  'title': StringSchema(),
  'year': IntegerSchema(nullable: true),
  'season': IntegerSchema(nullable: true),
  'cour': IntegerSchema(nullable: true),
  'number': StringSchema(nullable: true),
  'endNumber': StringSchema(nullable: true),
  'episodeType': StringSchema(),
  'releaseGroup': StringSchema(nullable: true),
  'version': StringSchema(nullable: true),
  'technical': ArraySchema(StringSchema()),
  'parserVersion': StringSchema()
}, required: [
  'raw',
  'title',
  'year',
  'season',
  'cour',
  'number',
  'endNumber',
  'episodeType',
  'releaseGroup',
  'version',
  'technical',
  'parserVersion'
]);
const _fieldSchema = ObjectSchema({
  'field': StringSchema(),
  'value': StringSchema(nullable: true),
  'provider': StringSchema(),
  'language': StringSchema(nullable: true),
  'fetchedAt': StringSchema(nullable: true),
  'invocationId': StringSchema(nullable: true)
}, required: [
  'field',
  'value',
  'provider',
  'language',
  'fetchedAt',
  'invocationId'
]);
const _bindingSchema = ObjectSchema({
  'bindingId': StringSchema(),
  'ref': _refSchema,
  'relation': StringSchema(),
  'scope': _scopeSchema,
  'status':
      StringSchema(values: ['proposed', 'accepted', 'rejected', 'revoked']),
  'source': StringSchema(),
  'boundBy':
      StringSchema(nullable: true, values: ['automatic', 'agent', 'user']),
  'revision': IntegerSchema(),
  'invocationId': StringSchema(nullable: true),
  'jobId': StringSchema(nullable: true),
  'createdAt': StringSchema()
}, required: [
  'bindingId',
  'ref',
  'relation',
  'scope',
  'status',
  'source',
  'boundBy',
  'revision',
  'invocationId',
  'jobId',
  'createdAt'
]);
const _locationSchema = ObjectSchema({
  'locationId': StringSchema(),
  'source': StringSchema(),
  'ownerDeviceId': StringSchema(),
  'locator': StringSchema(),
  'available': BooleanSchema()
}, required: [
  'locationId',
  'source',
  'ownerDeviceId',
  'locator',
  'available'
]);
const _fileEpisodeSchema = ObjectSchema({
  'episodeId': StringSchema(),
  'relation': StringSchema(),
  'ordinal': IntegerSchema(),
  'startMs': IntegerSchema(nullable: true),
  'endMs': IntegerSchema(nullable: true)
}, required: [
  'episodeId',
  'relation',
  'ordinal',
  'startMs',
  'endMs'
]);
const _entitySchema = ObjectSchema({
  'id': StringSchema(),
  'kind': StringSchema(),
  'parentId': StringSchema(nullable: true),
  'revision': IntegerSchema(),
  'bindingRevision': IntegerSchema(nullable: true),
  'metadata': ArraySchema(_fieldSchema),
  'bindings': ArraySchema(_bindingSchema),
  'locations': ArraySchema(_locationSchema),
  'episodes': ArraySchema(_fileEpisodeSchema),
  'evidence': ArraySchema(ObjectSchema({
    'evidenceId': StringSchema(),
    'bindingId': StringSchema(nullable: true),
    'source': StringSchema(),
    'reason': StringSchema(),
    'fileRevision': IntegerSchema(),
    'probe': _probeSchema,
    'url': StringSchema(nullable: true)
  }, required: [
    'evidenceId',
    'bindingId',
    'source',
    'reason',
    'url'
  ])),
  'legacyEvidence': ArraySchema(ObjectSchema({
    'locationId': StringSchema(),
    'animeId': IntegerSchema(nullable: true),
    'episodeId': IntegerSchema(nullable: true),
    'animeName': StringSchema(),
    'episodeTitle': StringSchema(nullable: true),
    'videoHash': StringSchema(nullable: true),
    'provenance': StringSchema()
  }, required: [
    'locationId',
    'animeId',
    'episodeId',
    'animeName',
    'episodeTitle',
    'videoHash',
    'provenance'
  ]))
}, required: [
  'id',
  'kind',
  'parentId',
  'revision',
  'bindingRevision',
  'metadata',
  'bindings',
  'locations',
  'episodes',
  'evidence',
  'legacyEvidence'
]);
const _jobRefSchema = ObjectSchema({
  'jobId': StringSchema(),
  'state': StringSchema(),
  'revision': IntegerSchema()
}, required: [
  'jobId',
  'state',
  'revision'
]);
const _libraryWorkSchema = ObjectSchema({
  'workId': StringSchema(),
  'title': StringSchema(),
  'metadata': ArraySchema(_fieldSchema),
  'releases': ArraySchema(ObjectSchema({
    'releaseId': StringSchema(),
    'title': StringSchema(),
    'metadata': ArraySchema(_fieldSchema),
    'episodes': ArraySchema(ObjectSchema({
      'episodeId': StringSchema(),
      'title': StringSchema(),
      'number': StringSchema(nullable: true),
      'order': StringSchema(),
      'type': StringSchema(),
      'metadata': ArraySchema(_fieldSchema),
      'files': ArraySchema(ObjectSchema({
        'fileId': StringSchema(),
        'locator': StringSchema(),
        'source': StringSchema(),
        'relation': StringSchema(),
        'ordinal': IntegerSchema(),
        'startMs': IntegerSchema(nullable: true),
        'endMs': IntegerSchema(nullable: true)
      }, required: [
        'fileId',
        'locator',
        'source',
        'relation',
        'ordinal',
        'startMs',
        'endMs'
      ]))
    }, required: [
      'episodeId',
      'title',
      'number',
      'order',
      'type',
      'metadata',
      'files'
    ]))
  }, required: [
    'releaseId',
    'title',
    'metadata',
    'episodes'
  ]))
}, required: [
  'workId',
  'title',
  'metadata',
  'releases'
]);

final class MediaCapability implements Capability {
  MediaCapability(MediaService service)
      : actions = [for (final spec in _specs) _MediaAction(service, spec)];
  @override
  final List<Action> actions;
}

ActionSpec _spec(String id, String description, Effect effect,
        ObjectSchema input, ObjectSchema output) =>
    ActionSpec(
        id: id,
        title: id,
        description: description,
        effect: effect,
        input: input,
        output: output);
const _decisionInput = ObjectSchema(
    {'jobId': _text, 'revision': IntegerSchema(minimum: 0)},
    required: ['jobId', 'revision']);
final _specs = [
  _spec(
      'media.metadata.search',
      'Search a metadata source. Results are transient candidates; no cache or binding is written.',
      Effect.read,
      const ObjectSchema({
        'provider': _text,
        'query': _text,
        'kind': StringSchema(values: ['tv', 'movie']),
        'year': IntegerSchema(minimum: 1800, maximum: 2200)
      }, required: [
        'provider',
        'query'
      ]),
      ObjectSchema({'results': ArraySchema(_recordSchema(0))},
          required: const ['results'])),
  _spec(
      'media.metadata.get',
      'Fetch an external object without persisting it. TMDB refs use stable IDs and a route scope including season/episode numbers.',
      Effect.read,
      const ObjectSchema({'ref': _refSchema, 'language': _text},
          required: ['ref']),
      ObjectSchema({'record': _recordSchema(2)}, required: const ['record'])),
  _spec(
      'media.identity.get',
      'Read a local identity, binding audit, evidence and composed metadata. IDs are local; legacy IDs remain unaccepted evidence.',
      Effect.read,
      const ObjectSchema({'entityId': _text}, required: ['entityId']),
      const ObjectSchema({'identity': _entitySchema}, required: ['identity'])),
  _spec(
      'media.library.works',
      'List Next works including TMDB-only and Bangumi-only identities, releases, catalogue episodes and file locations. Progress remains owned by Classic.',
      Effect.read,
      const ObjectSchema({
        'query': StringSchema(),
        'limit': IntegerSchema(minimum: 1, maximum: 200)
      }),
      const ObjectSchema(
          {'works': ArraySchema(_libraryWorkSchema), 'total': IntegerSchema()},
          required: ['works', 'total'])),
  _spec(
      'media.library.work',
      'Read one Next work with its release and episode structure. M1 animeId retains its Dandanplay meaning.',
      Effect.read,
      const ObjectSchema({'workId': _text}, required: ['workId']),
      const ObjectSchema({'work': _libraryWorkSchema}, required: ['work'])),
  _spec(
      'media.library.import_history',
      'Import current Classic history as a side index with unknown legacy provenance; never infer confirmation or overwrite progress.',
      Effect.write,
      const ObjectSchema({}),
      const ObjectSchema({'imported': IntegerSchema()},
          required: ['imported'])),
  _spec(
      'media.library.scan',
      'Schedule a scan of an already configured native media folder. Returns immediately; the verified scan receipt confirms enumeration and child scheduling, while identification results live in child jobs. requestId deduplicates acceptance.',
      Effect.write,
      const ObjectSchema(
          {'root': _text, 'requestId': _text, 'sources': ArraySchema(_text)},
          required: ['root', 'requestId']),
      const ObjectSchema({'job': _jobRefSchema}, required: ['job'])),
  _spec(
      'media.identification.start',
      'Start identification of an indexed file at its current content revision. Repeated submissions reuse the same job until content or binding revision changes.',
      Effect.write,
      const ObjectSchema({
        'fileId': _text,
        'fileRevision': IntegerSchema(minimum: 0),
        'releaseId': _text,
        'requestId': _text,
        'sources': ArraySchema(_text)
      }, required: [
        'fileId',
        'fileRevision'
      ]),
      const ObjectSchema({'job': _jobRefSchema}, required: ['job'])),
  _spec(
      'media.identification.get',
      'Read persisted parsed signals, provider attempts, candidates and the current Decision revision. Follow task.get for executable option calls.',
      Effect.read,
      const ObjectSchema({'jobId': _text}, required: ['jobId']),
      ObjectSchema({
        'job': _jobRefSchema,
        'fileId': const StringSchema(),
        'fileRevision': const IntegerSchema(),
        'bindingRevision': const IntegerSchema(),
        'state': const StringSchema(),
        'signals': _signalsSchema,
        'probe': _probeSchema,
        'attempts': const ArraySchema(ObjectSchema({
          'provider': StringSchema(),
          'status': StringSchema(),
          'detail': StringSchema()
        }, required: [
          'provider',
          'status',
          'detail'
        ])),
        'candidates': ArraySchema(_candidateSchema)
      }, required: const [
        'job',
        'fileId',
        'fileRevision',
        'bindingRevision',
        'state',
        'signals',
        'attempts',
        'candidates'
      ])),
  _spec(
      'media.identification.add_evidence',
      'Add a verified external catalogue candidate to a pending Decision. The host fetches the objects and validates episode membership. Use reconsider to publish a new executable Decision; adding evidence does not accept identity.',
      Effect.write,
      const ObjectSchema({
        'jobId': _text,
        'revision': IntegerSchema(minimum: 0),
        'workRef': _refSchema,
        'releaseRef': _refSchema,
        'episodeIds': ArraySchema(_text),
        'workId': _text,
        'reason': _text,
        'url': _text
      }, required: [
        'jobId',
        'revision',
        'workRef',
        'episodeIds',
        'reason'
      ]),
      const ObjectSchema(
          {'candidateId': StringSchema(), 'reconsider': _decisionInput},
          required: ['candidateId', 'reconsider'])),
  _spec(
      'media.identity.bind',
      'Accept a stored candidate from the current Decision. boundBy comes from the host invocation origin. Returns an acknowledged task snapshot; recovery commits identity, delivers Classic projection and verifies it before task success.',
      Effect.write,
      const ObjectSchema({
        'jobId': _text,
        'revision': IntegerSchema(minimum: 0),
        'candidateId': _text
      }, required: [
        'jobId',
        'revision',
        'candidateId'
      ]),
      const ObjectSchema({'job': _jobRefSchema}, required: ['job'])),
  for (final op in ['reconsider', 'skip', 'defer'])
    _spec(
        'media.identification.$op',
        switch (op) {
          'reconsider' =>
            'Publish a new Decision from stored candidates and evidence; preserves file/binding revision checks.',
          'skip' =>
            'Record this identification as skipped. The verified receipt explicitly reports identified=false.',
          _ =>
            'Record this identification as deferred for more evidence. Does not report identification success.'
        },
        Effect.write,
        _decisionInput,
        const ObjectSchema({'job': _jobRefSchema}, required: ['job'])),
  _spec(
      'media.identity.unbind',
      'Revoke accepted file bindings, retain evidence and repair Classic metadata through the durable outbox. Does not delete files or progress.',
      Effect.write,
      const ObjectSchema(
          {'fileId': _text, 'bindingRevision': IntegerSchema(minimum: 0)},
          required: ['fileId', 'bindingRevision']),
      const ObjectSchema({'identity': _entitySchema}, required: ['identity'])),
  _spec(
      'media.metadata.override',
      'Override one metadata field as the user. Requires a GUI invocation; Agent calls cannot claim a user override. Refresh preserves this value.',
      Effect.write,
      const ObjectSchema({
        'entityId': _text,
        'field': StringSchema(
            values: ['title', 'originalTitle', 'overview', 'imageUrl']),
        'value': StringSchema(nullable: true)
      }, required: [
        'entityId',
        'field',
        'value'
      ]),
      const ObjectSchema({'identity': _entitySchema}, required: ['identity'])),
  _spec(
      'media.metadata.refresh',
      'Schedule a metadata snapshot refresh for an accepted external object. Identity and user overrides remain unchanged. requestId deduplicates acceptance.',
      Effect.write,
      const ObjectSchema(
          {'ref': _refSchema, 'language': _text, 'requestId': _text},
          required: ['ref', 'requestId']),
      const ObjectSchema({'job': _jobRefSchema}, required: ['job'])),
];

final class _JsonValue implements JsonEncodable {
  const _JsonValue(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _MediaAction extends Action<_JsonValue, _JsonValue> {
  const _MediaAction(this.service, this.spec);
  final MediaService service;
  @override
  final ActionSpec spec;
  @override
  _JsonValue decodeInput(JsonMap json) => _JsonValue(json);
  @override
  Future<Outcome<_JsonValue>> run(
      _JsonValue input, Invocation invocation) async {
    try {
      return await _dispatch(input, invocation);
    } on ProviderRetry catch (error) {
      throw Failure(FailureCode.unavailable,
          '${error.provider}: ${error.reason} Retry after ${error.at.toUtc().toIso8601String()}.',
          retryable: true);
    }
  }

  Future<Outcome<_JsonValue>> _dispatch(
      _JsonValue input, Invocation invocation) async {
    final json = input.json;
    final store = service.store;
    JsonMap result;
    switch (spec.id) {
      case 'media.metadata.search':
        final records = await service
            .provider(json['provider'] as String)
            .search(json['query'] as String,
                kind: json['kind'] as String? ?? 'tv',
                year: (json['year'] as num?)?.toInt());
        result = {
          'results': [for (final record in records) record.toJson()]
        };
      case 'media.metadata.get':
        final ref =
            ExternalRef.fromJson(Map<String, Object?>.from(json['ref'] as Map));
        result = {
          'record': (await service
                  .provider(ref.provider)
                  .get(ref, language: json['language'] as String? ?? 'zh-CN'))
              .toJson()
        };
      case 'media.identity.get':
        result = {
          'identity': await _identity(store, json['entityId'] as String)
        };
      case 'media.library.works':
        final works = await store.library(query: json['query'] as String?);
        result = {
          'works': [
            for (final work
                in works.take((json['limit'] as num?)?.toInt() ?? 50))
              _work(work)
          ],
          'total': works.length
        };
      case 'media.library.work':
        final id = json['workId'] as String;
        final works = (await store.library())
            .where((work) => work['workId'] == id)
            .toList();
        if (works.isEmpty) {
          throw const Failure(
              FailureCode.notFound, 'Work is absent from the Next library.');
        }
        result = {'work': _work(works.single)};
      case 'media.library.import_history':
        result = {
          'imported': await service.mutate(
              () async => store.importLegacy(await service.classic.history()))
        };
      case 'media.library.scan':
        await service.authorizedPath(json['root'] as String, directory: true);
        for (final source in (json['sources'] as List?)?.cast<String>() ??
            service.providers.keys) {
          service.provider(source);
        }
        final key = stableMediaId('scan', [json]);
        result = {
          'job': _job(await service.submit('media.scan', json, key: key))
        };
      case 'media.identification.start':
        result = {
          'job': _job(await service.identify(json['fileId'] as String,
              expectedRevision: (json['fileRevision'] as num).toInt(),
              releaseId: json['releaseId'] as String?,
              requestId: json['requestId'] as String?,
              sources: (json['sources'] as List?)?.cast<String>()))
        };
      case 'media.identification.get':
        final id = json['jobId'] as String;
        final identification = await store.identification(id);
        result = {
          'job': _job(await service.engine.get(id)),
          'fileId': identification['file_id'],
          'fileRevision': identification['file_revision'],
          'bindingRevision': identification['binding_revision'],
          'state': identification['state'],
          ...identification['context'] as JsonMap,
          'candidates': [
            for (final row in await store.candidates(id))
              {
                'candidateId': row['id'],
                'state': row['state'],
                'source': row['source'],
                'fileRevision': row['file_revision'],
                'bindingRevision': row['binding_revision'],
                ...row['payload'] as JsonMap
              }
          ]
        };
      case 'media.identification.add_evidence':
        final job = await _pending(json);
        final identification = await store.identification(job.jobId);
        final location =
            (await store.locations(identification['file_id'] as String)).first;
        final ref = ExternalRef.fromJson(
            Map<String, Object?>.from(json['workRef'] as Map));
        if (!{'tv', 'movie', 'subject', 'anime'}.contains(ref.objectType)) {
          throw const Failure(FailureCode.invalidInput,
              'workRef must reference a work catalogue.');
        }
        final record = await service.provider(ref.provider).get(ref);
        final payload = await service.candidate(
            record, service.parser.parse(location['locator'] as String),
            releaseRef: json['releaseRef'] == null
                ? null
                : ExternalRef.fromJson(
                    Map<String, Object?>.from(json['releaseRef'] as Map)),
            episodeIds: (json['episodeIds'] as List).cast<String>(),
            workId: json['workId'] as String?,
            reason: json['reason'] as String,
            url: json['url'] as String?);
        await _pending(json);
        final id = await service.mutate(() => store.addCandidate(
            job.jobId,
            payload,
            invocation.origin == 'gui' ? 'user_evidence' : 'agent_evidence'));
        result = {
          'candidateId': id,
          'reconsider': {'jobId': job.jobId, 'revision': job.revision}
        };
      case 'media.identity.bind':
      case 'media.identification.reconsider':
      case 'media.identification.skip':
      case 'media.identification.defer':
        final job = await _pending(json);
        final choice =
            spec.id == 'media.identity.bind' ? 'bind' : spec.id.split('.').last;
        if (choice == 'bind' &&
            !(await store.candidates(job.jobId)).any((row) =>
                row['id'] == json['candidateId'] &&
                row['state'] == 'proposed')) {
          throw const Failure(
              FailureCode.conflict, 'Candidate is not in this Decision.');
        }
        final checkpoint = {
          'choice': choice,
          if (choice == 'bind') 'candidateId': json['candidateId'],
          'boundBy': invocation.origin == 'gui' ? 'user' : 'agent',
          'invocationId': invocation.id
        };
        result = {
          'job': _job(await service.engine.resolveDecision(job.jobId,
              revision: (json['revision'] as num).toInt(),
              call: ActionCall(spec.id, json),
              checkpoint: checkpoint))
        };
      case 'media.identity.unbind':
        await service.mutate(() async {
          await store.unbindFile(json['fileId'] as String,
              (json['bindingRevision'] as num).toInt(), invocation);
          await service.projection.drain(fileId: json['fileId'] as String);
        });
        result = {'identity': await _identity(store, json['fileId'] as String)};
      case 'media.metadata.override':
        if (invocation.origin != 'gui') {
          throw const Failure(FailureCode.unavailable,
              'Only the host GUI can write user metadata overrides.');
        }
        await store.overrideField(json['entityId'] as String,
            json['field'] as String, json['value'], invocation);
        result = {
          'identity': await _identity(store, json['entityId'] as String)
        };
      case 'media.metadata.refresh':
        final ref =
            ExternalRef.fromJson(Map<String, Object?>.from(json['ref'] as Map));
        service.provider(ref.provider);
        final objectId = stableMediaId('object', ref.toJson());
        final accepted = await store.database.query('media_bindings',
            where: 'object_id = ? AND status = ?',
            whereArgs: [objectId, 'accepted']);
        if (accepted.isEmpty) {
          throw const Failure(FailureCode.unavailable,
              'Refresh requires an accepted external binding.');
        }
        final request = {...json, 'language': json['language'] ?? 'zh-CN'};
        result = {
          'job': _job(await service.submit('media.metadata.refresh', request,
              key: stableMediaId('refresh', request)))
        };
      default:
        throw StateError('Unimplemented media action ${spec.id}');
    }
    return Completed(_JsonValue(result));
  }

  Future<Job> _pending(JsonMap json) async {
    final job = await service.engine.get(json['jobId'] as String);
    if (job.type != 'media.identify' ||
        job.state != JobState.needsDecision ||
        job.revision != (json['revision'] as num).toInt()) {
      throw const Failure(FailureCode.conflict,
          'Decision is stale. Read the current identification.');
    }
    await service.store.checkContext(job.jobId);
    return job;
  }
}

JsonMap _job(Job job) =>
    {'jobId': job.jobId, 'state': job.state.wireName, 'revision': job.revision};
List<JsonMap> _fields(JsonMap metadata) {
  final fields = metadata['fields'] as JsonMap,
      provenance = metadata['provenance'] as JsonMap;
  return [
    for (final field in fields.keys)
      {
        'field': field,
        'value': fields[field]?.toString(),
        'provider': (provenance[field] as Map)['provider'],
        'language': (provenance[field] as Map)['language'],
        'fetchedAt': (provenance[field] as Map)['fetchedAt'],
        'invocationId': (provenance[field] as Map)['invocationId']
      }
  ];
}

Future<JsonMap> _identity(IdentityStore store, String id) async {
  final value = await store.identity(id);
  final entity = value['entity'] as JsonMap;
  final legacy = await store.database.rawQuery(
      'SELECT h.* FROM media_legacy_history h JOIN media_locations l ON l.id=h.location_id WHERE l.file_id = ?',
      [id]);
  return {
    'id': id,
    'kind': entity['kind'],
    'parentId': entity['parent_id'],
    'revision': entity['revision'],
    'bindingRevision': (entity['attributes'] as JsonMap)['bindingRevision'],
    'metadata': _fields(value['metadata'] as JsonMap),
    'bindings': [
      for (final row in value['bindings'] as List<JsonMap>)
        {
          'bindingId': row['id'],
          'ref': {
            'provider': row['provider'],
            'objectType': row['object_type'],
            'externalId': row['external_id'],
            'scope': row['object_scope']
          },
          'relation': row['relation'],
          'scope': row['scope'],
          'status': row['status'],
          'source': row['source'],
          'boundBy': row['bound_by'],
          'revision': row['revision'],
          'invocationId': row['invocation_id'],
          'jobId': row['job_id'],
          'createdAt': row['created_at']
        }
    ],
    'locations': [
      for (final row in value['locations'] as List<JsonMap>)
        {
          'locationId': row['id'],
          'source': row['source'],
          'ownerDeviceId': row['owner_device_id'],
          'locator': row['locator'],
          'available': row['available'] == 1
        }
    ],
    'episodes': [
      for (final row in value['episodes'] as List<JsonMap>)
        {
          'episodeId': row['episode_id'],
          'relation': row['relation'],
          'ordinal': row['ordinal'],
          'startMs': row['start_ms'],
          'endMs': row['end_ms']
        }
    ],
    'evidence': [
      for (final row in value['evidence'] as List<JsonMap>)
        {
          'evidenceId': row['id'],
          'bindingId': row['binding_id'],
          'source': row['source'],
          ...decodeMediaJson(row['payload'])
        }
    ],
    'legacyEvidence': [
      for (final row in legacy)
        {'locationId': row['location_id'], ...decodeMediaJson(row['payload'])}
    ]
  };
}

JsonMap _work(JsonMap work) => {
      'workId': work['workId'],
      'title': work['title'],
      'metadata': _fields(work['metadata'] as JsonMap),
      'releases': [
        for (final release in work['releases'] as List<JsonMap>)
          {
            'releaseId': release['id'],
            'title': (release['attributes'] as JsonMap)['title'],
            'metadata': _fields(release['metadata'] as JsonMap),
            'episodes': [
              for (final episode in release['episodes'] as List<JsonMap>)
                {
                  'episodeId': episode['id'],
                  'title': (episode['attributes'] as JsonMap)['title'],
                  'number': (episode['attributes'] as JsonMap)['number'],
                  'order': (episode['attributes'] as JsonMap)['order'],
                  'type': (episode['attributes'] as JsonMap)['type'],
                  'metadata': _fields(episode['metadata'] as JsonMap),
                  'files': [
                    for (final file in episode['files'] as List<JsonMap>)
                      {
                        'fileId': file['id'],
                        'locator': file['locator'],
                        'source': file['source'],
                        'relation': file['relation'],
                        'ordinal': file['ordinal'],
                        'startMs': file['start_ms'],
                        'endMs': file['end_ms']
                      }
                  ]
                }
            ]
          }
      ]
    };
