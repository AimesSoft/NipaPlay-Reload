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
const _fieldSchema = ObjectSchema({
  'field': StringSchema(),
  'value': StringSchema(nullable: true),
  'provider': StringSchema(),
  'source': StringSchema(nullable: true),
  'language': StringSchema(nullable: true),
  'fetchedAt': StringSchema(nullable: true),
  'invocationId': StringSchema(nullable: true),
  'actor': StringSchema(
      nullable: true,
      description:
          'Host-recorded metadata editor: user or agent; null for source snapshots.'),
  'origin': StringSchema(
      nullable: true,
      description: 'Invocation origin of an edit; null for source snapshots.'),
  'mode': StringSchema(
      nullable: true,
      description:
          'persistent or correction for edits; null for source snapshots.')
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
  'evidence': ArraySchema(ObjectSchema({}, additionalProperties: true)),
  'classicObservations':
      ArraySchema(ObjectSchema({}, additionalProperties: true)),
  'conflicts': ArraySchema(ObjectSchema({}, additionalProperties: true)),
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
      'Read identity by entityId, path or current (default). Register missing File/FileLocation only; never infer work identity. Includes binding audit, evidence and metadata; legacy IDs remain unaccepted evidence.',
      Effect.read,
      const ObjectSchema(
          {'entityId': _text, 'path': _text, 'current': BooleanSchema()}),
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
      'Synchronize Classic paths and visible Dandanplay matches into the shared library, preserving source observations and conflicts. Retained IDs of cleared matches remain evidence; progress is never overwritten.',
      Effect.write,
      const ObjectSchema({}),
      const ObjectSchema({'imported': IntegerSchema()},
          required: ['imported'])),
  _spec(
      'media.library.scan',
      'Index video files under an authorized native root: enumeration, probe, head hash and file locations only. Does not search providers, infer episodes or create identification tasks. requestId deduplicates submission.',
      Effect.write,
      const ObjectSchema({'root': _text, 'requestId': _text},
          required: ['root', 'requestId']),
      const ObjectSchema({'job': _jobRefSchema}, required: ['job'])),
  _spec(
      'media.files.list',
      'Return the complete recursive video file list for root, or every indexed file location for workId. Includes size, durationMs (null when unavailable), 16 MiB headMd5 and current bindings. Read-only: no indexing or identity judgment.',
      Effect.read,
      const ObjectSchema({
        'root': _text,
        'workId': _text
      }, oneOfRequired: [
        ['root'],
        ['workId']
      ]),
      const ObjectSchema({
        'files': ArraySchema(ObjectSchema({
          'fileId': StringSchema(nullable: true),
          'path': StringSchema(),
          'size': IntegerSchema(nullable: true),
          'durationMs': IntegerSchema(nullable: true),
          'headMd5': StringSchema(nullable: true),
          'modifiedAt': StringSchema(nullable: true),
          'bindings': ArraySchema(ObjectSchema({}, additionalProperties: true)),
          'episodes': ArraySchema(ObjectSchema({}, additionalProperties: true))
        }, required: [
          'fileId',
          'path',
          'size',
          'durationMs',
          'headMd5',
          'modifiedAt',
          'bindings',
          'episodes'
        ])),
        'total': IntegerSchema()
      }, required: [
        'files',
        'total'
      ])),
  _spec(
      'media.hash.match',
      'Match multiple native files against Dandanplay using the MD5 of their first 16 MiB. Returns per-file candidates or explicit errors; an empty candidate list means no hash match. No fallback search, cache, tasks or bindings.',
      Effect.read,
      const ObjectSchema({
        'files': ArraySchema(ObjectSchema({
          'entityId': _text,
          'path': _text
        }, oneOfRequired: [
          ['entityId'],
          ['path']
        ]))
      }, required: [
        'files'
      ]),
      ObjectSchema({
        'files': ArraySchema(ObjectSchema({
          'index': const IntegerSchema(),
          'fileId': const StringSchema(nullable: true),
          'path': const StringSchema(),
          'headMd5': const StringSchema(),
          'candidates': ArraySchema(_recordSchema(2)),
          'error': const ObjectSchema({}, additionalProperties: true)
        }, required: const [
          'index'
        ]))
      }, required: const [
        'files'
      ])),
  _spec(
      'media.identity.bind_batch',
      'Atomically accept explicit work, release, episode or file bindings. Files require entityId or path and episodeRefs; TMDB TV requires releaseRef. Validates catalogue membership and existing identity conflicts. Optional workId/releaseId/localEpisodeIds explicitly connect another source to local entities. Preserves reason/evidence; host derives boundBy. requestId is durable and cannot be reused with different input. No filename interpretation or release cascade.',
      Effect.write,
      const ObjectSchema({
        'requestId': _text,
        'entries': ArraySchema(ObjectSchema({
          'kind': StringSchema(values: ['work', 'release', 'episode', 'file']),
          'entityId': _text,
          'path': _text,
          'workId': _text,
          'releaseId': _text,
          'localEpisodeIds': ArraySchema(_text),
          'workRef': _refSchema,
          'releaseRef': _refSchema,
          'episodeRefs': ArraySchema(_refSchema),
          'reason': _text,
          'evidence': ArraySchema(ObjectSchema(
              {'source': _text, 'detail': _text, 'url': StringSchema()},
              required: ['source', 'detail'])),
          'startMs': IntegerSchema(minimum: 0),
          'endMs': IntegerSchema(minimum: 0)
        }, required: [
          'kind',
          'workRef',
          'reason'
        ]))
      }, required: [
        'requestId',
        'entries'
      ]),
      const ObjectSchema({
        'entries': ArraySchema(ObjectSchema({
          'index': IntegerSchema(),
          'workId': StringSchema(),
          'releaseId': StringSchema(nullable: true),
          'episodeIds': ArraySchema(StringSchema()),
          'fileId': StringSchema(nullable: true),
          'bindingIds': ArraySchema(StringSchema())
        }, required: [
          'index',
          'workId',
          'releaseId',
          'episodeIds',
          'fileId',
          'bindingIds'
        ]))
      }, required: [
        'entries'
      ])),
  _spec(
      'media.identity.unbind_batch',
      'Atomically revoke Agent/user bindings on files, episodes, releases or works and retain provenance. Optional bindingIds selects accepted bindings on that entity; omitted revokes all explicit bindings. Classic source facts are changed through Classic matching operations. Clears file episode links when no accepted file identity remains and uses the durable Classic outbox. reason is audited; requestId makes retries idempotent.',
      Effect.write,
      const ObjectSchema({
        'requestId': _text,
        'entries': ArraySchema(ObjectSchema({
          'entityId': _text,
          'bindingIds': ArraySchema(_text),
          'reason': _text,
          'evidence': ArraySchema(ObjectSchema(
              {'source': _text, 'detail': _text, 'url': StringSchema()},
              required: ['source', 'detail']))
        }, required: [
          'entityId',
          'reason'
        ]))
      }, required: [
        'requestId',
        'entries'
      ]),
      const ObjectSchema({
        'entries': ArraySchema(ObjectSchema({
          'index': IntegerSchema(),
          'entityId': StringSchema(),
          'bindingIds': ArraySchema(StringSchema())
        }, required: [
          'index',
          'entityId',
          'bindingIds'
        ]))
      }, required: [
        'entries'
      ])),
  _spec(
      'media.metadata.get_batch',
      'Read multiple external works, seasons or episodes in one call; identical refs are fetched once. Results preserve input order and per-item errors. Does not persist metadata or identities.',
      Effect.read,
      const ObjectSchema({'refs': ArraySchema(_refSchema), 'language': _text},
          required: ['refs']),
      ObjectSchema({
        'results': ArraySchema(ObjectSchema({
          'index': const IntegerSchema(),
          'record': _recordSchema(2),
          'error': const ObjectSchema({}, additionalProperties: true)
        }, required: const [
          'index'
        ]))
      }, required: const [
        'results'
      ])),
  _spec(
      'media.metadata.search_batch',
      'Search multiple metadata sources or queries in one call. Returns per-query results or explicit errors without cache, tasks or bindings.',
      Effect.read,
      const ObjectSchema({
        'queries': ArraySchema(ObjectSchema({
          'provider': _text,
          'query': _text,
          'kind': StringSchema(values: ['tv', 'movie']),
          'year': IntegerSchema(minimum: 1800, maximum: 2200)
        }, required: [
          'provider',
          'query'
        ]))
      }, required: [
        'queries'
      ]),
      ObjectSchema({
        'results': ArraySchema(ObjectSchema({
          'index': const IntegerSchema(),
          'records': ArraySchema(_recordSchema(0)),
          'error': const ObjectSchema({}, additionalProperties: true)
        }, required: const [
          'index'
        ]))
      }, required: const [
        'results'
      ])),
  _spec(
      'media.metadata.override',
      'Edit one metadata field. The host records actor, origin and invocationId. Persistent overrides survive source refresh; corrections expire on newer source snapshots; clear removes the edit. Missing entities return not_found.',
      Effect.write,
      const ObjectSchema({
        'entityId': _text,
        'field': StringSchema(
            values: ['title', 'originalTitle', 'overview', 'imageUrl']),
        'value': StringSchema(
            nullable: true,
            description:
                'Replacement text; null is an explicit empty value. Ignored for clear.'),
        'mode': StringSchema(
            values: ['persistent', 'correction', 'clear'],
            description:
                'Edit lifetime. Defaults to persistent for compatibility. clear removes the stored edit.')
      }, required: [
        'entityId',
        'field',
        'value'
      ]),
      const ObjectSchema({'identity': _entitySchema}, required: ['identity'])),
  _spec(
      'media.metadata.refresh',
      'Schedule a metadata snapshot refresh for an accepted external object. Identity and persistent overrides remain unchanged; newer snapshots supersede corrections. requestId deduplicates acceptance.',
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
          'identity': await _identity(store, await service.resolveEntity(json))
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
        final key = stableMediaId('scan', [json]);
        result = {
          'job': _job(await service.submit('media.scan', json, key: key))
        };
      case 'media.files.list':
        result = await service.listFiles(json);
      case 'media.hash.match':
        result =
            await service.matchHashes((json['files'] as List).cast<JsonMap>());
      case 'media.identity.bind_batch':
        result = await service.bindBatch(json, invocation);
      case 'media.identity.unbind_batch':
        result = await service.unbindBatch(json, invocation);
      case 'media.metadata.get_batch':
      case 'media.metadata.search_batch':
        final items =
            (json[spec.id == 'media.metadata.get_batch' ? 'refs' : 'queries']
                    as List)
                .cast<JsonMap>();
        final results = <JsonMap>[];
        final cache = <String, Future<JsonMap>>{};
        for (var index = 0; index < items.length; index++) {
          final item = items[index];
          try {
            final value =
                await cache.putIfAbsent(stableMediaId('query', item), () async {
              if (spec.id == 'media.metadata.get_batch') {
                final ref = ExternalRef.fromJson(item);
                return {
                  'record': (await service.provider(ref.provider).get(ref,
                          language: json['language'] as String? ?? 'zh-CN'))
                      .toJson()
                };
              }
              return {
                'records': [
                  for (final record in await service
                      .provider(item['provider'] as String)
                      .search(item['query'] as String,
                          kind: item['kind'] as String? ?? 'tv',
                          year: (item['year'] as num?)?.toInt()))
                    record.toJson()
                ]
              };
            });
            results.add({'index': index, ...value});
          } on Failure catch (error) {
            results.add({'index': index, 'error': error.toJson()});
          } on ProviderRetry catch (error) {
            results.add({
              'index': index,
              'error': Failure(FailureCode.unavailable,
                      '${error.provider}: ${error.reason} Retry after ${error.at.toUtc().toIso8601String()}.',
                      retryable: true)
                  .toJson()
            });
          }
        }
        result = {'results': results};
      case 'media.metadata.override':
        await store.overrideField(json['entityId'] as String,
            json['field'] as String, json['value'], invocation,
            mode: json['mode'] as String? ?? 'persistent');
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
        'source': (provenance[field] as Map)['source'],
        'language': (provenance[field] as Map)['language'],
        'fetchedAt': (provenance[field] as Map)['fetchedAt'],
        'invocationId': (provenance[field] as Map)['invocationId'],
        'actor': (provenance[field] as Map)['origin'] == null
            ? null
            : (provenance[field] as Map)['provider'],
        'origin': (provenance[field] as Map)['origin'],
        'mode': (provenance[field] as Map)['mode']
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
    ],
    'classicObservations': await store.classicObservations(id),
    'conflicts': await store.identityConflicts(id)
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
            'title': _displayTitle(release),
            'metadata': _fields(release['metadata'] as JsonMap),
            'episodes': [
              for (final episode in release['episodes'] as List<JsonMap>)
                {
                  'episodeId': episode['id'],
                  'title': _displayTitle(episode),
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

Object? _displayTitle(JsonMap entity) =>
    ((entity['metadata'] as JsonMap)['fields'] as JsonMap)['title'] ??
    (entity['attributes'] as JsonMap)['title'];
