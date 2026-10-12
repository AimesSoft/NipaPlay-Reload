import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

import '../danmaku/service.dart';
import '../danmaku/capability.dart' show importProvenanceSchema;
import '../capabilities/media_models.dart';
import '../media/identity_store.dart';
import '../media/media_service.dart';
import '../media/metadata_snapshot.dart';
import '../mesh/runtime.dart';
import '../settings/denylist.dart';
import '../settings/registry.dart';
import 'query.dart';

Future<String?> visibleLocator(String? locator, MediaService media) async {
  if (locator == null || Uri.tryParse(locator)?.hasScheme == true) {
    return locator;
  }
  try {
    return await media.authorizedPath(locator);
  } on Failure {
    return null;
  }
}

StringSchema _text(String description) =>
    StringSchema(description: description, nullable: true);
IntegerSchema _int(String description) =>
    IntegerSchema(description: description, nullable: true);
BooleanSchema _bool(String description) =>
    BooleanSchema(description: description, nullable: true);
final _id =
    _text('Stable Next entity ID; independent of external provider IDs.');
final _revision = _int('Monotonically increasing local revision.');
final _time = _text('UTC ISO-8601 observation or event timestamp.');
final _locator = _text(
    'Recorded local or remote location; public URLs omit userinfo, query and fragment.');

final _bindingFields = ObjectSchema({
  'bindingId': _text('Stable Next identity binding ID.'),
  'entityId': _id,
  'objectId': _text('Stable external object reference ID.'),
  'provider': _text('Metadata provider namespace.'),
  'objectType': _text('Provider object type.'),
  'externalId': _text('ID in the provider namespace.'),
  'scope': _text('Provider route scope; not an authentication scope.'),
  'episodeScope': ObjectSchema({
    'order': _text('Episode order namespace.'),
    'season': _int('Season number; null means unspecified.'),
    'cour': _int('Cour number; null means unspecified.'),
    'numbers': const ArraySchema(
        StringSchema(nullable: true, description: 'Episode number label.'),
        description: 'Selected episode labels.'),
    'startMs': _int('File interval start in milliseconds.'),
    'endMs': _int('File interval end in milliseconds.'),
  }, description: 'Declared binding scope and file interval.'),
  'relation':
      _text('Identity relation: exact, combined or other declared relation.'),
  'status': _text('proposed, accepted, rejected or revoked.'),
  'source': _text('Recorded binding evidence source.'),
  'boundBy': _text('Host-recorded actor: user, agent or automatic.'),
  'revision': _revision,
  'invocationId': _text('Host invocation correlation ID.'),
  'jobId': _text('Related task ID, if present.'),
  'createdAt': _time,
});
final _progressFields = ObjectSchema({
  'positionMs': _int('Last playback position in milliseconds.'),
  'durationMs': _int('Recorded duration in milliseconds; zero means unknown.'),
  'progress': const NumberSchema(
      nullable: true, description: 'Watched fraction from 0 to 1.'),
  'lastWatchedAt': _time,
});
final _historyFields = ObjectSchema({
  'entryId': _text(
      'Stable opaque Classic history identity derived from its location.'),
  'fileId': _id,
  'locator': _locator,
  'animeId': _int('Classic Dandanplay anime ID; null for other identities.'),
  'episodeId':
      _int('Classic Dandanplay episode ID; distinct from Next episode IDs.'),
  'title': _text('Recorded Classic series title.'),
  'episodeTitle': _text('Recorded episode title.'),
  ..._progressFields.properties,
});
final _receiptDetails = ObjectSchema({
  'summary': _text('Helper final reply, redacted; not proof of domain completion.'),
  'resultVerification': _text('Helper-reported domain outcome remains unverified; verified receipt only verifies the turn ended.'),
  'threadId': _text('Helper Codex thread ID.'),
  'turnId': _text('Helper Codex turn ID.'),
  'turnStatus': _text('Actual helper turn status.'),
  'sourceId': _text('Media source ID.'),
  'provider': _text('Account provider.'),
  'connected': _bool('Verified connection result.'),
  'loggedIn': _bool('Account login result.'),
  'method': _text('Authentication method, never credentials.'),
  'event': _text('Hook trigger event.'),
  'objectId': _text('Hook trigger subject.'),
  'exitCode': _int('Hook process exit code.'),
  'elapsedMs': _int('Hook execution duration.'),
  'reason': _text('Domain completion or cancellation reason.'),
  'fileId': _id,
  'fileIds': ArraySchema(_id,
      nullable: true,
      description:
          'Produced Next file IDs, when the receipt includes a file collection.'),
  'bindingId': _text('Danmaku binding ID.'),
  'snapshotId': _text('Metadata snapshot ID.'),
  'cacheKey': _text('Danmaku dataset cache identity.'),
  'infoHash': _text('BitTorrent content identity; not a credential.'),
  'outputDirectory': _locator,
  'downloadComplete': _bool('Whether the selected download completed.'),
  'paused': _bool('Recorded download pause state.'),
  'refreshed': _bool('Whether a metadata snapshot was committed.'),
  'identityChanged': _bool('Whether identity was modified.'),
  'userOverridesPreserved':
      _bool('Whether persistent metadata edits were preserved.'),
  'projectionVerified': _bool('Whether Classic projection readback passed.'),
  'indexed': _int('Number of indexed files.'),
  'files': ArraySchema(
      ObjectSchema({
        'relativePath': _text('Output-relative path.'),
        'path': _locator,
        'size': _int('File size in bytes.'),
        'expectedSize': _int('Expected output size in bytes.'),
        'actualSize': _int('Verified output size in bytes; null means absent.'),
        'retained': _bool('Whether the downloaded file remains on disk.'),
        'selected': _bool('Whether this file was selected for download.'),
        'media': _bool('Whether this file is recognized as media.'),
        'verified': _bool('Whether file verification passed.'),
        'imported': _bool('Whether the library import completed.'),
      }),
      nullable: true,
      description:
          'Public output file receipts; null for tasks without a file receipt.'),
});
final _receipt = ObjectSchema({
  'verification': _text('verified, acknowledged or unverified.'),
  'details': _receiptDetails,
  'cancellation': ObjectSchema({
    'requestedAt': _time,
    'phase': _text('Cancellation phase.'),
    'sideEffectCommitted': _bool('Whether domain effects had committed.'),
    'afterCommit': _bool('Whether cancellation followed commitment.'),
  }, nullable: true)
},
    nullable: true,
    description:
        'Public receipt whitelist; domain-specific storage and credentials are excluded.');
final _taskFields = ObjectSchema({
  'threadId': _text('Helper Codex thread ID; null before dispatch or for other tasks.'),
  'startedAt': _time,
  'currentActivity': _text('Short viewer-facing helper activity sentence.'),
  'jobId': _text('Stable persisted task ID.'),
  'type': _text('Registered executor type.'),
  'title': _text('Task title.'),
  'state':
      _text('Persisted task state; succeeded means verification finished.'),
  'phase': _text('Executor phase.'),
  'revision': _revision,
  'createdAt': _time,
  'updatedAt': _time,
  'ownerDeviceId': _text('Executing device ID.'),
  'progress': ObjectSchema({
    'completed': const NumberSchema(
        nullable: true,
        description: 'Completed quantity in the declared unit.'),
    'total': const NumberSchema(
        nullable: true,
        description:
            'Total quantity in the declared unit; null means unknown.'),
    'unit': _text('Progress unit, such as bytes or files.')
  }),
  'errorCode': _text('Stable failure code; raw error messages are excluded.'),
  'receipt': _receipt,
});

JsonMap publicTaskFacts(JsonMap snapshot) => publicValue({
  ...snapshot, 'errorCode': (snapshot['error'] as Map?)?['code'],
}, _taskFields) as JsonMap;

/// Runtime suppliers expose existing in-memory Classic state, never migration
/// or refresh entry points. Core remains usable before a GUI is attached.
final class StateSources {
  List<JsonMap> Function()? history;
  List<JsonMap> Function()? continueWatching;
  Future<List<JsonMap>> Function()? calendar;
  List<StateView>? classicLibrary;
}

List<StateView> publicStateViews(
    {required MediaService media,
    required SettingsRegistry settings,
    required DanmakuService danmaku,
    required MeshRuntime mesh,
    required StateSources sources}) {
  final db = media.store.database;
  StateView sql(
          String name, String description, ObjectSchema fields, String query,
          {Future<JsonMap> Function(JsonMap)? transform,
          Map<String, StateRelation> relations = const {}}) =>
      StateView(
          name: name,
          description: description,
          fields: fields,
          relations: relations,
          read: (offset, limit) async {
            final rows =
                await db.rawQuery('$query LIMIT ? OFFSET ?', [limit, offset]);
            return [
              for (final row in rows)
                transform == null ? row : await transform(row)
            ];
          });
  Future<JsonMap> task(JsonMap row) async {
    final snapshot = jsonDecode(row['snapshot'] as String) as JsonMap;
    final receipt = snapshot['receipt'] as JsonMap?;
    if (receipt != null) {
      final details = receipt['details'] as JsonMap;
      details['outputDirectory'] =
          await visibleLocator(details['outputDirectory'] as String?, media);
      for (final file in ((details['files'] as List?) ?? [])) {
        final data = file as JsonMap;
        data['path'] = await visibleLocator(data['path'] as String?, media);
      }
    }
    return {...snapshot, 'errorCode': (snapshot['error'] as Map?)?['code']};
  }

  JsonMap progress(JsonMap row) => {
        'positionMs': row['lastPosition'],
        'durationMs': row['duration'],
        'progress': row['watchProgress'],
        'lastWatchedAt': row['lastWatchTime'] == null
            ? null
            : DateTime.parse(row['lastWatchTime'] as String)
                .toUtc()
                .toIso8601String()
      };
  Future<JsonMap> history(JsonMap row) async {
    final locator = await visibleLocator(row['filePath'] as String?, media);
    final locations = await db.query('media_locations',
        columns: ['file_id'],
        where: 'owner_device_id=? AND (locator=? OR locator=?)',
        whereArgs: [media.store.ownerDeviceId, row['filePath'], locator],
        limit: 1);
    return {
      'entryId': stableMediaId('history', row['filePath'] as String),
      'locator': locator,
      'fileId': locations.firstOrNull?['file_id'],
      'animeId': row['animeId'],
      'episodeId': row['episodeId'],
      'title': row['animeName'],
      'episodeTitle': row['episodeTitle'],
      ...progress(row)
    };
  }

  const bindingSql =
      'SELECT b.id AS bindingId,b.entity_id AS entityId,b.object_id AS objectId,'
      'o.provider,o.object_type AS objectType,o.external_id AS externalId,o.scope,'
      'b.scope AS episodeScope,b.relation,b.status,b.source,b.bound_by AS boundBy,b.revision,'
      'b.invocation_id AS invocationId,b.job_id AS jobId,b.created_at AS createdAt '
      'FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id';
  JsonMap binding(JsonMap row) =>
      {...row, 'episodeScope': decodeMediaJson(row['episodeScope'])};
  Future<List<JsonMap>> bindings(String id) async => [
        for (final row in await db
            .rawQuery('$bindingSql WHERE b.entity_id=? ORDER BY b.id', [id]))
          binding(row)
      ];
  final entities = ObjectSchema({
    'id': _id,
    'parentId': _id,
    'workId': _id,
    'releaseId': _id,
    'title': _text('Merged metadata title, falling back to recorded title.'),
    'revision': _revision,
    'kind': _text('work, release or episode.'),
    'number':
        _text('Episode number; textual to preserve special episode numbering.'),
    'order': _text('Episode ordering namespace.'),
    'type': _text('Episode type, such as regular or special.'),
    'metadata': ArraySchema(
        ObjectSchema({
          'field': _text('Metadata field name.'),
          'value': _text(
              'Merged metadata value encoded as text; null is explicit empty.'),
          'provider': _text('Metadata provider or host-recorded editor actor.'),
          'language': _text('Source language, if known.'),
          'fetchedAt': _time,
          'invocationId':
              _text('Edit invocation ID; null for source snapshots.'),
          'origin': _text('Edit origin; null for source snapshots.'),
          'mode': _text('persistent or correction; null for source snapshots.'),
        }),
        description: 'Merged field values and provenance.'),
    'bindings': ArraySchema(_bindingFields,
        description: 'Public identity bindings for this entity.'),
    'metadataView': metadataViewSchema,
  });
  Future<JsonMap> entity(JsonMap row) async {
    final attrs = decodeMediaJson(row['attributes']);
    final metadata = await media.store.mergedMetadata(row['id'] as String);
    final values = metadata['fields'] as JsonMap;
    final provenance = metadata['provenance'] as JsonMap;
    return {
      ...row,
      ...attrs,
      'title': (metadata['fields'] as Map)['title'] ?? attrs['title'],
      'bindings': await bindings(row['id'] as String),
      'metadataView': metadata,
      'metadata': [
        for (final field in values.keys)
          {
            'field': field,
            'value': values[field]?.toString(),
            ...Map<String, Object?>.from(provenance[field] as Map)
          }
      ]
    };
  }

  const workQuery =
      'SELECT id,parent_id AS parentId,id AS workId,NULL AS releaseId,kind,revision,attributes FROM media_entities WHERE kind=\'work\' ORDER BY id';
  const releaseQuery =
      'SELECT id,parent_id AS parentId,parent_id AS workId,id AS releaseId,kind,revision,attributes FROM media_entities WHERE kind=\'release\' ORDER BY id';
  const episodeQuery =
      'SELECT e.id,e.parent_id AS parentId,r.parent_id AS workId,r.id AS releaseId,e.kind,e.revision,e.attributes FROM media_entities e JOIN media_entities r ON r.id=e.parent_id WHERE e.kind=\'episode\' ORDER BY e.id';
  return [
    sql(
        'media.entities',
        'Recorded Next entities and merged metadata, without registration, refresh or raw evidence payloads. File locations are in library.files.',
        entities,
        'SELECT id,parent_id AS parentId,kind,revision,attributes FROM media_entities ORDER BY id',
        transform: entity,
        relations: {
          'bindings': const StateRelation('media.bindings', 'id', 'entityId'),
          'locations': const StateRelation('library.files', 'id', 'fileId')
        }),
    for (final name in ['library.classic_series', 'library.classic_episodes'])
      StateView(
          name: name,
          description: name == 'library.classic_series'
              ? 'Classic series using Dandanplay anime IDs; unavailable without a GUI history supplier.'
              : 'Classic episode/files/progress projection; unavailable without a GUI history supplier.',
          fields: name == 'library.classic_series'
              ? classicSeriesStateSchema
              : ObjectSchema({
                  'animeId':
                      const IntegerSchema(description: 'Dandanplay anime ID.'),
                  ...episodeEntrySchema.properties
                }),
          relations: name == 'library.classic_series'
              ? {
                  'episodes': const StateRelation(
                      'library.classic_episodes', 'animeId', 'animeId')
                }
              : {},
          read: (offset, limit) async {
            final view = sources.classicLibrary
                ?.where((view) => view.name == name)
                .firstOrNull;
            if (view == null) {
              throw const Failure(
                  FailureCode.unavailable, 'classic_library_unavailable');
            }
            return view.read(offset, limit);
          }),
    sql(
        'library.works',
        'Next works from all metadata providers. IDs are not Dandanplay anime IDs.',
        entities,
        workQuery,
        transform: entity,
        relations: {
          'seasons': const StateRelation('library.seasons', 'id', 'workId'),
          'episodes': const StateRelation('library.episodes', 'id', 'workId'),
          'files': const StateRelation('library.files', 'id', 'workId')
        }),
    sql('library.seasons', 'Next releases/seasons belonging to works.',
        entities, releaseQuery, transform: entity, relations: {
      'episodes': const StateRelation('library.episodes', 'id', 'releaseId')
    }),
    sql(
        'library.episodes',
        'Catalogue episodes, including episodes without local files.',
        entities,
        episodeQuery,
        transform: entity,
        relations: {
          'files': const StateRelation('library.files', 'id', 'episodeId'),
          'bindings': const StateRelation('media.bindings', 'id', 'entityId')
        }),
    sql(
        'library.files',
        'Recorded files and locations; one row per file/location/episode relation. Local locators outside authorized roots are omitted. Progress is a live Classic memory observation; null means no history.',
        ObjectSchema({
          'fileId': _id,
          'episodeId': _id,
          'workId': _id,
          'releaseId': _id,
          'locationId': _text('Stable location ID.'),
          'locator': _locator,
          'source': _text('Location source, including local, WebDAV or SMB.'),
          'ownerDeviceId': _text('Location owner device ID.'),
          'available':
              _bool('Recorded availability; query does not probe files.'),
          'revision': _revision,
          'bindingRevision': _revision,
          'relation': _text('File to episode relation.'),
          'ordinal': _int('Order within a combined file.'),
          'startMs': _int(
              'Episode interval start in milliseconds; null means unspecified.'),
          'endMs': _int(
              'Episode interval end in milliseconds; null means unspecified.'),
          'bindings': ArraySchema(_bindingFields),
          'progress': ObjectSchema(_progressFields.properties, nullable: true),
          'historyStatus': _text(
              'recorded, no_history or unavailable (history supplier is absent).'),
        }),
        'SELECT f.id AS fileId,f.revision,f.attributes,l.id AS locationId,l.locator,l.source,l.owner_device_id AS ownerDeviceId,l.available,'
            'fe.episode_id AS episodeId,fe.relation,fe.ordinal,fe.start_ms AS startMs,fe.end_ms AS endMs,r.id AS releaseId,r.parent_id AS workId '
            'FROM media_entities f LEFT JOIN media_locations l ON l.file_id=f.id '
            'LEFT JOIN media_file_episodes fe ON fe.file_id=f.id LEFT JOIN media_entities e ON e.id=fe.episode_id '
            'LEFT JOIN media_entities r ON r.id=e.parent_id WHERE f.kind=\'file\' ORDER BY f.id,l.id,fe.ordinal',
        transform: (row) async {
      final locator = row['locator'] as String?;
      var visible = true;
      if (row['source'] == 'local' && locator != null) {
        try {
          await media.authorizedPath(locator);
        } on Failure {
          visible = false;
        }
      }
      JsonMap? watched;
      for (final entry in sources.history?.call() ?? []) {
        final recorded = entry['filePath'] as String;
        if (recorded == locator ||
            locator != null &&
                p.basename(recorded) == p.basename(locator) &&
                await visibleLocator(recorded, media) == locator) {
          watched = entry;
          break;
        }
      }
      return {
        ...row,
        'locator': visible ? locator : null,
        'available': row['available'] == 1,
        'bindingRevision':
            decodeMediaJson(row['attributes'])['bindingRevision'],
        'bindings': await bindings(row['fileId'] as String),
        'progress': watched == null ? null : progress(watched),
        'historyStatus': sources.history == null
            ? 'unavailable'
            : watched == null
                ? 'no_history'
                : 'recorded'
      };
    }, relations: {
      'bindings': const StateRelation('media.bindings', 'fileId', 'entityId'),
      'history': const StateRelation('history.entries', 'fileId', 'fileId'),
      'danmaku': const StateRelation('danmaku.bindings', 'fileId', 'entityId')
    }),
    sql(
        'media.identities',
        'External identity references accepted or proposed by local bindings.',
        ObjectSchema({
          'objectId': _text('Stable external object reference ID.'),
          'provider': _text('Provider namespace.'),
          'objectType': _text('Provider object type.'),
          'externalId': _text('Provider ID.'),
          'scope': _text('Provider route scope.')
        }),
        'SELECT id AS objectId,provider,object_type AS objectType,external_id AS externalId,scope FROM media_external_objects ORDER BY id',
        relations: {
          'bindings':
              const StateRelation('media.bindings', 'objectId', 'objectId')
        }),
    sql(
        'media.bindings',
        'Identity binding status and provenance; evidence payloads are excluded.',
        _bindingFields,
        '$bindingSql ORDER BY b.id',
        transform: (row) async => binding(row)),
    for (final name in ['history.entries', 'history.continue_watching'])
      StateView(
          name: name,
          description:
              'Classic in-memory history. Returns unavailable before a history supplier is attached. No database migration or refresh.',
          fields: _historyFields,
          read: (offset, limit) async {
            final supplier = name == 'history.entries'
                ? sources.history
                : sources.continueWatching;
            if (supplier == null) {
              throw const Failure(
                  FailureCode.unavailable, 'history_unavailable');
            }
            return [
              for (final row in supplier().skip(offset).take(limit))
                await history(row)
            ];
          }),
    sql(
        'tasks',
        'Persisted public task snapshots. Raw input, checkpoint, arbitrary details and Decision call inputs are excluded.',
        _taskFields,
        'SELECT snapshot FROM jobs ORDER BY created_at,job_id',
        transform: (row) async => task(row),
        relations: {
          'events': const StateRelation('task_events', 'jobId', 'jobId'),
          'receipts': const StateRelation('task_receipts', 'jobId', 'jobId')
        }),
    sql(
        'task_events',
        'Persisted task transitions with closed public snapshot projections.',
        ObjectSchema({
          'jobId': _text('Stable task ID.'),
          'revision': _revision,
          'kind': _text('Task transition kind.'),
          'at': _time,
          'snapshot': _taskFields
        }),
        'SELECT job_id AS jobId,revision,kind,at,snapshot FROM job_events ORDER BY at,job_id,revision',
        transform: (row) async => {...row, 'snapshot': await task(row)}),
    sql(
        'task_receipts',
        'Tasks with committed verification receipts; file paths are public projections.',
        ObjectSchema({
          'jobId': _text('Stable task ID.'),
          'type': _text('Executor type.'),
          'state': _text('Current task state.'),
          'receipt': _receipt
        }),
        "SELECT snapshot FROM jobs WHERE json_type(snapshot,'\$.receipt')='object' ORDER BY created_at,job_id",
        transform: (row) async => task(row)),
    sql(
        'downloads',
        'Persisted download execution state and receipts; no backend refresh or session authentication.',
        _taskFields,
        "SELECT snapshot FROM jobs WHERE type='download' ORDER BY created_at,job_id",
        transform: (row) async => task(row),
        relations: {
          'events': const StateRelation('task_events', 'jobId', 'jobId')
        }),
    StateView(
        name: 'settings.changes',
        description:
            'Append-only visible setting change history, newest first. Values are projected through each registered setting schema and encoded as JSON text; secret fields are omitted.',
        fields: ObjectSchema({
          'key': _text('Registered visible setting key.'),
          'revision': _revision,
          'changedAt': _time,
          'changedBy': _text('Host-recorded actor.'),
          'origin': _text('Invocation transport origin.'),
          'invocationId': _text('Invocation correlation ID.'),
          'valueJson': _text(
              'JSON encoded current value using the setting schema; public URLs omit authentication parameters.'),
          'previousValueJson':
              _text('JSON encoded previous value using the setting schema.'),
          'reason': _text('Recorded reason, treated as untrusted data.')
        }),
        read: (offset, limit) async {
          final keys = settings.entries
              .where((entry) => entry.visible() && !isSettingDenied(entry.key))
              .map((entry) => entry.key)
              .toList();
          if (keys.isEmpty) return [];
          final rows = await db.rawQuery(
              'SELECT key,revision,changed_at AS changedAt,changed_by AS changedBy,origin,invocation_id AS invocationId,value,previous_value,reason FROM settings_changes '
              'WHERE key IN (${List.filled(keys.length, '?').join(',')}) ORDER BY sequence DESC LIMIT ? OFFSET ?',
              [...keys, limit, offset]);
          return [
            for (final row in rows)
              {
                ...row,
                'valueJson': jsonEncode(publicValue(
                    jsonDecode(row['value'] as String),
                    settings.entries
                        .singleWhere((e) => e.key == row['key'])
                        .schema)),
                'previousValueJson': jsonEncode(publicValue(
                    jsonDecode(row['previous_value'] as String),
                    settings.entries
                        .singleWhere((e) => e.key == row['key'])
                        .schema)),
              }
          ];
        }),
    sql(
        'danmaku.bindings',
        'Persistent danmaku associations. Cache presence and player mounting are distinct; no acquisition or mounting.',
        ObjectSchema({
          'bindingId': _text('Stable danmaku binding ID.'),
          'entityId': _id,
          'entityRevision': _revision,
          'revision': _revision,
          'status': _text('accepted or revoked.'),
          'sourceId': _text('Source namespace.'),
          'videoId': _text('Exact source video ID.'),
          'objectType': _text('Source object type.'),
          'enabled': _bool('Persistent enabled property.'),
          'displayFold':
              _bool('Display duplicate folding; original data remains.'),
          'offsetMs':
              _int('Fixed offset in milliseconds; positive advances danmaku.'),
          'cacheKey': _text('Dataset identity; null means not acquired.'),
          'cacheRevision': _revision,
          'loaded': _bool('Currently mounted in the local player, including Erika '
              'native danmaku; not proof of visible comments.'),
          'boundBy': _text('Host-recorded actor.'),
          'provenance': importProvenanceSchema,
          'createdAt': _time
        }),
        'SELECT id AS bindingId,entity_id AS entityId,entity_revision AS entityRevision,revision,status,video,enabled,deduplicate,offset_ms AS offsetMs,cache_key AS cacheKey,cache_revision AS cacheRevision,bound_by AS boundBy,created_at AS createdAt,provenance FROM danmaku_bindings ORDER BY id',
        transform: (row) async {
      final video = decodeMediaJson(row['video']);
      return {
        ...row,
        if (row['provenance'] != null)
          'provenance': decodeMediaJson(row['provenance']),
        'sourceId': video['sourceId'],
        'videoId': video['videoId'],
        'objectType': video['objectType'],
        'enabled': row['enabled'] == 1,
        'displayFold': row['deduplicate'] == 1,
        'loaded': danmaku.player.loaded(row['bindingId'] as String) != null
      };
    }, relations: {
      'datasets':
          const StateRelation('danmaku.datasets', 'cacheKey', 'cacheKey')
    }),
    sql(
        'danmaku.datasets',
        'Committed cache chunk summaries; no comment text or sender/session data.',
        ObjectSchema({
          'cacheKey': _text('Dataset identity.'),
          'chunkIndex': _int('Zero-based chunk index.'),
          'startMs': _int('Coverage start in source milliseconds.'),
          'endMs': _int('Coverage end in source milliseconds.'),
          'coverage': _text('Acquired coverage status.'),
          'fetchedAt': _time,
          'entryCount': _int('Number of stored entries in this chunk.')
        }),
        'SELECT cache_key AS cacheKey,chunk_index AS chunkIndex,start_ms AS startMs,end_ms AS endMs,coverage,fetched_at AS fetchedAt,json_array_length(payload) AS entryCount FROM danmaku_cache_chunks ORDER BY cache_key,chunk_index'),
    StateView(
        name: 'danmaku.tracks',
        description:
            'Current player track registry, including Classic, local and managed tracks. Empty means no loaded tracks; persistent bindings are separate.',
        fields: ObjectSchema({
          'trackId': _text('Player track ID.'),
          'bindingId': _text('Managed binding ID; null for unbound tracks.'),
          'entityId': _id,
          'name': _text('Track display name.'),
          'source': _text('Source namespace.'),
          'origin': _text('Track origin.'),
          'provenance': importProvenanceSchema,
          'platform': _text('Original platform.'),
          'platformVideoId': _text('Original platform video ID.'),
          'revision': _revision,
          'offsetMs': _int('Fixed milliseconds; positive advances danmaku.'),
          'count': _int('Loaded entry count.'),
          'enabled': _bool('Track display switch, including Erika native danmaku; '
              'not proof of visible comments at the current position.'),
          'deduplicate': _bool('Current display folding property.')
        }),
        read: (offset, limit) async =>
            danmaku.registry.skip(offset).take(limit).toList()),
    StateView(
        name: 'mesh.devices',
        description:
            'Cached same-account device observations; online is last-observed reachability, not a fresh probe. No coordinator refresh or catalog RPC.',
        fields: ObjectSchema({
          'deviceId': _text('Mesh device ID.'),
          'name': _text('Device display name.'),
          'platform': _text('Device operating platform.'),
          'revoked': _bool('Last observed revocation.'),
          'online': _bool('Cached reachability; null means unobserved.'),
          'lastSeenAt': _time
        }),
        read: (offset, limit) async =>
            mesh.cachedDevices.skip(offset).take(limit).toList()),
  ];
}
