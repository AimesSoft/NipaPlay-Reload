import 'dart:async';
import 'dart:convert';
import '../state/change_history.dart';
import '../events/signals.dart';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'classic_history_eligibility.dart';

import 'metadata_provider.dart';
import 'metadata_snapshot.dart';
import 'file_identity_merge.dart';

String stableMediaId(String prefix, Object value) =>
    '$prefix-${sha256.convert(utf8.encode(jsonEncode(_canonical(value))))}';
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String newMediaId(String prefix) => '$prefix-${const Uuid().v4()}';
JsonMap decodeMediaJson(Object? value) =>
    Map<String, Object?>.from(jsonDecode(value as String) as Map);
String get _now => DateTime.now().toUtc().toIso8601String();
bool isLocationOnlyMediaProbe(JsonMap probe) =>
    probe.keys.every((key) => key == 'legacy');

final class IdentityStore {
  IdentityStore(this.database, this.ownerDeviceId);
  final Database database;
  final String ownerDeviceId;
  Future<T> _transaction<T>(Future<T> Function(Transaction) action) => BodySignals.transaction(database, action);
  final _fileChanges = StreamController<JsonMap>.broadcast();
  Stream<JsonMap> get fileChanges => _fileChanges.stream;
  Future<T> _filesChanged<T>(
      Future<T> Function(List<JsonMap>) operation) async {
    final added = <JsonMap>[];
    final result = await operation(added);
    for (final file in added) {
      _fileChanges.add(file);
    }
    return result;
  }

  Future<void> closeEvents() => _fileChanges.close();

  /// Location-only registration never changes content revisions or infers identity.
  Future<String> ensureFile(String locator, {DatabaseExecutor? db}) =>
      db == null
          ? _filesChanged((added) =>
              _transaction((tx) => _ensureFile(tx, locator, added)))
          : _ensureFile(db, locator);

  Future<String> _ensureFile(DatabaseExecutor tx, String locator,
      [List<JsonMap>? added, String? source]) async {
    if (locator.trim().isEmpty) {
      throw const Failure(FailureCode.invalidInput, 'File path is empty.');
    }
    await mergeLegacyRemoteFile(tx, ownerDeviceId, locator);
    var rows = await tx.query('media_locations',
        where:
            'owner_device_id = ? AND locator = ?${source == null ? '' : ' AND source=?'}',
        whereArgs: [ownerDeviceId, locator, if (source != null) source]);
    if (source != null && source != 'local' && source != 'remote' && rows.isEmpty) {
      final legacy = await tx.query('media_locations', where: "owner_device_id=? AND locator=? AND source='remote'", whereArgs: [ownerDeviceId, locator]);
      final scoped = await tx.query('media_locations', where: "owner_device_id=? AND locator=? AND source!='remote'", whereArgs: [ownerDeviceId, locator]);
      if (legacy.isNotEmpty && scoped.isEmpty) {
        await tx.update('media_locations', {'source': source}, where: 'id=?', whereArgs: [legacy.single['id']]);
        rows = [{...legacy.single, 'source': source}];
      }
    }
    if (rows.map((r) => r['file_id']).toSet().length > 1) {
      throw const Failure(FailureCode.conflict,
          'This path belongs to multiple sources; use the source browse fileId.');
    }
    if (rows.isNotEmpty) return rows.first['file_id'] as String;
    final id = newMediaId('file');
    await tx.insert('media_entities', {
      'id': id,
      'kind': 'file',
      'revision': 0,
      'attributes':
          jsonEncode({'probe': <String, Object?>{}, 'bindingRevision': 0})
    });
    await tx.insert('media_locations', {
      'id': newMediaId('location'),
      'file_id': id,
      'source': source ?? (locator.contains('://') ? 'remote' : 'local'),
      'owner_device_id': ownerDeviceId,
      'locator': locator,
      'available': 1
    });
    added?.add({'fileId': id, 'path': locator});
    return id;
  }

  Future<String> ensureRemoteFile(
          String locator, String sourceId, JsonMap metadata) =>
      _filesChanged((added) => _transaction((tx) async {
            final serverId = metadata['serverId'] as String?;
            final sourceScope = serverId == null
                ? sourceId
                : '$sourceId@${Uri.encodeComponent(serverId)}';
            final id = await _ensureFile(tx, locator, added, sourceScope);
            final file = await entity(id, db: tx);
            await tx.update(
                'media_entities',
                {
                  'attributes': jsonEncode({
                    ...file['attributes'] as JsonMap,
                    'remoteSource': {'sourceId': sourceId, ...metadata}
                  })
                },
                where: 'id=?',
                whereArgs: [id]);
            return id;
          }));

  Future<JsonMap> entity(String id, {DatabaseExecutor? db}) async {
    id = await canonicalFileId(db ?? database, id);
    final rows = await (db ?? database)
        .query('media_entities', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw Failure(FailureCode.notFound, 'Media entity $id not found.');
    }
    return {
      ...rows.single,
      'attributes': decodeMediaJson(rows.single['attributes'])
    };
  }

  Future<String> registerFile(String locator, JsonMap probe,
          {String source = 'local'}) =>
      _filesChanged((added) => _transaction((tx) async {
            final locations = await tx.query('media_locations',
                where: 'source = ? AND owner_device_id = ? AND locator = ?',
                whereArgs: [source, ownerDeviceId, locator]);
            if (locations.isNotEmpty) {
              final fileId = locations.single['file_id'] as String;
              final file = await entity(fileId, db: tx);
              final attrs = file['attributes'] as JsonMap;
              if (isLocationOnlyMediaProbe(attrs['probe'] as JsonMap)) {
                await tx.update(
                    'media_entities',
                    {
                      'attributes': jsonEncode({...attrs, 'probe': probe})
                    },
                    where: 'id = ?',
                    whereArgs: [fileId]);
              } else if ([
                'size',
                'modifiedAt',
                'headMd5'
              ].any((key) => (attrs['probe'] as JsonMap)[key] != probe[key])) {
                final dandanplay = await tx.rawQuery(
                    'SELECT b.relation,o.external_id,o.scope AS object_scope FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.entity_id = ? AND b.status = ? AND o.provider = ? AND b.source!=\'classic_match\'',
                    [fileId, 'accepted', 'dandanplay']);
                final bindingRevision = (attrs['bindingRevision'] as int) + 1;
                await tx.update(
                    'media_entities',
                    {
                      'revision': (file['revision'] as int) + 1,
                      'attributes': jsonEncode({
                        ...attrs,
                        'probe': probe,
                        'bindingRevision': bindingRevision
                      })
                    },
                    where: 'id = ?',
                    whereArgs: [fileId]);
                final revoked = await tx.query('media_bindings', columns: ['id'],
                    where: "entity_id=? AND status='accepted' AND source!='classic_match'",
                    whereArgs: [fileId]);
                await tx.update('media_bindings', {'status': 'revoked'},
                    where:
                        'entity_id = ? AND status = ? AND source!=\'classic_match\'',
                    whereArgs: [fileId, 'accepted']);
                for (final binding in revoked) {
                  await _audit(tx, binding['id'] as String,
                      {'reason': 'File content changed after indexing.'},
                      Invocation(origin: 'application'), event: 'unbind');
                }
                await _pruneFileLinks(tx, fileId);
                await _queueFileProjection(
                    tx, fileId, (file['revision'] as int) + 1, bindingRevision,
                    removed: dandanplay);
              }
              await tx.update(
                  'media_entities',
                  {
                    'attributes': jsonEncode({
                      ...(await entity(fileId, db: tx))['attributes']
                          as JsonMap,
                      'probe': probe
                    })
                  },
                  where: 'id=?',
                  whereArgs: [fileId]);
              await tx.update('media_locations', {'available': 1},
                  where: 'id = ?', whereArgs: [locations.single['id']]);
              added.add({'fileId': fileId, 'path': locator});
              return fileId;
            }
            final id = newMediaId('file');
            await tx.insert('media_entities', {
              'id': id,
              'kind': 'file',
              'revision': 0,
              'attributes': jsonEncode({'probe': probe, 'bindingRevision': 0})
            });
            await tx.insert('media_locations', {
              'id': newMediaId('location'),
              'file_id': id,
              'source': source,
              'owner_device_id': ownerDeviceId,
              'locator': locator,
              'available': 1
            });
            added.add({'fileId': id, 'path': locator});
            return id;
          }));

  Future<List<JsonMap>> locations(String fileId) async => database
      .query('media_locations', where: 'file_id = ?', whereArgs: [await canonicalFileId(database, fileId)]);

  /// Only visible Classic matches become identities; retained IDs remain evidence.
  Future<int> importLegacy(List<JsonMap> history,
      {bool reconcileMissing = true}) async {
    for (final row in history) {
      await _filesChanged((added) => _transaction((tx) async {
            final locator = row['filePath'] as String;
            final fileId = await _ensureFile(tx, locator, added);
            final location = (await tx.query('media_locations',
                    where: 'file_id=? AND locator=?',
                    whereArgs: [fileId, locator]))
                .first;
            final evidence = <String, Object?>{
              'animeId': row['animeId'],
              'episodeId': row['episodeId'],
              'animeName': row['animeName'],
              'episodeTitle': row['episodeTitle'],
              'videoHash': row['videoHash'],
              'provenance': 'legacy_unknown'
            };
            final fingerprint = stableMediaId('legacy', evidence);
            if (row['classicMetadata'] case final Map cached) {
              final animeId = row['animeId'] as int?;
              final eligible = eligibleClassicHistory(row);
              if (animeId != null && animeId > 0 &&
                  eligible &&
                  (row['episodeId'] as int? ?? 0) > 0 &&
                  (row['animeName'] as String).isNotEmpty &&
                  row['episodeTitle'] != null) {
                final ref = ExternalRef('dandanplay', 'anime', '$animeId');
                await tx.insert('media_snapshots', {
                  'id': stableMediaId('classic-cache', [ref.toJson(), cached]),
                  'object_id': await _object(tx, ref),
                  'language': cached['language'],
                  'fetched_at': cached['fetchedAt'] ?? DateTime.now().toUtc().toIso8601String(),
                  'fields': jsonEncode({
                    'ref': ref.toJson(), 'metadata': cached['fields'],
                    'language': cached['language'], 'fetchedAt': cached['fetchedAt'],
                    'receivedAt': DateTime.now().toUtc().toIso8601String(),
                    'source': 'classic_cache', 'origin': 'classic_history',
                  })
                }, conflictAlgorithm: ConflictAlgorithm.ignore);
              }
            }
            final previous = await tx.rawQuery(
                'SELECT o.* FROM media_classic_current c JOIN media_classic_observations o ON o.id=c.observation_id WHERE c.location_id=?',
                [location['id']]);
            if (previous.isNotEmpty &&
                previous.single['fingerprint'] == fingerprint) {
              return;
            }
            // A binding Nipa already revoked (unbind_batch on a classic_match
            // binding) stays as that revocation recorded it.
            if (previous.isNotEmpty &&
                previous.single['binding_id'] != null &&
                (await tx.query('media_bindings',
                        columns: ['id'],
                        where: "id=? AND status='accepted'",
                        whereArgs: [previous.single['binding_id']]))
                    .isNotEmpty) {
              await tx.update('media_bindings', {'status': 'revoked'},
                  where: 'id=?', whereArgs: [previous.single['binding_id']]);
              await _audit(tx, previous.single['binding_id'] as String,
                  {'reason': 'Classic matching observation superseded.'},
                  Invocation(origin: 'classic_history'), event: 'unbind');
            }
            final observationId = newMediaId('classic-observation');
            final at = DateTime.now().toUtc();
            String? bindingId;
            final animeId = row['animeId'] as int?,
                episodeId = row['episodeId'] as int?;
            final eligible = eligibleClassicHistory(row);
            final matched = eligible &&
                animeId != null &&
                animeId > 0 &&
                episodeId != null &&
                episodeId > 0 &&
                (row['animeName'] as String).isNotEmpty &&
                row['episodeTitle'] != null;
            if (matched) {
              final work = MetadataRecord(
                  ref: ExternalRef('dandanplay', 'anime', '$animeId'),
                  title: row['animeName'] as String,
                  kind: 'anime',
                  language: 'und',
                  order: 'provider',
                  fetchedAt: at);
              final episode = MetadataRecord(
                  ref: ExternalRef('dandanplay', 'episode', '$episodeId',
                      scope: 'anime/$animeId'),
                  title: row['episodeTitle'] as String,
                  kind: 'episode',
                  language: 'und',
                  order: 'provider',
                  fetchedAt: at);
              final workId = await _classicLocal(tx, 'work', work, null);
              final releaseId =
                  await _classicLocal(tx, 'release', work, workId);
              final episodeLocalId =
                  await _classicLocal(tx, 'episode', episode, releaseId);
              for (final pair in [
                (workId, work),
                (releaseId, work),
                (episodeLocalId, episode)
              ]) {
                final objectId = await _object(tx, pair.$2.ref);
                final existing = await tx.query('media_bindings',
                    where: 'entity_id=? AND object_id=? AND status=?',
                    whereArgs: [pair.$1, objectId, 'accepted']);
                if (existing.isEmpty) {
                  await _classicBinding(
                      tx, pair.$1, pair.$2, observationId, at);
                }
              }
              for (final record in [work, episode]) {
                await tx.insert('media_snapshots', {
                  'id': stableMediaId(
                      'classic-snapshot', [observationId, record.ref.toJson()]),
                  'object_id': await _object(tx, record.ref),
                  'language': record.language,
                  'fetched_at': at.toIso8601String(),
                  'fields': jsonEncode(
                      {...record.toJson(), 'source': 'classic_match',
                        'receivedAt': at.toUtc().toIso8601String(), 'origin': 'classic_history'})
                });
              }
              // A readback of our durable projection is a delivery fact, not a new Classic decision.
              final projections = await tx.query('media_projection_outbox',
                  where: 'file_id=? AND state IN (?,?)',
                  whereArgs: [fileId, 'pending', 'delivered'],
                  orderBy: 'binding_revision DESC',
                  limit: 1);
              final projected = projections.isEmpty
                  ? <String, Object?>{}
                  : decodeMediaJson(projections.single['payload']);
              final echo = projected['animeId'] == animeId &&
                  projected['episodeId'] == episodeId;
              if (!echo) {
                bindingId = await _classicBinding(
                    tx, fileId, episode, observationId, at);
                await tx.insert(
                    'media_file_episodes',
                    {
                      'file_id': fileId,
                      'episode_id': episodeLocalId,
                      'relation': 'exact',
                      'ordinal': 0,
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore);
              }
              evidence['provenance'] =
                  echo ? 'next_projection_readback' : 'classic_match';
            }
            final oldLegacy = await tx.query('media_legacy_history',
                where: 'location_id=?', whereArgs: [location['id']]);
            await tx.insert('media_classic_observations', {
              'id': observationId,
              'location_id': location['id'],
              'fingerprint': fingerprint,
              'payload': jsonEncode({
                ...evidence,
                if (previous.isEmpty && oldLegacy.isNotEmpty)
                  'priorLegacyEvidence':
                      decodeMediaJson(oldLegacy.single['payload'])
              }),
              'binding_id': bindingId,
              'observed_at': at.toIso8601String(),
            });
            await tx.insert(
                'media_classic_current',
                {
                  'location_id': location['id'],
                  'observation_id': observationId
                },
                conflictAlgorithm: ConflictAlgorithm.replace);
            // Preserve the released legacy evidence verbatim; new observations carry subsequent changes.
            await tx.insert(
                'media_legacy_history',
                {
                  'location_id': location['id'],
                  'fingerprint': fingerprint,
                  'payload':
                      jsonEncode({...evidence, 'provenance': 'legacy_unknown'})
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
            await _pruneFileLinks(tx, fileId);
          }));
    }
    if (reconcileMissing) {
      final locators = history.map((row) => row['filePath']).toSet();
      final current = await database.rawQuery(
          'SELECT l.locator FROM media_classic_current c JOIN media_locations l ON l.id=c.location_id WHERE l.owner_device_id=?',
          [ownerDeviceId]);
      final removed =
          current.where((row) => !locators.contains(row['locator'])).toList();
      if (removed.isNotEmpty) {
        await importLegacy([
          for (final row in removed)
            {'filePath': row['locator'], 'animeName': '', 'episodeTitle': null}
        ], reconcileMissing: false);
      }
    }
    return history.length;
  }

  /// Where each of a file's episode links comes from, by episode ID: one
  /// entry per accepted file binding that stands behind the link
  /// (`classic_match`, or an explicit binding with `boundBy` and the
  /// `origin` of the invocation that made it), and `local_catalog` for a link
  /// made through `localEpisodeIds`. A link with no accepted binding behind
  /// it and no such relation has an empty list.
  Future<Map<String, List<JsonMap>>> linkSources(String fileId,
      {DatabaseExecutor? db}) async {
    final executor = db ?? database;
    final id = await canonicalFileId(executor, fileId);
    final links = await executor.query('media_file_episodes',
        where: 'file_id=?', whereArgs: [id], orderBy: 'ordinal,episode_id');
    final result = <String, List<JsonMap>>{};
    for (final link in links) {
      final episodeId = link['episode_id'] as String;
      final sources = <JsonMap>[];
      if (link['relation'] == 'local_catalog') {
        sources.add({'source': 'local_catalog'});
      }
      for (final binding in await executor.rawQuery(
          'SELECT f.id,f.source,f.bound_by FROM media_bindings f '
          "WHERE f.entity_id=? AND f.status='accepted' AND EXISTS ("
          'SELECT 1 FROM media_bindings e WHERE e.entity_id=? AND e.status=\'accepted\' AND e.object_id=f.object_id) '
          'ORDER BY f.created_at,f.id',
          [id, episodeId])) {
        String? origin;
        for (final row in await executor.query('media_evidence',
            columns: ['payload'],
            where: 'binding_id=?',
            whereArgs: [binding['id']],
            orderBy: 'created_at,id')) {
          final payload = decodeMediaJson(row['payload']);
          if (payload['event'] == 'bind') origin = payload['origin'] as String?;
        }
        sources.add({
          'bindingId': binding['id'],
          'source': binding['source'],
          'boundBy': binding['bound_by'],
          if (origin != null) 'origin': origin,
        });
      }
      result[episodeId] = sources;
    }
    return result;
  }

  Future<String> _classicLocal(DatabaseExecutor tx, String kind,
      MetadataRecord record, String? parent) async {
    final owners = await tx.rawQuery(
        'SELECT DISTINCT e.id FROM media_entities e JOIN media_bindings b ON b.entity_id=e.id WHERE e.kind=? AND b.object_id=? AND b.status=?',
        [kind, stableMediaId('object', record.ref.toJson()), 'accepted']);
    if (owners.length > 1) {
      throw Failure(FailureCode.conflict,
          'Classic external object has multiple local $kind owners: ${owners.map((row) => row['id']).join(', ')}. No owner was selected.');
    }
    if (owners.isNotEmpty) return owners.first['id'] as String;
    return _materialize(tx, kind, record, parent);
  }

  Future<String> _classicBinding(DatabaseExecutor tx, String entityId,
      MetadataRecord record, String observationId, DateTime at) async {
    final objectId = await _object(tx, record.ref);
    final id = stableMediaId('classic-binding', [observationId, entityId]);
    await tx.insert('media_bindings', {
      'id': id,
      'entity_id': entityId,
      'object_id': objectId,
      'relation': record.kind == 'episode' ? 'exact' : 'contains',
      'scope': jsonEncode({
        'order': 'provider',
        'season': null,
        'cour': null,
        'numbers': <String>[],
        'startMs': null,
        'endMs': null
      }),
      'status': 'accepted',
      'source': 'classic_match',
      'revision': 0,
      'created_at': at.toIso8601String(),
    });
    await tx.insert('media_evidence', {
      'id': newMediaId('evidence'),
      'binding_id': id,
      'source': 'classic_match',
      'payload': jsonEncode(
          {'observationId': observationId, 'event': 'classic_match'}),
      'created_at': at.toIso8601String()
    });
    return id;
  }

  Future<void> _pruneFileLinks(DatabaseExecutor tx, String fileId) async {
    await tx.rawDelete(
        'DELETE FROM media_file_episodes WHERE file_id=? AND relation<>\'local_catalog\' AND NOT EXISTS ('
        'SELECT 1 FROM media_bindings f JOIN media_bindings e ON e.object_id=f.object_id '
        'WHERE f.entity_id=? AND f.status=\'accepted\' AND e.entity_id=media_file_episodes.episode_id AND e.status=\'accepted\')',
        [fileId, fileId]);
  }

  Future<String> _object(DatabaseExecutor tx, ExternalRef ref) async {
    final id = stableMediaId('object', ref.toJson());
    await tx.insert(
        'media_external_objects',
        {
          'id': id,
          'provider': ref.provider,
          'object_type': ref.objectType,
          'external_id': ref.externalId,
          'scope': ref.scope
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return id;
  }

  Future<String> _materialize(DatabaseExecutor tx, String kind,
      MetadataRecord record, String? parent) async {
    final id = stableMediaId(kind, record.ref.toJson());
    await tx.insert(
        'media_entities',
        {
          'id': id,
          'kind': kind,
          'parent_id': parent,
          'revision': 0,
          'attributes': jsonEncode({
            'title': record.title,
            'type': record.episodeType,
            'number': record.number,
            'season': record.season,
            'order': record.order
          })
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    final existing = await entity(id, db: tx);
    if (existing['parent_id'] != parent) {
      throw const Failure(FailureCode.conflict,
          'External object already belongs to another local release.');
    }
    return id;
  }

  Future<String> _bindRecord(
      DatabaseExecutor tx,
      String entityId,
      MetadataRecord record,
      String relation,
      JsonMap scope,
      String actor,
      String source,
      Invocation invocation,
      String requestKey,
      int revision,
      {bool saveMetadata = true}) async {
    final objectId = await _object(tx, record.ref);
    final accepted = await tx.query('media_bindings',
        where: 'entity_id = ? AND object_id = ? AND status = ? AND source != ?',
        whereArgs: [entityId, objectId, 'accepted', 'classic_match']);
    if (accepted.isNotEmpty) {
      final binding = accepted.single;
      if (binding['relation'] != relation ||
          stableMediaId('scope', decodeMediaJson(binding['scope'])) !=
              stableMediaId('scope', scope)) {
        throw const Failure(FailureCode.conflict,
            'Existing binding has different relation or scope; unbind it explicitly.');
      }
      return binding['id'] as String;
    }
    final id = stableMediaId('binding', [requestKey, entityId, objectId]);
    await tx.insert('media_bindings', {
      'id': id,
      'entity_id': entityId,
      'object_id': objectId,
      'relation': relation,
      'scope': jsonEncode(scope),
      'status': 'accepted',
      'source': source,
      'bound_by': actor,
      'revision': revision,
      'invocation_id': invocation.id,
      'created_at': _now
    });
    if (saveMetadata) await _snapshot(tx, objectId, record);
    return id;
  }

  Future<String> _snapshot(
      DatabaseExecutor tx, String objectId, MetadataRecord record) async {
    final invocation = BodyChanges.invocation;
    final id = stableMediaId('snapshot',
        [objectId, record.language, record.fetchedAt.toIso8601String()]);
    final existing = await tx.query('media_snapshots', columns: ['id'], where: 'id=?', whereArgs: [id]);
    await tx.insert(
        'media_snapshots',
        {
          'id': id,
          'object_id': objectId,
          'language': record.language,
          'fetched_at': record.fetchedAt.toUtc().toIso8601String(),
          'fields': jsonEncode({...record.toJson(), 'receivedAt': _now,
            'origin': invocation?.origin, 'invocationId': invocation?.id})
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (existing.isEmpty) {
      BodySignals.changed('media.assets.changed', objectId,
          {'kind': 'metadata', 'snapshotId': id, 'provider': record.ref.provider,
            'changedFields': record.toJson().keys.toList()});
    }
    return id;
  }

  Future<String> saveSnapshot(MetadataRecord record) => _transaction(
      (tx) async => _snapshot(tx, await _object(tx, record.ref), record));

  Future<JsonMap> importSnapshots(JsonMap input, Invocation invocation) =>
      _transaction((tx) async {
        final key = stableMediaId(
            'snapshot-operation', [invocation.origin, input['requestId']]);
        final fingerprint = stableMediaId('input', input);
        final saved = await operation(key, fingerprint, db: tx);
        if (saved != null) return saved;
        final entries = (input['entries'] as List).cast<JsonMap>();
        if (entries.isEmpty) {
          throw const Failure(
              FailureCode.invalidInput, 'entries must not be empty.');
        }
        final receivedAt = _now;
        final results = <JsonMap>[];
        for (var index = 0; index < entries.length; index++) {
          try {
            final entry = entries[index];
            final ref = canonicalExternalRef(
                Map<String, Object?>.from(entry['ref'] as Map));
            final objectId = stableMediaId('object', ref.toJson());
            final bound = await tx.query('media_bindings',
                where: 'object_id=? AND status=?',
                whereArgs: [objectId, 'accepted'],
                limit: 1);
            if (bound.isEmpty) {
              throw const Failure(FailureCode.invalidInput,
                  'Snapshot requires an accepted external identity; bind ref first.');
            }
            final fields = Map<String, Object?>.from(entry['fields'] as Map);
            validateMetadataFields(fields);
            final fetchedAt = entry['fetchedAt'] as String?;
            if (fetchedAt != null && DateTime.tryParse(fetchedAt) == null) {
              throw const Failure(FailureCode.invalidInput,
                  'fetchedAt must be an ISO-8601 timestamp.');
            }
            final id = stableMediaId('imported-snapshot', [key, index]);
            final payload = <String, Object?>{
              'ref': ref.toJson(),
              'metadata': {
                ...fields,
                if (fields['rating'] case final Map rating)
                  'rating': {...rating, 'source': ref.provider},
              },
              'language': entry['language'],
              'fetchedAt': fetchedAt,
              'receivedAt': receivedAt,
              'source': 'submitted_snapshot',
              'actor': invocation.origin == 'gui' ? 'user' : 'agent',
              'origin': invocation.origin,
              'invocationId': invocation.id,
              'url': entry['url'],
            };
            await tx.insert('media_snapshots', {
              'id': id,
              'object_id': objectId,
              'language': entry['language'],
              'fetched_at': receivedAt,
              'fields': jsonEncode(payload)
            });
            results.add({'index': index, 'snapshotId': id, ...payload});
          } on Failure catch (error) {
            throw Failure(error.code, 'Entry $index: ${error.message}',
                violations: [
                  SchemaViolation('/entries/$index', error.message)
                ]);
          }
        }
        final result = <String, Object?>{'entries': results};
        await tx.insert('media_binding_operations', {
          'id': key,
          'fingerprint': fingerprint,
          'result': jsonEncode(result)
        });
        return result;
      });

  Future<List<String>> _metadataEntities(String id) async {
    final target = await entity(id);
    if (target['kind'] != 'work' && target['kind'] != 'release') return [id];
    final workId =
        target['kind'] == 'work' ? id : target['parent_id'] as String;
    final releases = await database.query('media_entities',
        columns: ['id'],
        where: 'kind=? AND parent_id=?',
        whereArgs: ['release', workId],
        orderBy: 'id');
    return [workId, for (final row in releases) row['id'] as String];
  }

  Future<List<JsonMap>> _metadataSnapshots(List<String> ids,
          {bool acceptedOnly = true}) =>
      database.rawQuery(
          'SELECT DISTINCT s.*,o.provider,o.object_type,o.external_id,o.scope AS object_scope,b.entity_id FROM media_snapshots s '
          'JOIN media_external_objects o ON o.id=s.object_id JOIN media_bindings b ON b.object_id=o.id '
          'WHERE b.entity_id IN (${List.filled(ids.length, '?').join(',')}) ${acceptedOnly ? 'AND b.status=\'accepted\'' : ''} '
          'ORDER BY CASE WHEN json_extract(s.fields,\'\$.source\')=\'classic_match\' THEN 1 ELSE 0 END, '
          'CASE WHEN b.entity_id=? THEN 0 ELSE 1 END,s.fetched_at DESC,s.id DESC',
          [...ids, ids.first]);

  Future<List<JsonMap>> metadataSnapshots(String id) async {
    final rows = await _metadataSnapshots(await _metadataEntities(id),
        acceptedOnly: false);
    final seen = <String>{};
    return [
      for (final row in rows)
        if (seen.add(row['id'] as String))
          {
            'snapshotId': row['id'],
            'entityId': row['entity_id'],
            'ref': {
              'provider': row['provider'],
              'objectType': row['object_type'],
              'externalId': row['external_id'],
              'scope': row['object_scope']
            },
            'language': row['language'],
            'recordedAt': row['fetched_at'],
            'record': decodeMediaJson(row['fields']),
          }
    ];
  }

  Future<List<JsonMap>> pendingProjections({String? fileId}) => database.query(
      'media_projection_outbox',
      where: fileId == null ? 'state = ?' : 'state IN (?,?) AND file_id = ?',
      whereArgs: [
        'pending',
        if (fileId != null) ...['conflict', fileId]
      ],
      orderBy: 'binding_revision');
  Future<void> finishProjection(String id, String state) =>
      _transaction((tx) async {
        final previous = (await tx.query('media_projection_outbox',
            where: 'id=?', whereArgs: [id])).single;
        await tx.update('media_projection_outbox', {'state': state},
            where: 'id=?', whereArgs: [id]);
        if (state == 'conflict' && previous['state'] != state) {
          final invocation = BodyChanges.invocation;
          await tx.insert('body_changes', {
            'at': _now, 'type': 'identity.projection_conflict',
            'subject_id': previous['file_id'],
            'actor': 'system', 'origin': invocation?.origin ?? 'application',
            'invocation_id': invocation?.id,
            'facts': jsonEncode({'projectionId': id, 'fileId': previous['file_id'],
              'before': previous['state'], 'after': state,
              'reason': 'Classic matching differs from this projection; neither identity was discarded.'}),
          });
        }
      });

  Future<JsonMap> identity(String id) async {
    id = await canonicalFileId(database, id);
    final row = await entity(id);
    final bindings = await database.rawQuery(
        'SELECT b.*, o.provider, o.object_type, o.external_id, o.scope AS object_scope FROM media_bindings b JOIN media_external_objects o ON o.id = b.object_id WHERE b.entity_id = ? ORDER BY b.created_at, b.id',
        [id]);
    return {
      'entity': row,
      'bindings': [
        for (final b in bindings) {...b, 'scope': decodeMediaJson(b['scope'])}
      ],
      'locations': await locations(id),
      'episodes': await database
          .query('media_file_episodes', where: 'file_id = ?', whereArgs: [id]),
      'evidence': await database.rawQuery(
          'SELECT e.* FROM media_evidence e JOIN media_bindings b ON b.id = e.binding_id WHERE b.entity_id = ?',
          [id]),
      'metadata': await mergedMetadata(id)
    };
  }

  Future<List<JsonMap>> classicObservations(String fileId,
      {bool currentOnly = false}) async {
    final rows = await database.rawQuery(
        'SELECT o.*,c.observation_id FROM media_classic_observations o '
        'JOIN media_locations l ON l.id=o.location_id LEFT JOIN media_classic_current c ON c.location_id=l.id '
        'WHERE l.file_id=? ${currentOnly ? 'AND o.id=c.observation_id' : ''} ORDER BY o.observed_at,o.id',
        [fileId]);
    return [
      for (final row in rows)
        {
          'observationId': row['id'],
          'locationId': row['location_id'],
          'current': row['id'] == row['observation_id'],
          'observedAt': row['observed_at'],
          'bindingId': row['binding_id'],
          ...decodeMediaJson(row['payload'])
        }
    ];
  }

  Future<List<JsonMap>> identityConflicts(String id) async {
    final conflicts = <JsonMap>[];
    final classic = await classicObservations(id, currentOnly: true);
    final bindings = await database.rawQuery(
        'SELECT b.id,b.source,o.external_id,o.scope,o.provider FROM media_bindings b '
        'JOIN media_external_objects o ON o.id=b.object_id WHERE b.entity_id=? AND b.status=? AND b.source!=?',
        [id, 'accepted', 'classic_match']);
    for (final observation
        in classic.where((o) => o['provenance'] == 'classic_match')) {
      for (final binding in bindings) {
        bool same;
        if (binding['provider'] == 'dandanplay') {
          same = binding['external_id'] == '${observation['episodeId']}' &&
              binding['scope'] == 'anime/${observation['animeId']}';
        } else {
          final shared = await database.rawQuery(
              'SELECT 1 FROM media_bindings a JOIN media_bindings b ON b.entity_id=a.entity_id '
              'JOIN media_external_objects o ON o.id=b.object_id JOIN media_entities e ON e.id=a.entity_id '
              'WHERE a.object_id=(SELECT object_id FROM media_bindings WHERE id=?) AND b.status=? AND a.status=? '
              'AND e.kind=? AND o.provider=? AND o.external_id=? AND o.scope=?',
              [
                binding['id'],
                'accepted',
                'accepted',
                'episode',
                'dandanplay',
                '${observation['episodeId']}',
                'anime/${observation['animeId']}'
              ]);
          same = shared.isNotEmpty;
        }
        if (!same) {
          conflicts.add({
            'type': 'different_episode',
            'classicObservationId': observation['observationId'],
            'bindingId': binding['id'],
            'source': binding['source'],
            'provider': binding['provider'],
            'externalId': binding['external_id'],
            'classicAnimeId': observation['animeId'],
            'classicEpisodeId': observation['episodeId']
          });
        }
      }
    }
    for (final projection in await database.query('media_projection_outbox',
        where: 'file_id=? AND state=?', whereArgs: [id, 'conflict'])) {
      conflicts.add({
        'type': 'classic_projection',
        'projectionId': projection['id'],
        'payload': decodeMediaJson(projection['payload'])
      });
    }
    return conflicts;
  }

  Future<JsonMap> mergedMetadata(String entityId) async {
    entityId = await canonicalFileId(database, entityId);
    final ids = await _metadataEntities(entityId);
    final rows = await _metadataSnapshots(ids);
    final fields = <String, Object?>{}, provenance = <String, Object?>{};
    for (final id in ids) {
      final local = await entity(id);
      final attrs = local['attributes'] as JsonMap;
      if (attrs['localOnly'] == true && !fields.containsKey('title')) {
        fields['title'] = attrs['title'];
        provenance['title'] = {'provider': 'local', 'source': 'local_catalog',
          'language': 'und', 'entityId': id};
      }
    }
    final ratings = <JsonMap>[];
    final seenRatings = <String>{}, seenSubmitted = <String>{};
    for (final row in rows) {
      final record = decodeMediaJson(row['fields']);
      final values = record['metadata'] == null
          ? {
              for (final key in [
                'title',
                'originalTitle',
                'overview',
                'imageUrl',
                'year'
              ])
                key: record[key]
            }
          : Map<String, Object?>.from(record['metadata'] as Map);
      final sourceKey = '${row['object_id']}/${row['language']}';
      if (record['source'] == 'submitted_snapshot' &&
          !seenSubmitted.add(sourceKey)) {
        continue;
      }
      if (values['rating'] case final Map rating
          when seenRatings.add(sourceKey)) {
        ratings.add({
          ...Map<String, Object?>.from(rating),
          'source': row['provider'],
          'snapshotId': row['id'],
          'language': row['language'],
          'ref': {
            'provider': row['provider'],
            'objectType': row['object_type'],
            'externalId': row['external_id'],
            'scope': row['object_scope']
          },
        });
      }
      for (final field in values.keys) {
        int languageRank(Object? language, Object? value) {
          if (value is String && RegExp(r'[\u3041-\u3096\u30a1-\u30fa]').hasMatch(value)) return 2;
          return switch ((language as String? ?? '').toLowerCase()) {
            'zh-cn' || 'zh-hans' || 'zh-hans-cn' => 0,
            'zh' => 1,
            _ => 2,
          };
        }
        final preferChinese = (field == 'title' || field == 'overview') &&
            fields.containsKey(field) && languageRank(row['language'], values[field]) <
                languageRank((provenance[field] as Map)['language'], fields[field]);
        if (values[field] != null &&
            values[field] != '' &&
            (!fields.containsKey(field) || preferChinese || (provenance[field] as Map?)?['source'] == 'local_catalog')) {
          fields[field] = values[field];
          provenance[field] = {
            'provider': row['provider'],
            'source': record['source'] ?? 'provider_snapshot',
            'language': row['language'],
            'fetchedAt': record['fetchedAt'] ?? row['fetched_at'],
            'recordedAt': row['fetched_at'],
            'snapshotId': row['id'],
            'entityId': row['entity_id'],
            'actor': record['actor'],
            'origin': record['origin'],
            'invocationId': record['invocationId'],
          };
        }
      }
    }
    final edited = <String>{};
    for (final row in await database.rawQuery(
        'SELECT * FROM media_overrides WHERE entity_id IN (${List.filled(ids.length, '?').join(',')}) '
        'ORDER BY changed_at DESC, CASE WHEN entity_id=? THEN 0 ELSE 1 END, entity_id',
        [...ids, ids.first])) {
      if (row['mode'] == 'correction' &&
          rows.any((snapshot) =>
              (snapshot['fetched_at'] as String)
                  .compareTo(row['changed_at'] as String) >
              0)) {
        continue;
      }
      if (!edited.add(row['field'] as String)) continue;
      fields[row['field'] as String] = jsonDecode(row['value'] as String);
      provenance[row['field'] as String] = {
        'provider': row['actor'],
        'actor': row['actor'],
        'changedAt': row['changed_at'],
        'invocationId': row['invocation_id'],
        'origin': row['origin'],
        'mode': row['mode']
      };
    }
    return {'fields': fields, 'provenance': provenance, 'ratings': ratings};
  }

  Future<void> overrideField(
          String id, String field, Object? value, Invocation invocation,
          {String mode = 'persistent', String? language}) async {
    final languageField = '${field}Language';
    final ids = await _metadataEntities(await canonicalFileId(database, id));
    final hasLanguage = (await database.query('media_overrides',
        where: 'entity_id IN (${List.filled(ids.length, '?').join(',')}) AND field=?',
        whereArgs: [...ids, languageField])).isNotEmpty;
    await overrideFields([
        {'entityId': id, 'field': field, 'value': value, 'mode': mode},
        if ((field == 'title' || field == 'overview') && (language != null || hasLanguage))
          {
            'entityId': id,
            'field': '${field}Language',
            'value': language,
            'mode': mode
          }
      ], invocation);
  }

  Future<void> overrideFields(
      List<JsonMap> entries, Invocation invocation) async {
    final edits = await overrideEdits(entries, invocation);
    await _transaction((tx) => writeOverrides(tx, edits));
    announceOverrides(edits, invocation);
  }

  /// The entities that share one metadata view: a work and its releases;
  /// any other entity stands alone.
  Future<List<String>> metadataFamily(String id) async =>
      _metadataEntities(await canonicalFileId(database, id));

  /// Override rows resolved against the database, ready for [writeOverrides]
  /// inside a transaction of the caller's. [created] names entities that
  /// transaction is about to create; they stand alone.
  Future<List<(JsonMap, List<String>)>> overrideEdits(
      List<JsonMap> entries, Invocation invocation,
      {Set<String> created = const {}}) async {
    final edits = <(JsonMap, List<String>)>[];
    for (final entry in entries) {
      final raw = entry['entityId'] as String;
      final isNew = created.contains(raw);
      final id = isNew ? raw : await canonicalFileId(database, raw);
      final ids = isNew ? [id] : await _metadataEntities(id);
      final edit = <String, Object?>{
        'entity_id': id,
        'field': entry['field'],
        'value': jsonEncode(entry['value']),
        'mode': entry['mode'] ?? 'persistent',
        'actor': invocation.origin == 'gui' ? 'user' : 'agent',
        'origin': invocation.origin,
        'invocation_id': invocation.id,
        'changed_at': _now
      };
      edits.add((edit, ids));
    }
    return edits;
  }

  Future<void> writeOverrides(
      DatabaseExecutor tx, List<(JsonMap, List<String>)> edits) async {
    for (final (edit, ids) in edits) {
      await tx.insert('media_metadata_edits', edit);
      if (edit['mode'] == 'clear') {
        await tx.delete('media_overrides',
            where:
                'entity_id IN (${List.filled(ids.length, '?').join(',')}) AND field=?',
            whereArgs: [...ids, edit['field']]);
      } else {
        await tx.insert('media_overrides', edit,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  void announceOverrides(
      List<(JsonMap, List<String>)> edits, Invocation invocation) {
    for (final (edit, _) in edits) {
      BodySignals.changed('media.assets.changed', edit['entity_id'] as String,
          {'kind': 'metadata', 'field': edit['field'], 'mode': edit['mode'],
            'changedFields': [edit['field']], 'origin': invocation.origin});
    }
  }

  Future<List<JsonMap>> library({String? query}) async {
    final works = await database.query('media_entities',
        where: 'kind = ?', whereArgs: ['work'], orderBy: 'id');
    final results = <JsonMap>[];
    for (final work in works) {
      if (decodeMediaJson(work['attributes'])['removed'] == true) continue;
      final id = work['id'] as String;
      final metadata = await mergedMetadata(id);
      final fields = metadata['fields'] as JsonMap;
      final title = fields['title'] as String? ??
          decodeMediaJson(work['attributes'])['title'] as String;
      if (query != null &&
          !title.toLowerCase().contains(query.toLowerCase()) &&
          !(fields['originalTitle'] as String? ?? '')
              .toLowerCase()
              .contains(query.toLowerCase())) {
        continue;
      }
      results.add({
        'workId': id,
        'title': title,
        'metadata': metadata,
        'releases': await _releases(id, metadata)
      });
    }
    return results;
  }

  Future<List<JsonMap>> _releases(String workId, JsonMap metadata) async {
    final releases = await database.query('media_entities',
        where: 'parent_id = ? AND kind = ?', whereArgs: [workId, 'release']);
    return [
      for (final release in releases)
        if (decodeMediaJson(release['attributes'])['removed'] != true)
        {
          ...release,
          'attributes': decodeMediaJson(release['attributes']),
          'metadata': metadata,
          'episodes': await _episodes(release['id'] as String)
        }
    ];
  }

  Future<List<JsonMap>> _episodes(String releaseId) async {
    final episodes = await database.query('media_entities',
        where: 'parent_id = ? AND kind = ?', whereArgs: [releaseId, 'episode']);
    final ordered = episodes.where((e) => decodeMediaJson(e['attributes'])['removed'] != true).toList()
      ..sort((a, b) {
        final aa = decodeMediaJson(a['attributes']),
            bb = decodeMediaJson(b['attributes']);
        final type = (aa['type'] == 'regular' ? 0 : 1)
            .compareTo(bb['type'] == 'regular' ? 0 : 1);
        if (type != 0) return type;
        final an = double.tryParse(aa['number'] as String? ?? ''),
            bn = double.tryParse(bb['number'] as String? ?? '');
        return an != null && bn != null
            ? an.compareTo(bn)
            : (aa['number'] as String? ?? '')
                .compareTo(bb['number'] as String? ?? '');
      });
    return [
      for (final episode in ordered)
        {
          ...episode,
          'attributes': decodeMediaJson(episode['attributes']),
          'metadata': await mergedMetadata(episode['id'] as String),
          'files': await database.rawQuery(
              'SELECT f.*,l.locator,l.source,fe.relation,fe.ordinal,fe.start_ms,fe.end_ms FROM media_file_episodes fe JOIN media_entities f ON f.id=fe.file_id JOIN media_locations l ON l.file_id=f.id WHERE fe.episode_id = ?',
              [episode['id']])
        }
    ];
  }

  Future<JsonMap?> operation(String key, String fingerprint,
      {DatabaseExecutor? db}) async {
    final rows = await (db ?? database)
        .query('media_binding_operations', where: 'id = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    if (rows.single['fingerprint'] != fingerprint) {
      throw const Failure(FailureCode.conflict,
          'requestId was already used with different input.');
    }
    return decodeMediaJson(rows.single['result']);
  }

  Future<void> _audit(DatabaseExecutor tx, String bindingId, JsonMap input,
      Invocation invocation,
      {String event = 'bind', JsonMap? file, JsonMap? extra}) async {
    await tx.insert('media_evidence', {
      'id': newMediaId('evidence'),
      'binding_id': bindingId,
      'source': 'explicit_binding',
      'created_at': _now,
      'payload': jsonEncode({
        ...?extra,
        'event': event,
        'reason': input['reason'],
        'evidence': input['evidence'] ?? [],
        'boundBy': invocation.origin == 'gui' ? 'user' : 'agent',
        'invocationId': invocation.id,
        'origin': invocation.origin,
        if (file != null) ...{
          'fileRevision': file['revision'],
          'probe': (file['attributes'] as JsonMap)['probe'],
          if ((file['attributes'] as JsonMap)['remoteSource'] != null) ...{
            'remoteSource': (file['attributes'] as JsonMap)['remoteSource'],
            'locator': input['verifiedPath'],
          }
        }
      })
    });
  }

  Future<void> _checkObjects(
      DatabaseExecutor tx, String id, List<MetadataRecord> records) async {
    final kind = (await entity(id, db: tx))['kind'];
    if (kind != 'file') {
      for (final record in records) {
        final owners = await tx.rawQuery(
            'SELECT b.entity_id FROM media_bindings b JOIN media_entities e ON e.id=b.entity_id '
            'WHERE b.object_id=? AND b.status=? AND e.kind=? AND b.entity_id!=?',
            [
              stableMediaId('object', record.ref.toJson()),
              'accepted',
              kind,
              id
            ]);
        if (owners.isNotEmpty) {
          throw Failure(FailureCode.conflict,
              'External object is already bound to local $kind ${owners.first['entity_id']}.');
        }
      }
    }
    final rows = await tx.rawQuery(
        'SELECT o.* FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id '
        'WHERE b.entity_id=? AND b.status=? AND o.provider=? AND b.source!=\'classic_match\'',
        [id, 'accepted', records.first.ref.provider]);
    final expected = {
      for (final r in records) stableMediaId('object', r.ref.toJson())
    };
    if (rows.any((row) => !expected.contains(row['id']))) {
      throw const Failure(FailureCode.conflict,
          'Conflicting accepted identity from this source; unbind it explicitly.');
    }
  }

  Future<String> _local(DatabaseExecutor tx, String? id, String kind,
      MetadataRecord record, String? parent) async {
    if (id == null) return _materialize(tx, kind, record, parent);
    final existing = await entity(id, db: tx);
    if (existing['kind'] != kind || existing['parent_id'] != parent) {
      throw Failure(FailureCode.conflict,
          'Expected local entity $id to be kind=$kind with parentId=$parent; '
          'actual kind=${existing['kind']}, parentId=${existing['parent_id']}. '
          'entityId identifies the entry itself; workId/releaseId identify its parents. '
          'Omit local IDs to create/reuse the hierarchy by catalogue refs.');
    }
    return id;
  }

  Future<JsonMap> bindBatch(List<JsonMap> entries, String key,
          String fingerprint, Invocation invocation) =>
      _filesChanged((newFiles) => _transaction((tx) async {
            final saved = await operation(key, fingerprint, db: tx);
            if (saved != null) return saved;
            final results = <JsonMap>[];
            for (var index = 0; index < entries.length; index++) {
              final entry = {...entries[index],
                if (entries[index]['entityId'] is String)
                  'entityId': await canonicalFileId(tx, entries[index]['entityId'] as String)};
              try {
                final kind = entry['kind'] as String;
                if (entry.containsKey('ref')) {
                  if (kind == 'file') {
                    results.add(await _bindFileReference(
                        tx, entry, key, invocation, index));
                    continue;
                  }
                  final id = entry['entityId'] as String;
                  final target = await entity(id, db: tx);
                  if (target['kind'] != kind || kind == 'file') {
                    throw const Failure(FailureCode.invalidInput,
                        'Direct binding kind must match the existing work/release/episode.');
                  }
                  final record = MetadataRecord(
                      ref: ExternalRef.fromJson(entry['ref'] as JsonMap),
                      title: '',
                      kind: kind,
                      fetchedAt: DateTime.now().toUtc());
                  await _checkObjects(tx, id, [record]);
                  final binding = await _bindRecord(
                      tx,
                      id,
                      record,
                      kind == 'episode' ? 'exact' : 'contains',
                      {
                        'order': 'unspecified',
                        'season': null,
                        'cour': null,
                        'numbers': <String>[],
                        'startMs': null,
                        'endMs': null
                      },
                      invocation.origin == 'gui' ? 'user' : 'agent',
                      'explicit_binding',
                      invocation,
                      key,
                      0,
                      saveMetadata: false);
                  await _audit(tx, binding, entry, invocation);
                  results.add({
                    'index': index,
                    'workId': kind == 'work'
                        ? id
                        : kind == 'release'
                            ? target['parent_id']
                            : (await entity(target['parent_id'] as String,
                                db: tx))['parent_id'],
                    'releaseId': kind == 'release'
                        ? id
                        : kind == 'episode'
                            ? target['parent_id']
                            : null,
                    'episodeIds': kind == 'episode' ? [id] : <String>[],
                    'fileId': null,
                    'bindingIds': [binding],
                  });
                  continue;
                }
                final work = MetadataRecord.fromJson(entry['work'] as JsonMap);
                final release =
                    MetadataRecord.fromJson(entry['release'] as JsonMap);
                final selected = (entry['episodes'] as List)
                    .cast<JsonMap>()
                    .map(MetadataRecord.fromJson)
                    .toList();
                final workId = await _local(
                    tx,
                    kind == 'work'
                        ? entry['entityId'] as String?
                        : entry['workId'] as String?,
                    'work',
                    work,
                    null);
                final scope = <String, Object?>{
                  'order': release.order,
                  'season': release.season,
                  'cour': null,
                  'numbers': [for (final ep in selected) ep.number],
                  'startMs': entry['startMs'],
                  'endMs': entry['endMs']
                };
                final bindings = <String>[];
                final actor = invocation.origin == 'gui' ? 'user' : 'agent';
                Future<void> bind(String id, MetadataRecord record,
                    String relation, JsonMap bindingScope,
                    {JsonMap? file}) async {
                  final binding = await _bindRecord(
                      tx,
                      id,
                      record,
                      relation,
                      bindingScope,
                      actor,
                      'explicit_binding',
                      invocation,
                      key,
                      ((await entity(id, db: tx))['attributes']
                              as JsonMap)['bindingRevision'] as int? ??
                          0);
                  if (!bindings.contains(binding)) {
                    bindings.add(binding);
                    await _audit(tx, binding, entry, invocation, file: file);
                  }
                }

                final parentScope = {
                  ...scope,
                  'numbers': <String>[],
                  'startMs': null,
                  'endMs': null
                };
                await _checkObjects(tx, workId, [work]);
                await bind(workId, work, 'contains', {
                  ...parentScope,
                  'season': work.season,
                  'order': work.order
                });
                String? releaseId;
                final episodeIds = <String>[];
                if (kind != 'work') {
                  releaseId = await _local(
                      tx,
                      kind == 'release'
                          ? entry['entityId'] as String?
                          : entry['releaseId'] as String?,
                      'release',
                      release,
                      workId);
                  await _checkObjects(tx, releaseId, [release]);
                  await bind(releaseId, release, 'contains', parentScope);
                  for (var i = 0; i < selected.length; i++) {
                    final ep = selected[i];
                    final localIds =
                        (entry['localEpisodeIds'] as List?)?.cast<String>();
                    final id = await _local(
                        tx,
                        kind == 'episode'
                            ? entry['entityId'] as String?
                            : localIds?[i],
                        'episode',
                        ep,
                        releaseId);
                    await _checkObjects(tx, id, [ep]);
                    await bind(id, ep, 'exact', {
                      ...parentScope,
                      'numbers': [ep.number]
                    });
                    episodeIds.add(id);
                  }
                }
                String? fileId;
                if (kind == 'file') {
                  fileId = entry['entityId'] as String? ??
                      await _ensureFile(
                          tx, entry['verifiedPath'] as String, newFiles);
                  final file = await entity(fileId, db: tx);
                  final attrs = file['attributes'] as JsonMap;
                  final links = await tx.query('media_file_episodes',
                      where: 'file_id=?',
                      whereArgs: [fileId],
                      orderBy: 'ordinal');
                  final explicitLinks = <JsonMap>[];
                  for (final link in links) {
                    final bindings = await tx.rawQuery(
                        'SELECT 1 FROM media_bindings f JOIN media_bindings e ON e.object_id=f.object_id WHERE f.entity_id=? AND f.status=? AND f.source!=? AND e.entity_id=? AND e.status=?',
                        [
                          fileId,
                          'accepted',
                          'classic_match',
                          link['episode_id'],
                          'accepted'
                        ]);
                    if (bindings.isNotEmpty) explicitLinks.add(link);
                  }
                  if (explicitLinks.isNotEmpty &&
                      stableMediaId(
                              'links',
                              explicitLinks
                                  .map((row) => row['episode_id'])
                                  .toList()) !=
                          stableMediaId('links', episodeIds)) {
                    throw const Failure(FailureCode.conflict,
                        'File is already linked to different local episodes; unbind it explicitly.');
                  }
                  final previousBindings = await tx.query('media_bindings',
                      where: 'entity_id=? AND status=?',
                      whereArgs: [fileId, 'accepted']);
                  await _checkObjects(tx, fileId, selected);
                  final relation = selected.length == 1 ? 'exact' : 'combined';
                  for (var i = 0; i < selected.length; i++) {
                    await bind(fileId, selected[i], relation, scope, file: {
                      ...file,
                      'attributes': {...attrs, 'probe': entry['probe']}
                    });
                    final link = {
                      'file_id': fileId,
                      'episode_id': episodeIds[i],
                      'relation': relation,
                      'ordinal': i,
                      'start_ms': entry['startMs'],
                      'end_ms': entry['endMs']
                    };
                    final same = explicitLinks
                        .where((row) => row['episode_id'] == episodeIds[i]);
                    if (same.isNotEmpty &&
                        (same.single['relation'] != relation ||
                            same.single['start_ms'] != entry['startMs'] ||
                            same.single['end_ms'] != entry['endMs'])) {
                      throw const Failure(FailureCode.conflict,
                          'Existing file episode relation or interval differs.');
                    }
                    await tx.insert('media_file_episodes', link,
                        conflictAlgorithm: ConflictAlgorithm.ignore);
                  }
                  final probe = entry['probe'] as JsonMap;
                  final oldProbe = attrs['probe'] as JsonMap;
                  if (!isLocationOnlyMediaProbe(oldProbe) &&
                      ['size', 'modifiedAt', 'headMd5']
                          .any((key) => probe[key] != oldProbe[key])) {
                    throw const Failure(FailureCode.conflict,
                        'File changed since indexing; scan again.');
                  }
                  final fileBindings = await tx.query('media_bindings',
                      where: 'entity_id=? AND status=?',
                      whereArgs: [fileId, 'accepted']);
                  final added = fileBindings.any((b) =>
                      !previousBindings.any((old) => old['id'] == b['id']));
                  final revision =
                      (attrs['bindingRevision'] as int) + (added ? 1 : 0);
                  for (final binding in fileBindings.where((b) =>
                      !previousBindings.any((old) => old['id'] == b['id']))) {
                    await tx.update('media_bindings', {'revision': revision},
                        where: 'id=?', whereArgs: [binding['id']]);
                  }
                  await tx.update(
                      'media_entities',
                      {
                        'attributes': jsonEncode({
                          ...attrs,
                          'probe': probe,
                          'bindingRevision': revision
                        })
                      },
                      where: 'id=?',
                      whereArgs: [fileId]);
                  if (added) {
                    await _queueFileProjection(
                        tx, fileId, file['revision'] as int, revision);
                  }
                }
                results.add({
                  'index': index,
                  'workId': workId,
                  'releaseId': releaseId,
                  'episodeIds': episodeIds,
                  'fileId': fileId,
                  if (fileId != null)
                    'classicProjectionId': (await tx.query(
                            'media_projection_outbox',
                            where: 'file_id=? AND binding_revision=?',
                            whereArgs: [
                          fileId,
                          ((await entity(fileId, db: tx))['attributes']
                              as JsonMap)['bindingRevision']
                        ]))
                        .map((p) => p['id'])
                        .firstOrNull,
                  'bindingIds': bindings
                });
              } on Failure catch (error) {
                throw Failure(error.code, 'Entry $index: ${error.message}',
                    violations: [
                      SchemaViolation('/entries/$index', error.message)
                    ]);
              }
            }
            final result = <String, Object?>{'entries': results};
            await tx.insert('media_binding_operations', {
              'id': key,
              'fingerprint': fingerprint,
              'result': jsonEncode(result)
            });
            return result;
          }));

  Future<JsonMap> unbindBatch(List<JsonMap> entries, String key,
          String fingerprint, Invocation invocation) =>
      _transaction((tx) async {
        final saved = await operation(key, fingerprint, db: tx);
        if (saved != null) return saved;
        final results = <JsonMap>[];
        for (var index = 0; index < entries.length; index++) {
          final entry = {...entries[index],
            if (entries[index]['entityId'] is String)
              'entityId': await canonicalFileId(tx, entries[index]['entityId'] as String)};
          try {
            final id = entry['entityId'] as String;
            final entityRow = await entity(id, db: tx);
            // A file's classic_match binding can be named; omitting bindingIds
            // still selects explicit bindings only.
            final bindings = await tx.rawQuery(
                'SELECT b.*,o.provider,o.external_id,o.scope AS object_scope FROM media_bindings b '
                'JOIN media_external_objects o ON o.id=b.object_id WHERE b.entity_id=? AND b.status=?',
                [id, 'accepted']);
            final requested = (entry['bindingIds'] as List?)?.cast<String>();
            if (requested != null &&
                requested.any((bid) => !bindings.any((b) => b['id'] == bid))) {
              throw const Failure(FailureCode.conflict,
                  'bindingIds must belong to this entity and be accepted.');
            }
            if (requested != null &&
                (requested.isEmpty ||
                    requested.toSet().length != requested.length)) {
              throw const Failure(FailureCode.invalidInput,
                  'bindingIds must be nonempty and distinct.');
            }
            final selected = bindings
                .where((b) => requested == null
                    ? b['source'] != 'classic_match'
                    : requested.contains(b['id']))
                .toList();
            final classicSelected =
                selected.where((b) => b['source'] == 'classic_match').toList();
            final explicitSelected =
                selected.where((b) => b['source'] != 'classic_match').toList();
            final linksBefore = [
              for (final link in await tx.query('media_file_episodes',
                  where: 'file_id=?', whereArgs: [id]))
                link['episode_id'] as String
            ];
            for (final binding in selected) {
              await tx.update('media_bindings', {'status': 'revoked'},
                  where: 'id=?', whereArgs: [binding['id']]);
              await _audit(tx, binding['id'] as String, entry, invocation,
                  event: 'unbind',
                  extra: binding['source'] == 'classic_match'
                      ? {'revoked': 'classic_match'}
                      : null);
            }
            final classicFacts = <JsonMap>[];
            if (classicSelected.isNotEmpty) {
              for (final binding in classicSelected) {
                final observed = await tx.rawQuery(
                    'SELECT o.id,o.payload FROM media_classic_observations o '
                    'JOIN media_classic_current c ON c.observation_id=o.id WHERE o.binding_id=?',
                    [binding['id']]);
                for (final observation in observed) {
                  await tx.update(
                      'media_classic_observations',
                      {
                        'payload': jsonEncode({
                          ...decodeMediaJson(observation['payload']),
                          'provenance': 'classic_match_revoked',
                        })
                      },
                      where: 'id=?',
                      whereArgs: [observation['id']]);
                }
              }
              if (entityRow['kind'] == 'file') {
                await _pruneFileLinks(tx, id);
                final after = {
                  for (final link in await tx.query('media_file_episodes',
                      where: 'file_id=?', whereArgs: [id]))
                    link['episode_id'] as String
                };
                classicFacts.addAll(await _classicIdentitiesAbove(
                    tx, [for (final e in linksBefore) if (!after.contains(e)) e]));
              }
              if (entityRow['kind'] == 'episode') {
                for (final link in await tx.query('media_file_episodes',
                    columns: ['file_id'],
                    where: 'episode_id=?',
                    whereArgs: [id])) {
                  await _pruneFileLinks(tx, link['file_id'] as String);
                }
              }
            }
            if (entityRow['kind'] == 'file' && explicitSelected.isNotEmpty) {
              final remaining = await tx.query('media_bindings',
                  where: 'entity_id=? AND status=?',
                  whereArgs: [id, 'accepted']);
              final links = await tx.query('media_file_episodes',
                  where: 'file_id=?', whereArgs: [id]);
              for (final link in links) {
                final identities = await tx.query('media_bindings',
                    where: 'entity_id=? AND status=?',
                    whereArgs: [link['episode_id'], 'accepted']);
                if (!remaining.any((b) => identities
                    .any((ep) => ep['object_id'] == b['object_id']))) {
                  await tx.delete('media_file_episodes',
                      where: 'file_id=? AND episode_id=?',
                      whereArgs: [id, link['episode_id']]);
                }
              }
              final attrs = entityRow['attributes'] as JsonMap;
              final revision = (attrs['bindingRevision'] as int) + 1;
              await tx.update(
                  'media_entities',
                  {
                    'attributes':
                        jsonEncode({...attrs, 'bindingRevision': revision})
                  },
                  where: 'id=?',
                  whereArgs: [id]);
              await _queueFileProjection(
                  tx, id, entityRow['revision'] as int, revision,
                  removed: explicitSelected
                      .where((b) => b['provider'] == 'dandanplay')
                      .toList());
            }
            results.add({
              'index': index,
              'entityId': id,
              // Revoking only Classic's recognition queues nothing for Classic.
              if (entityRow['kind'] == 'file')
                'classicProjectionId':
                    classicSelected.isNotEmpty && explicitSelected.isEmpty
                        ? null
                        : (await tx.query('media_projection_outbox',
                                where: 'file_id=? AND binding_revision=?',
                                whereArgs: [
                              id,
                              ((await entity(id, db: tx))['attributes']
                                  as JsonMap)['bindingRevision']
                            ]))
                            .map((p) => p['id'])
                            .firstOrNull,
              'bindingIds': [for (final b in selected) b['id']],
              if (classicFacts.isNotEmpty) 'remainingClassicBindings': classicFacts,
            });
          } on Failure catch (error) {
            throw Failure(error.code, 'Entry $index: ${error.message}',
                violations: [
                  SchemaViolation('/entries/$index', error.message)
                ]);
          }
        }
        final result = <String, Object?>{'entries': results};
        await tx.insert('media_binding_operations', {
          'id': key,
          'fingerprint': fingerprint,
          'result': jsonEncode(result)
        });
        return result;
      });

  /// The accepted classic_match bindings on [episodeIds] and on the releases
  /// and works above them: what Classic's recognition still holds up there
  /// after a file's binding was revoked. Facts only; nothing is revoked.
  Future<List<JsonMap>> _classicIdentitiesAbove(
      DatabaseExecutor tx, List<String> episodeIds) async {
    final ids = <String>{};
    for (final episode in episodeIds) {
      var current = episode;
      while (ids.add(current)) {
        final parent = (await entity(current, db: tx))['parent_id'];
        if (parent is! String) break;
        current = parent;
      }
    }
    return [
      for (final id in ids)
        for (final row in await tx.rawQuery(
            'SELECT b.id,e.kind FROM media_bindings b JOIN media_entities e ON e.id=b.entity_id '
            "WHERE b.entity_id=? AND b.status='accepted' AND b.source='classic_match' ORDER BY b.id",
            [id]))
          {'entityId': id, 'kind': row['kind'], 'bindingId': row['id']}
    ];
  }

  /// Puts back classic_match bindings `unbindBatch` revoked, by name. A
  /// file's comes back only while it is still the file's current Classic
  /// observation, and only when its episode has an accepted identity to link.
  Future<JsonMap> restoreClassicBatch(List<JsonMap> entries, String key,
          String fingerprint, Invocation invocation) =>
      _transaction((tx) async {
        final saved = await operation(key, fingerprint, db: tx);
        if (saved != null) return saved;
        final results = <JsonMap>[];
        for (var index = 0; index < entries.length; index++) {
          final entry = {
            ...entries[index],
            if (entries[index]['entityId'] is String)
              'entityId': await canonicalFileId(
                  tx, entries[index]['entityId'] as String)
          };
          try {
            final id = entry['entityId'] as String;
            final kind = (await entity(id, db: tx))['kind'];
            final requested = (entry['bindingIds'] as List?)?.cast<String>();
            if (requested != null &&
                (requested.isEmpty ||
                    requested.toSet().length != requested.length)) {
              throw const Failure(FailureCode.invalidInput,
                  'bindingIds must be nonempty and distinct.');
            }
            if (kind != 'file' && requested == null) {
              throw const Failure(FailureCode.invalidInput,
                  'bindingIds must name the revoked classic_match bindings of this entity.');
            }
            final revoked = await tx.query('media_bindings',
                where: "entity_id=? AND status='revoked' AND source='classic_match'",
                whereArgs: [id]);
            // A file's recognition is revoked and still Classic's current
            // observation of it, or it cannot come back.
            final observed = <String, JsonMap>{};
            if (kind == 'file') {
              for (final row in await tx.rawQuery(
                  'SELECT o.id,o.payload,o.binding_id FROM media_classic_observations o '
                  'JOIN media_classic_current c ON c.observation_id=o.id WHERE o.binding_id IS NOT NULL')) {
                if (decodeMediaJson(row['payload'])['provenance'] ==
                    'classic_match_revoked') {
                  observed[row['binding_id'] as String] = row;
                }
              }
            }
            final candidates = [
              for (final b in revoked)
                if (kind != 'file' || observed.containsKey(b['id'])) b
            ];
            if (requested != null &&
                requested.any(
                    (bid) => !candidates.any((c) => c['id'] == bid))) {
              throw const Failure(FailureCode.conflict,
                  "bindingIds must name revoked classic_match bindings of this entity; a file's must still be the current Classic observation.");
            }
            final selected = candidates
                .where((c) => requested == null || requested.contains(c['id']))
                .toList();
            final restored = <String>[];
            for (final binding in selected) {
              final bindingId = binding['id'] as String;
              final twin = await tx.query('media_bindings',
                  columns: ['id'],
                  where:
                      "entity_id=? AND object_id=? AND status='accepted' AND source='classic_match'",
                  whereArgs: [id, binding['object_id']]);
              if (twin.isNotEmpty) continue;
              String? episodeId;
              if (kind == 'file') {
                final owners = await tx.rawQuery(
                    'SELECT DISTINCT b.entity_id FROM media_bindings b JOIN media_entities e ON e.id=b.entity_id '
                    "WHERE b.object_id=? AND e.kind='episode' AND b.status='accepted'",
                    [binding['object_id']]);
                if (owners.length != 1) {
                  throw const Failure(FailureCode.conflict,
                      'The episode of this Classic recognition has no accepted identity; its classic_match binding is revoked.');
                }
                episodeId = owners.single['entity_id'] as String;
              }
              await tx.update('media_bindings', {'status': 'accepted'},
                  where: 'id=?', whereArgs: [bindingId]);
              await _audit(tx, bindingId, entry, invocation,
                  event: 'restore', extra: {'restored': 'classic_match'});
              restored.add(bindingId);
              if (episodeId != null) {
                await tx.insert(
                    'media_file_episodes',
                    {
                      'file_id': id,
                      'episode_id': episodeId,
                      'relation': 'exact',
                      'ordinal': 0,
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore);
                final row = observed[bindingId]!;
                await tx.update(
                    'media_classic_observations',
                    {
                      'payload': jsonEncode({
                        ...decodeMediaJson(row['payload']),
                        'provenance': 'classic_match',
                      })
                    },
                    where: 'id=?',
                    whereArgs: [row['id']]);
              }
            }
            results.add({
              'index': index,
              'entityId': id,
              'bindingIds': restored,
            });
          } on Failure catch (error) {
            throw Failure(error.code, 'Entry $index: ${error.message}',
                violations: [
                  SchemaViolation('/entries/$index', error.message)
                ]);
          }
        }
        final result = <String, Object?>{'entries': results};
        await tx.insert('media_binding_operations', {
          'id': key,
          'fingerprint': fingerprint,
          'result': jsonEncode(result)
        });
        return result;
      });

  Future<JsonMap> _bindFileReference(DatabaseExecutor tx, JsonMap entry,
      String key, Invocation invocation, int index) async {
    final fileId = entry['entityId'] as String;
    final file = await entity(fileId, db: tx);
    final attrs = file['attributes'] as JsonMap;
    final episodeId = (entry['localEpisodeIds'] as List).single as String;
    final episode = await entity(episodeId, db: tx);
    final ref = ExternalRef.fromJson(entry['ref'] as JsonMap);
    final accepted = await tx.query('media_bindings',
        where: 'entity_id=? AND object_id=? AND status=?',
        whereArgs: [
          episodeId,
          stableMediaId('object', ref.toJson()),
          'accepted'
        ]);
    if (file['kind'] != 'file' ||
        episode['kind'] != 'episode' ||
        accepted.isEmpty) {
      throw const Failure(FailureCode.invalidInput,
          'File ref requires an existing episode with the same accepted external identity.');
    }
    final links =
        await tx.rawQuery('''SELECT DISTINCT l.* FROM media_file_episodes l
      JOIN media_bindings f ON f.entity_id=l.file_id
      JOIN media_bindings e ON e.entity_id=l.episode_id AND e.object_id=f.object_id
      WHERE l.file_id=? AND f.status='accepted' AND f.source!='classic_match'
        AND e.status='accepted' ''', [fileId]);
    if (links.any((row) =>
        row['episode_id'] != episodeId ||
        row['relation'] != 'exact' ||
        row['start_ms'] != null ||
        row['end_ms'] != null)) {
      throw const Failure(FailureCode.conflict,
          'File is already linked with different episodes or intervals; unbind it explicitly.');
    }
    final probe = entry['probe'] as JsonMap;
    if (!isLocationOnlyMediaProbe(attrs['probe'] as JsonMap) &&
        ['size', 'modifiedAt', 'headMd5']
            .any((key) => probe[key] != (attrs['probe'] as JsonMap)[key])) {
      throw const Failure(
          FailureCode.conflict, 'File changed since indexing; scan again.');
    }
    final record = MetadataRecord(
        ref: ref,
        title: '',
        kind: 'episode',
        fetchedAt: DateTime.now().toUtc());
    await _checkObjects(tx, fileId, [record]);
    final previous = await tx.query('media_bindings',
        where: 'entity_id=? AND status=?', whereArgs: [fileId, 'accepted']);
    final scope = decodeMediaJson(accepted.first['scope']);
    final binding = await _bindRecord(
        tx,
        fileId,
        record,
        'exact',
        scope,
        invocation.origin == 'gui' ? 'user' : 'agent',
        'explicit_binding',
        invocation,
        key,
        attrs['bindingRevision'] as int,
        saveMetadata: false);
    await _audit(tx, binding, entry, invocation, file: {
      ...file,
      'attributes': {...attrs, 'probe': probe}
    });
    await tx.insert(
        'media_file_episodes',
        {
          'file_id': fileId,
          'episode_id': episodeId,
          'relation': 'exact',
          'ordinal': 0,
          'start_ms': null,
          'end_ms': null
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    final added = !previous.any((row) => row['id'] == binding);
    final revision = (attrs['bindingRevision'] as int) + (added ? 1 : 0);
    await tx.update(
        'media_entities',
        {
          'attributes': jsonEncode(
              {...attrs, 'probe': probe, 'bindingRevision': revision})
        },
        where: 'id=?',
        whereArgs: [fileId]);
    if (added) {
      await tx.update('media_bindings', {'revision': revision},
          where: 'id=?', whereArgs: [binding]);
      await _queueFileProjection(tx, fileId, file['revision'] as int, revision);
    }
    final projections = await tx.query('media_projection_outbox',
        where: 'file_id=? AND binding_revision=?',
        whereArgs: [fileId, revision]);
    final release = await entity(episode['parent_id'] as String, db: tx);
    return {
      'index': index,
      'workId': release['parent_id'],
      'releaseId': release['id'],
      'episodeIds': [episodeId],
      'fileId': fileId,
      'classicProjectionId': projections.map((row) => row['id']).firstOrNull,
      'bindingIds': [binding]
    };
  }

  Future<void> _queueFileProjection(
      DatabaseExecutor tx, String fileId, int fileRevision, int bindingRevision,
      {List<JsonMap> removed = const []}) async {
    final current = await tx.rawQuery(
        'SELECT b.relation,o.external_id,o.scope AS object_scope,o.id FROM media_bindings b '
        'JOIN media_external_objects o ON o.id=b.object_id WHERE b.entity_id=? AND b.status=? AND o.provider=? AND b.source!=\'classic_match\'',
        [fileId, 'accepted', 'dandanplay']);
    JsonMap? payload;
    if (current.length == 1 && current.single['relation'] == 'exact') {
      final row = current.single;
      final animeId =
          int.parse((row['object_scope'] as String).split('/').last);
      final animeObjects = await tx.query('media_external_objects',
          where: 'provider=? AND object_type=? AND external_id=? AND scope=?',
          whereArgs: ['dandanplay', 'anime', '$animeId', '']);
      if (animeObjects.isEmpty) {
        throw const Failure(FailureCode.conflict,
            'Dandanplay work metadata is missing for projection.');
      }
      final observed = await tx.rawQuery(
          'SELECT 1 FROM media_classic_current c JOIN media_locations l ON l.id=c.location_id WHERE l.file_id=? LIMIT 1', [fileId]);
      Future<String?> title(String objectId) async {
        final snapshots = await tx.query('media_snapshots',
            where: 'object_id=?',
            whereArgs: [objectId],
            orderBy: 'fetched_at DESC');
        if (snapshots.isEmpty) {
          throw const Failure(FailureCode.conflict,
              'Dandanplay metadata snapshot is missing for projection.');
        }
        for (final snapshot in snapshots) {
          final fields = decodeMediaJson(snapshot['fields']);
          if (observed.isNotEmpty &&
              {'classic_match', 'classic_cache'}.contains(fields['source'])) {
            continue;
          }
          final value = (fields['metadata'] as Map? ?? fields)['title'] as String?;
          if (value != null && value.trim().isNotEmpty) {
            return value;
          }
        }
        return null;
      }

      payload = {
        'journalVersion': 1,
        'animeId': animeId,
        'episodeId': int.parse(row['external_id'] as String),
        'animeName': await title(animeObjects.single['id'] as String),
        'episodeTitle': await title(row['id'] as String)
      };
      final previous = await tx.query('media_projection_outbox',
          where: "file_id=? AND json_extract(payload,'\$.animeId') IS NOT NULL",
          whereArgs: [fileId],
          orderBy: 'binding_revision DESC',
          limit: 1);
      if (previous.isNotEmpty) {
        final prior = decodeMediaJson(previous.single['payload']);
        if (prior['animeId'] == payload['animeId'] &&
            prior['episodeId'] == payload['episodeId']) {
          payload['previousProjectionId'] = previous.single['id'];
        }
      }
    } else if (removed.isNotEmpty) {
      final delivered = await tx.query('media_projection_outbox',
          where: "file_id=? AND json_extract(payload,'\$.animeId') IS NOT NULL",
          whereArgs: [fileId],
          orderBy: 'binding_revision DESC',
          limit: 1);
      if (delivered.isEmpty) return;
      final last = decodeMediaJson(delivered.single['payload']);
      if (!removed.any((b) =>
          b['relation'] == 'exact' &&
          last['episodeId'] == int.parse(b['external_id'] as String) &&
          last['animeId'] ==
              int.parse((b['object_scope'] as String).split('/').last))) {
        return;
      }
      payload = {
        'clear': true,
        'restoreProjectionId': delivered.single['id'],
        'journalVersion': last['journalVersion'],
        'expectedAnimeId': last['animeId'],
        'expectedEpisodeId': last['episodeId']
      };
    }
    if (payload == null) return;
    final remote = (await entity(fileId, db: tx))['attributes'] as JsonMap;
    if (remote['remoteSource'] case final Map target
        when target['type'] == 'jellyfin' || target['type'] == 'emby') {
      payload['remoteTarget'] = target;
    }
    await tx.insert('media_projection_outbox', {
      'id': stableMediaId('projection', [fileId, bindingRevision]),
      'file_id': fileId,
      'file_revision': fileRevision,
      'binding_revision': bindingRevision,
      'state': 'pending',
      'payload': jsonEncode(payload)
    });
  }
}
