import 'package:nipa_harness/nipa_harness.dart';

import 'identity_store.dart';
import 'media_service.dart';
import 'metadata_provider.dart';
import 'metadata_snapshot.dart';
import 'catalog_capability.dart';
import 'management.dart';

const _text = StringSchema(minLength: 1);
const _refSchema = ObjectSchema({
  'provider': _text,
  'objectType': _text,
  'externalId': _text,
  'scope': StringSchema(description:
      'Provider object namespace, always a string (not a local ID or binding scope object). '
      'Work: "". Dandanplay episode: "anime/<animeId>"; Bangumi episode: "subject/<subjectId>". '
      'TMDB season: "tv/<tvId>/season/<seasonNumber>"; episode: '
      '"tv/<tvId>/season/<seasonNumber>/episode/<episodeNumber>". '
      'Use the exact ref returned by metadata; externalId is the provider object ID, not an episode number.')
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
      'workId': const StringSchema(nullable: true, description: 'Search results only: accepted identity in the viewer library, canonical Next work ID; null when absent. No title-based inference.'),
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
      'rating': const ObjectSchema({
        'value': NumberSchema(),
        'max': NumberSchema(),
        'count': NumberSchema()
      }, required: [
        'value',
        'max'
      ], description: 'Work score as the provider reports it; absent when unrated.'),
      'episodeCount': const IntegerSchema(
          description: 'Work episode count as the provider reports it; absent when unknown.'),
      'details': const ObjectSchema({}, additionalProperties: true),
      'acquisition': const ObjectSchema({}, additionalProperties: true,
          description: 'Acquisition kind and requested section outcomes for this object. Detail fetched does not mean every field exists, nor that child records were fetched in detail. Absent on older records.'),
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
  'metadataView': metadataViewSchema,
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
  'metadataView': metadataViewSchema,
  'releases': ArraySchema(ObjectSchema({
    'releaseId': StringSchema(),
    'title': StringSchema(),
    'metadata': ArraySchema(_fieldSchema),
    'metadataView': metadataViewSchema,
    'episodes': ArraySchema(ObjectSchema({
      'episodeId': StringSchema(),
      'title': StringSchema(),
      'number': StringSchema(nullable: true),
      'order': StringSchema(),
      'type': StringSchema(),
      'metadata': ArraySchema(_fieldSchema),
      'metadataView': metadataViewSchema,
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
      : actions = [for (final spec in _specs) _MediaAction(service, spec),
          ...CatalogCapability(service).actions,
          ...MediaManagementCapability(service,
            [for (final spec in _specs) _MediaAction(service, spec)]).actions,
          _RefreshBatchAction(service)];
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
      'Search a metadata source. On TMDB, kind tv or movie searches that kind only; without kind, series and films are searched together in TMDB\'s own order (year then keeps results whose first air or release date is in that year). Results are transient candidates; no binding is written. Each result includes nullable workId from accepted exact/contains work or release identities in the local + Mesh catalogue (Next page ID). Title similarity and proposed/rejected/revoked bindings never count. Search may prepare the disposable catalogue/artwork projection on first read.',
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
      'Fetch an external object without persisting it. acquisition describes this object only; nested episodes may be catalogue summaries. Bind then refresh to save source details, or explicitly import the returned fields including details. TMDB refs use stable IDs and a route scope including season/episode numbers. Work records carry rating {value,max,count?}, episodeCount and details (credits, studios, genres, runtime, status, infobox, staff, characters, tags and retained providerData when available). Bangumi public metadata needs no login. Scraping never downloads danmaku; bind confirmed episode IDs separately.',
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
      'Explicitly import Classic paths and visible Dandanplay matches into Next, preserving source observations and conflicts. This is opt-in: startup, history changes, scans and identity writes never import Classic matches automatically. Retained IDs of cleared matches remain evidence; progress is never overwritten.',
      Effect.write,
      const ObjectSchema({}),
      const ObjectSchema({'imported': IntegerSchema()},
          required: ['imported'])),
  _spec(
      'media.library.scan',
      'Index video files under an authorized native root: enumeration, probe, head hash and file locations only. Does not search providers, infer episodes or create identification tasks. A directory that cannot be listed (on Windows one deeper than 259 characters, unless the system allows long paths) is left out and the receipt says which: unreadableDirectories {count, examples, reason}. requestId deduplicates submission. organizeAddedFolder=true explicitly requests Agent organization after this scan using saved settings; omit for background/repeated scans. This only queues work, not a completed scrape.',
      Effect.write,
      const ObjectSchema({'root': _text, 'requestId': _text, 'organizeAddedFolder': BooleanSchema()},
          required: ['root', 'requestId']),
      const ObjectSchema({'job': _jobRefSchema}, required: ['job'])),
  _spec(
      'media.files.list',
      'Return the complete recursive video file list for root, or every indexed file location for workId. Includes size, durationMs, technical (container, bitrate in bit/s, video/audio streams; null for files not yet probed), 16 MiB headMd5 and current bindings. Scan refreshes stored probe facts. Read-only: no indexing or identity judgment.',
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
          'technical': ObjectSchema({}, additionalProperties: true, nullable: true),
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
      'Atomically accept explicit bindings in one batch. Binding an ID is not metadata collection: direct mode fetches and saves no details. For library organization, follow direct bindings with metadata.refresh_batch, await each task receipt, then read metadata.ui_facts.sourceCoverage/review. Dandanplay identity does not replace TMDB or Bangumi details. Local hierarchy is work -> release -> episode; files link to episodes. '
      'Two input modes must not be mixed within an entry. '
      '(1) Catalogue mode: every entry supplies workRef. kind=work binds/creates only the work; '
      'kind=release binds/creates the work and release; kind=episode binds/creates the work, release and exactly one episodeRef; '
      'kind=file also links an indexed file to one or more distinct episodeRefs. '
      'Without local IDs, the same provider refs reuse the same local hierarchy within this batch. '
      'For Dandanplay anime and Bangumi subject, omit releaseRef or repeat workRef: their episode catalogue is the release. '
      'TMDB TV requires releaseRef of objectType=season for all non-work entries. '
      'Work refs have scope=""; Dandanplay episode scope="anime/<animeId>", Bangumi episode scope="subject/<subjectId>"; '
      'TMDB season scope="tv/<tvId>/season/<number>" and episode scope adds "/episode/<number>". '
      'externalId is always the actual provider object ID, not the displayed episode number. '
      'Example (replace ANIME_ID and EPISODE_ID with verified provider IDs): '
      '{"requestId":"chosen-series-1","entries":['
      '{"kind":"work","workRef":{"provider":"dandanplay","objectType":"anime","externalId":"ANIME_ID","scope":""},"reason":"User selected this work"},'
      '{"kind":"release","workRef":{"provider":"dandanplay","objectType":"anime","externalId":"ANIME_ID","scope":""},"reason":"This anime is its episode catalogue"},'
      '{"kind":"episode","workRef":{"provider":"dandanplay","objectType":"anime","externalId":"ANIME_ID","scope":""},"episodeRefs":[{"provider":"dandanplay","objectType":"episode","externalId":"EPISODE_ID","scope":"anime/ANIME_ID"}],"reason":"Verified episode identity"}]}. '
      '(2) Direct mode: ref + existing entityId + kind binds an external work/release/episode without fetching metadata, creating parents or cascading. '
      'To give an existing work, release or episode another provider\'s identity (TMDB on a work made from Bangumi, say), use direct mode with its entityId: '
      'catalogue mode with a ref no local entity has accepted creates a separate work. '
      'Direct file bindings also require exactly one localEpisodeIds target where this ref is already accepted (including an earlier entry). '
      'New direct provider namespaces must be HTTPS origins; host canonicalizes them. '
      'To tell playback which anime this is for AniSkip (opening/ending segments), bind its MyAnimeList ID '
      '(provider https://myanimelist.net) or AniList ID (provider https://anilist.co), objectType anime, scope "", '
      'to the episode, its season (release) or its work in direct mode; the nearest one is used, with the episode\'s bound number. '
      'Indexed remote files use source browse fileId as entityId and need no local byte probing. '
      'Preserves reason/evidence; host derives boundBy. requestId is durable and cannot be reused with different input.',
      Effect.write,
      const ObjectSchema({
        'requestId': _text,
        'entries': ArraySchema(ObjectSchema({
          'kind': StringSchema(values: ['work', 'release', 'episode', 'file']),
          'entityId': StringSchema(minLength: 1, description:
              'Existing local entity of this entry kind. Required in direct mode. '
              'Catalogue mode: optional for work/release/episode (omitted creates or reuses by ref); '
              'file requires exactly one entityId (browse fileId) or path.'),
          'path': StringSchema(minLength: 1, description:
              'Catalogue file only: alternative to entityId; remote location must already be indexed.'),
          'workId': StringSchema(minLength: 1, description:
              'Catalogue non-work entry: optional existing local parent work ID, not an external provider ID. '
              'Omit to reuse/create the work from workRef.'),
          'releaseId': StringSchema(minLength: 1, description:
              'Catalogue episode/file: optional existing local parent release ID under workId. '
              'Omit to reuse/create from releaseRef (or workRef for anime/subject/movie).'),
          'localEpisodeIds': ArraySchema(_text, description:
              'Catalogue: existing local episode IDs corresponding one-to-one with episodeRefs under the selected release. '
              'For kind=episode use entityId instead. Direct file: exactly one existing episode with this accepted ref.'),
          'workRef': _refSchema,
          'ref': _refSchema,
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
          'classicProjectionId': StringSchema(nullable: true),
          'bindingIds': ArraySchema(StringSchema()),
          'metadata': ObjectSchema({}, additionalProperties: true, description:
              'This invocation only: identity_only fetches/persists no metadata; nextAction suggests built-in refresh or external import after checking existing coverage. Catalogue records report their acquisition scope; child summaries are not full details. Existing snapshots are not assessed here; read ui_facts.sourceCoverage.'),
          'classicProjection': ArraySchema(ObjectSchema({
            'locator': StringSchema(),
            'status': StringSchema(),
            'restored': BooleanSchema()
          }, required: [
            'locator',
            'status',
            'restored'
          ]))
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
      'Atomically revoke Agent/user bindings and retain provenance. Optional bindingIds selects accepted bindings; omitted revokes all explicit bindings and never a classic_match one. classic_match bindings (Classic\'s automatic recognition; identitySources and identity.get list them) are revoked only when named by bindingId, on a file or on the episode, release or work it created. Revoking one changes Next only: Classic\'s watch record (progress, animeId/episodeId) and Classic UI are untouched and nothing is queued to the Classic projection outbox. Revoking a file\'s removes the links only it supported and records the Classic observation it came from as provenance classic_match_revoked, so later syncs do not attach it again; a different Classic recognition of the file (changed observation fingerprint) is imported as usual. Revoking an episode, release or work binding changes that layer: the library does not show a work with no accepted binding and no file under it. For a file entry the result lists remainingClassicBindings, the accepted classic_match bindings still on the episodes that lost the file and on their releases and works; nothing there is revoked unless named. Undo with media.identity.restore_classic_batch. Restore a projected Classic match only when its matching fields still equal the atomic projection journal; changed Classic fields remain untouched and return conflict after Next revocation. classicProjection reports restoration or unchanged independent Classic matches. reason is audited; requestId makes retries idempotent.',
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
          'bindingIds': ArraySchema(StringSchema()),
          'remainingClassicBindings': ArraySchema(ObjectSchema({
            'entityId': StringSchema(),
            'kind': StringSchema(),
            'bindingId': StringSchema()
          }, required: [
            'entityId',
            'kind',
            'bindingId'
          ])),
          'classicProjectionId': StringSchema(nullable: true),
          'classicProjection': ArraySchema(ObjectSchema({
            'locator': StringSchema(),
            'status': StringSchema(),
            'restored': BooleanSchema()
          }, required: [
            'locator',
            'status',
            'restored'
          ]))
        }, required: [
          'index',
          'entityId',
          'bindingIds'
        ]))
      }, required: [
        'entries'
      ])),
  _spec(
      'media.identity.restore_classic_batch',
      'Undo the revocation of classic_match bindings made by unbind_batch, by name. Entries are entityIds with bindingIds; bindingIds may be omitted only for a file, which then restores its revoked recognition. A file\'s binding comes back only while it is still the file\'s current Classic observation (provenance classic_match_revoked) and its episode has an accepted identity; otherwise the request is a conflict and nothing in the batch is restored. It restores the binding, the file-episode link and the observation provenance classic_match for a file; for an episode, release or work only the named binding. Classic\'s record and the projection outbox are not touched. Each restore is audited as event restore. Alternatively bind_batch makes an explicit binding, which is not the same fact and is projected to Classic. reason is audited; requestId makes retries idempotent.',
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
      'Read multiple external works, seasons or episodes in one call; identical refs are fetched once. Results preserve input order and per-item errors. Does not persist metadata or identities. Preserve details/providerData when importing; reading records alone does not complete library enrichment. acquisition distinguishes detail requests from child catalogue summaries.',
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
      'Search multiple metadata sources or queries in one call. Each query\'s kind works as in media.metadata.search (omitted on TMDB: series and films together). Returns per-query results or explicit errors without tasks or bindings. Each record includes nullable workId from accepted work/release identity in the local + Mesh catalogue; no title inference. First read may prepare the disposable catalogue/artwork projection.',
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
      'media.metadata.import_batch',
      'Append structured snapshots for accepted external identities, including arbitrary HTTPS origin namespaces. fields.rating has value/max/count and optional label; the host records its source from ref, receipt time, actor, origin and invocationId. Other JSON fields are retained. fetchedAt is optional source-reported acquisition time; host receipt time controls freshness. Atomic, durable requestId; no network or identity changes.',
      Effect.write,
      const ObjectSchema({
        'requestId': _text,
        'entries': ArraySchema(ObjectSchema({
          'ref': _refSchema,
          'language': _text,
          'fields': metadataFieldsSchema,
          'fetchedAt': _text,
          'url': _text,
        }, required: [
          'ref',
          'language',
          'fields'
        ])),
      }, required: [
        'requestId',
        'entries'
      ]),
      const ObjectSchema({
        'entries': ArraySchema(ObjectSchema({}, additionalProperties: true))
      }, required: [
        'entries'
      ])),
  _spec(
      'media.metadata.snapshots',
      'Read all retained source snapshots and host provenance for an entity. Work/release use the same work family; episode/file remain local. Returns original records, including unknown fields and historical snapshots. Does not fetch or write.',
      Effect.read,
      const ObjectSchema({'entityId': _text}, required: ['entityId']),
      const ObjectSchema({
        'snapshots': ArraySchema(ObjectSchema({}, additionalProperties: true))
      }, required: [
        'snapshots'
      ])),
  _spec(
      'media.metadata.override',
      'Edit title (display title), originalTitle, overview (synopsis) or legacy imageUrl. title/overview accept optional language (e.g. zh-CN); omitted language is unknown. Work/release edits share the work view: latest active edit wins; clear removes active edits across the family, retaining the audit log. Episode/file edits remain local. Host records actor, origin and invocationId. Persistent overrides survive refresh; corrections expire on newer snapshots. Use media.artwork.set for backdrop/poster/logo/episode still. Missing entities return not_found.',
      Effect.write,
      const ObjectSchema({
        'entityId': _text,
        'field': StringSchema(
            values: ['title', 'originalTitle', 'overview', 'imageUrl']),
        'value': StringSchema(
            nullable: true,
            description:
                'Replacement text; null is an explicit empty value. Ignored for clear.'),
        'language': _text,
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
      'Fetch and save source details for one accepted external object. Required after identity-only binding when collecting metadata. This schedules a task: wait for its terminal receipt and inspect acquisition, then read ui_facts. It does not bind or separately refresh child seasons/episodes; submit each verified ref explicitly. Identity and persistent overrides remain unchanged; newer snapshots supersede corrections. requestId deduplicates acceptance.',
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

final class _RefreshBatchAction extends Action<_JsonValue, _JsonValue> {
  const _RefreshBatchAction(this.service);
  final MediaService service;
  @override
  ActionSpec get spec => const ActionSpec(
    id: 'media.metadata.refresh_batch', title: '批量刷新来源资料',
    description: 'Schedule the same refresh as media.metadata.refresh for multiple refs. Each item is accepted independently (atomic:false), with index, job or structured error. Use after direct identity binding to fetch AND save metadata for every verified work/season/episode ref. No recursive child refresh. Wait for each job receipt, inspect acquisition, and read ui_facts.sourceCoverage/review; acceptance is not completion. Per-entry requestId deduplicates task acceptance.',
    effect: Effect.write,
    input: ObjectSchema({'entries': ArraySchema(ObjectSchema(
      {'ref': _refSchema, 'language': _text, 'requestId': _text}, required: ['ref','requestId']))}, required: ['entries']),
    output: ObjectSchema({}, additionalProperties: true));
  @override
  _JsonValue decodeInput(JsonMap json) => _JsonValue(json);
  @override
  Future<Outcome<_JsonValue>> run(_JsonValue input, Invocation invocation) async {
    final entries = (input.json['entries'] as List).cast<JsonMap>();
    if(entries.isEmpty || entries.length > 100) throw const Failure(FailureCode.invalidInput,'Batch must contain 1 to 100 entries.');
    final single = _MediaAction(service, _specs.singleWhere((s) => s.id == 'media.metadata.refresh'));
    final results = <JsonMap>[];
    for(var i=0; i<entries.length; i++) {
      try {
        final result = await single.run(_JsonValue(entries[i]),invocation);
        results.add({'index': i, ...result.toEnvelope()});
      } on Failure catch(e) { results.add({'index': i,'status': 'failed','error':e.toJson()}); }
    }
    return Completed(_JsonValue({'atomic':false,'entries':results}));
  }
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
                kind: json['kind'] as String? ?? 'any',
                year: (json['year'] as num?)?.toInt());
        result = {
          'results': await service.searchResults(records)
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
        final id = (await store.entity(json['workId'] as String))['id'];
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
          'job': _job(await service.submit('media.scan', {
            ...json,
            if (json['organizeAddedFolder'] == true && service.folderRequest != null)
              'folderRequest': await service.folderRequest!(invocation),
          }, key: key))
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
      case 'media.identity.restore_classic_batch':
        result = await service.restoreClassicBatch(json, invocation);
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
                'records': await service.searchResults(await service
                      .provider(item['provider'] as String)
                      .search(item['query'] as String,
                          kind: item['kind'] as String? ?? 'any',
                          year: (item['year'] as num?)?.toInt()))
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
        await service.mutate(() => store.overrideField(
            json['entityId'] as String,
            json['field'] as String,
            json['value'],
            invocation,
            language: json['language'] as String?,
            mode: json['mode'] as String? ?? 'persistent'));
        result = {
          'identity': await _identity(store, json['entityId'] as String)
        };
      case 'media.metadata.import_batch':
        result =
            await service.mutate(() => store.importSnapshots(json, invocation));
      case 'media.metadata.snapshots':
        result = {
          'snapshots': await store.metadataSnapshots(json['entityId'] as String)
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
        'actor': (provenance[field] as Map)['actor'] ??
            ((provenance[field] as Map)['mode'] == null
                ? null
                : (provenance[field] as Map)['provider']),
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
    'metadataView': value['metadata'],
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
      'metadataView': work['metadata'],
      'releases': [
        for (final release in work['releases'] as List<JsonMap>)
          {
            'releaseId': release['id'],
            'title': _displayTitle(release),
            'metadata': _fields(release['metadata'] as JsonMap),
            'metadataView': release['metadata'],
            'episodes': [
              for (final episode in release['episodes'] as List<JsonMap>)
                {
                  'episodeId': episode['id'],
                  'title': _displayTitle(episode),
                  'number': (episode['attributes'] as JsonMap)['number'],
                  'order': (episode['attributes'] as JsonMap)['order'],
                  'type': (episode['attributes'] as JsonMap)['type'],
                  'metadata': _fields(episode['metadata'] as JsonMap),
                  'metadataView': episode['metadata'],
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
