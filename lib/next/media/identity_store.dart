import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'metadata_provider.dart';

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
  const IdentityStore(this.database, this.ownerDeviceId);
  final Database database;
  final String ownerDeviceId;

  /// Location-only registration never changes content revisions or infers identity.
  Future<String> ensureFile(String locator) => database.transaction((tx) async {
        if (locator.trim().isEmpty) {
          throw const Failure(FailureCode.invalidInput, 'File path is empty.');
        }
        final rows = await tx.query('media_locations',
            where: 'owner_device_id = ? AND locator = ?',
            whereArgs: [ownerDeviceId, locator]);
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
          'source': locator.contains('://') ? 'remote' : 'local',
          'owner_device_id': ownerDeviceId,
          'locator': locator,
          'available': 1
        });
        return id;
      });

  Future<JsonMap> entity(String id, {DatabaseExecutor? db}) async {
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
      database.transaction((tx) async {
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
          } else if (jsonEncode(attrs['probe']) != jsonEncode(probe)) {
            final dandanplay = await tx.rawQuery(
                'SELECT o.external_id,o.scope FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.entity_id = ? AND b.status = ? AND o.provider = ?',
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
            await tx.delete('media_file_episodes',
                where: 'file_id = ?', whereArgs: [fileId]);
            await tx.update('media_bindings', {'status': 'revoked'},
                where: 'entity_id = ? AND status = ?',
                whereArgs: [fileId, 'accepted']);
            if (dandanplay.length == 1) {
              await tx.insert('media_projection_outbox', {
                'id': stableMediaId('projection', [fileId, bindingRevision]),
                'file_id': fileId,
                'file_revision': (file['revision'] as int) + 1,
                'binding_revision': bindingRevision,
                'payload': jsonEncode({
                  'clear': true,
                  'expectedAnimeId': int.parse(
                      (dandanplay.single['scope'] as String).split('/').last),
                  'expectedEpisodeId':
                      int.parse(dandanplay.single['external_id'] as String)
                }),
                'state': 'pending'
              });
            }
          }
          await tx.update('media_locations', {'available': 1},
              where: 'id = ?', whereArgs: [locations.single['id']]);
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
        return id;
      });

  Future<List<JsonMap>> locations(String fileId) => database
      .query('media_locations', where: 'file_id = ?', whereArgs: [fileId]);

  /// Historical IDs stay as evidence; neither confirmation nor a binding actor is inferred.
  Future<int> importLegacy(List<JsonMap> history) async {
    for (final row in history) {
      final locator = row['filePath'] as String;
      final existing = await database.query('media_locations',
          where: 'owner_device_id = ? AND locator = ?',
          whereArgs: [ownerDeviceId, locator]);
      final source = locator.startsWith('smb://')
          ? 'smb'
          : locator.startsWith('webdav://')
              ? 'webdav'
              : locator.contains('://')
                  ? 'remote'
                  : 'local';
      final fileId = existing.isEmpty
          ? await registerFile(locator, {'legacy': true}, source: source)
          : existing.single['file_id'] as String;
      final location = (await locations(fileId))
          .firstWhere((item) => item['locator'] == locator);
      // Progress is intentionally absent from the side index.
      final evidence = {
        'animeId': row['animeId'],
        'episodeId': row['episodeId'],
        'animeName': row['animeName'],
        'episodeTitle': row['episodeTitle'],
        'videoHash': row['videoHash'],
        'provenance': 'legacy_unknown'
      };
      final fingerprint = stableMediaId('legacy', evidence);
      await database.insert(
          'media_legacy_history',
          {
            'location_id': location['id'],
            'fingerprint': fingerprint,
            'payload': jsonEncode(evidence)
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return history.length;
  }

  Future<void> beginIdentification(
      String jobId, String fileId, JsonMap context) async {
    final file = await entity(fileId);
    await database.insert(
        'media_identifications',
        {
          'job_id': jobId,
          'file_id': fileId,
          'file_revision': file['revision'],
          'binding_revision':
              (file['attributes'] as JsonMap)['bindingRevision'],
          'state': 'pending',
          'context': jsonEncode(context)
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<JsonMap> identification(String jobId, {DatabaseExecutor? db}) async {
    final rows = await (db ?? database).query('media_identifications',
        where: 'job_id = ?', whereArgs: [jobId]);
    if (rows.isEmpty) {
      throw const Failure(FailureCode.notFound, 'Identification not found.');
    }
    return {...rows.single, 'context': decodeMediaJson(rows.single['context'])};
  }

  Future<void> setIdentificationState(String jobId, String state) =>
      database.update('media_identifications', {'state': state},
          where: 'job_id = ?', whereArgs: [jobId]);

  Future<void> checkContext(String jobId, {DatabaseExecutor? db}) async {
    final identification = await this.identification(jobId, db: db);
    final file = await entity(identification['file_id'] as String, db: db);
    if (file['revision'] != identification['file_revision'] ||
        (file['attributes'] as JsonMap)['bindingRevision'] !=
            identification['binding_revision']) {
      throw const Failure(FailureCode.conflict,
          'File or binding changed. Start identification for the current revision.');
    }
  }

  Future<String> addCandidate(
      String jobId, JsonMap payload, String source) async {
    final work = Map<String, Object?>.from(payload['work'] as Map);
    final release = Map<String, Object?>.from(payload['release'] as Map);
    final id = stableMediaId('candidate', [
      jobId,
      work['ref'],
      release['ref'],
      [for (final ep in payload['episodes'] as List) (ep as Map)['ref']],
      payload['workId'],
      payload['scope'],
      payload['evidence']
    ]);
    await database.transaction((tx) async {
      await checkContext(jobId, db: tx);
      final identification = await this.identification(jobId, db: tx);
      final evidence = {
        ...Map<String, Object?>.from(payload['evidence'] as Map),
        'fileRevision': identification['file_revision'],
        'probe': (identification['context'] as JsonMap)['probe']
      };
      final persisted = {...payload, 'evidence': evidence};
      await tx.insert(
          'media_candidates',
          {
            'id': id,
            'job_id': jobId,
            'file_id': identification['file_id'],
            'file_revision': identification['file_revision'],
            'binding_revision': identification['binding_revision'],
            'payload': jsonEncode(persisted),
            'source': source,
            'state': 'proposed'
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await tx.insert(
          'media_evidence',
          {
            'id': stableMediaId('evidence', id),
            'job_id': jobId,
            'source': source,
            'payload': jsonEncode(evidence),
            'created_at': _now
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return id;
  }

  Future<List<JsonMap>> candidates(String jobId) async => [
        for (final row in await database.query('media_candidates',
            where: 'job_id = ?', whereArgs: [jobId], orderBy: 'id'))
          {...row, 'payload': decodeMediaJson(row['payload'])}
      ];

  Future<void> updateIdentificationContext(
      String jobId, JsonMap context) async {
    await database.update(
        'media_identifications', {'context': jsonEncode(context)},
        where: 'job_id = ?', whereArgs: [jobId]);
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
      String jobId,
      int revision) async {
    final objectId = await _object(tx, record.ref);
    final id = stableMediaId('binding', [jobId, entityId, objectId]);
    final previous = await tx.query('media_bindings',
        columns: ['id'],
        where: 'entity_id = ? AND id != ?',
        whereArgs: [entityId, id],
        orderBy: 'created_at DESC, id DESC',
        limit: 1);
    await tx.insert(
        'media_bindings',
        {
          'id': id,
          'entity_id': entityId,
          'object_id': objectId,
          'relation': relation,
          'scope': jsonEncode(scope),
          'status': 'accepted',
          'source': source,
          'bound_by': actor,
          'revision': revision,
          'supersedes': previous.isEmpty ? null : previous.single['id'],
          'invocation_id': invocation.id,
          'job_id': jobId,
          'created_at': _now
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await _snapshot(tx, objectId, record);
    return id;
  }

  Future<String> _snapshot(
      DatabaseExecutor tx, String objectId, MetadataRecord record) async {
    final id = stableMediaId('snapshot',
        [objectId, record.language, record.fetchedAt.toIso8601String()]);
    await tx.insert(
        'media_snapshots',
        {
          'id': id,
          'object_id': objectId,
          'language': record.language,
          'fetched_at': record.fetchedAt.toUtc().toIso8601String(),
          'fields': jsonEncode(record.toJson())
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return id;
  }

  Future<String> saveSnapshot(MetadataRecord record) => database.transaction(
      (tx) async => _snapshot(tx, await _object(tx, record.ref), record));

  /// The checkpoint choice is durable before this transaction; recovery can safely repeat it.
  Future<JsonMap> acceptCandidate(String jobId, String candidateId,
          String actor, Invocation invocation) =>
      database.transaction((tx) async {
        final identification = await this.identification(jobId, db: tx);
        if (identification['state'] == 'accepted') {
          final accepted = await tx.query('media_candidates',
              where: 'job_id = ? AND state = ?',
              whereArgs: [jobId, 'accepted']);
          if (accepted.single['id'] != candidateId) {
            throw const Failure(
                FailureCode.conflict, 'A different candidate was accepted.');
          }
          return {'fileId': identification['file_id'], 'accepted': true};
        }
        await checkContext(jobId, db: tx);
        final rows = await tx.query('media_candidates',
            where: 'id = ? AND job_id = ? AND state = ?',
            whereArgs: [candidateId, jobId, 'proposed']);
        if (rows.isEmpty) {
          throw const Failure(FailureCode.conflict,
              'Candidate does not belong to this pending identification.');
        }
        final candidate = rows.single;
        final payload = decodeMediaJson(candidate['payload']);
        final work = MetadataRecord.fromJson(
            Map<String, Object?>.from(payload['work'] as Map));
        final release = MetadataRecord.fromJson(
            Map<String, Object?>.from(payload['release'] as Map));
        final selected = [
          for (final ep in payload['episodes'] as List)
            MetadataRecord.fromJson(Map<String, Object?>.from(ep as Map))
        ];
        final workId = payload['workId'] as String? ??
            await _materialize(tx, 'work', work, null);
        if ((await entity(workId, db: tx))['kind'] != 'work') {
          throw const Failure(
              FailureCode.invalidInput, 'workId must reference a work.');
        }
        final releaseId = await _materialize(tx, 'release', release, workId);
        final fileId = identification['file_id'] as String;
        final file = await entity(fileId, db: tx);
        final attrs = file['attributes'] as JsonMap;
        final revision = (attrs['bindingRevision'] as int) + 1;
        final scope = Map<String, Object?>.from(payload['scope'] as Map);
        final source = candidate['source'] as String;
        await _bindRecord(tx, workId, work, 'contains', scope, actor, source,
            invocation, jobId, revision);
        await _bindRecord(tx, releaseId, release, payload['relation'] as String,
            scope, actor, source, invocation, jobId, revision);
        await tx.update('media_bindings', {'status': 'revoked'},
            where: 'entity_id = ? AND status = ?',
            whereArgs: [fileId, 'accepted']);
        await tx.delete('media_file_episodes',
            where: 'file_id = ?', whereArgs: [fileId]);
        var ordinal = 0;
        for (final episode in selected) {
          final epId = await _materialize(tx, 'episode', episode, releaseId);
          await _bindRecord(tx, epId, episode, 'exact', scope, actor, source,
              invocation, jobId, revision);
          final bindingId = await _bindRecord(
              tx,
              fileId,
              episode,
              payload['relation'] as String,
              scope,
              actor,
              source,
              invocation,
              jobId,
              revision);
          await tx.insert(
              'media_evidence',
              {
                'id': stableMediaId('evidence', bindingId),
                'binding_id': bindingId,
                'job_id': jobId,
                'source': source,
                'payload': jsonEncode(payload['evidence']),
                'created_at': _now
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
          await tx.insert('media_file_episodes', {
            'file_id': fileId,
            'episode_id': epId,
            'relation': payload['relation'],
            'ordinal': ordinal++,
            'start_ms': null,
            'end_ms': null
          });
        }
        // Persist the complete selected release catalogue, independently of file coverage.
        for (final episode in release.episodes) {
          final epId = await _materialize(tx, 'episode', episode, releaseId);
          await _bindRecord(tx, epId, episode, 'exact', scope, actor, source,
              invocation, jobId, revision);
        }
        for (final binding in await tx
            .query('media_bindings', where: 'job_id = ?', whereArgs: [jobId])) {
          await tx.insert(
              'media_evidence',
              {
                'id': stableMediaId('evidence', binding['id'] as String),
                'binding_id': binding['id'],
                'job_id': jobId,
                'source': source,
                'payload': jsonEncode(payload['evidence']),
                'created_at': _now
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await tx.update(
            'media_entities',
            {
              'attributes': jsonEncode({...attrs, 'bindingRevision': revision})
            },
            where: 'id = ?',
            whereArgs: [fileId]);
        await tx.update('media_candidates', {'state': 'rejected'},
            where: 'job_id = ?', whereArgs: [jobId]);
        await tx.update('media_candidates', {'state': 'accepted'},
            where: 'id = ?', whereArgs: [candidateId]);
        await tx.update('media_identifications', {'state': 'accepted'},
            where: 'job_id = ?', whereArgs: [jobId]);
        if (work.ref.provider == 'dandanplay' && selected.length == 1) {
          await tx.insert('media_projection_outbox', {
            'id': stableMediaId('projection', [fileId, revision]),
            'file_id': fileId,
            'file_revision': file['revision'],
            'binding_revision': revision,
            'state': 'pending',
            'payload': jsonEncode({
              'animeId': int.parse(work.ref.externalId),
              'episodeId': int.parse(selected.single.ref.externalId),
              'animeName': work.title,
              'episodeTitle': selected.single.title
            })
          });
        }
        return {
          'fileId': fileId,
          'workId': workId,
          'releaseId': releaseId,
          'bindingRevision': revision,
          'accepted': true
        };
      });

  Future<List<JsonMap>> pendingProjections({String? fileId}) =>
      database.query('media_projection_outbox',
          where: fileId == null ? 'state = ?' : 'state = ? AND file_id = ?',
          whereArgs: ['pending', if (fileId != null) fileId],
          orderBy: 'binding_revision');
  Future<void> finishProjection(String id, String state) =>
      database.update('media_projection_outbox', {'state': state},
          where: 'id = ?', whereArgs: [id]);

  Future<JsonMap> identity(String id) async {
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

  Future<JsonMap> mergedMetadata(String entityId) async {
    final rows = await database.rawQuery(
        'SELECT s.*,o.provider FROM media_snapshots s JOIN media_external_objects o ON o.id=s.object_id JOIN media_bindings b ON b.object_id=o.id WHERE b.entity_id = ? AND b.status = ? ORDER BY s.fetched_at DESC, s.id',
        [entityId, 'accepted']);
    final fields = <String, Object?>{}, provenance = <String, Object?>{};
    for (final row in rows) {
      final values = decodeMediaJson(row['fields']);
      for (final field in [
        'title',
        'originalTitle',
        'overview',
        'imageUrl',
        'year'
      ]) {
        if (values[field] != null &&
            values[field] != '' &&
            !fields.containsKey(field)) {
          fields[field] = values[field];
          provenance[field] = {
            'provider': row['provider'],
            'language': row['language'],
            'fetchedAt': row['fetched_at']
          };
        }
      }
    }
    for (final row in await database.query('media_overrides',
        where: 'entity_id = ?', whereArgs: [entityId])) {
      fields[row['field'] as String] = jsonDecode(row['value'] as String);
      provenance[row['field'] as String] = {
        'provider': 'user',
        'invocationId': row['invocation_id']
      };
    }
    return {'fields': fields, 'provenance': provenance};
  }

  Future<void> overrideField(
      String id, String field, Object? value, Invocation invocation) async {
    await entity(id);
    await database.insert(
        'media_overrides',
        {
          'entity_id': id,
          'field': field,
          'value': jsonEncode(value),
          'invocation_id': invocation.id
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<JsonMap>> library({String? query}) async {
    final works = await database.query('media_entities',
        where: 'kind = ?', whereArgs: ['work'], orderBy: 'id');
    final results = <JsonMap>[];
    for (final work in works) {
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
        'releases': await _releases(id)
      });
    }
    return results;
  }

  Future<List<JsonMap>> _releases(String workId) async {
    final releases = await database.query('media_entities',
        where: 'parent_id = ? AND kind = ?', whereArgs: [workId, 'release']);
    return [
      for (final release in releases)
        {
          ...release,
          'attributes': decodeMediaJson(release['attributes']),
          'metadata': await mergedMetadata(release['id'] as String),
          'episodes': await _episodes(release['id'] as String)
        }
    ];
  }

  Future<List<JsonMap>> _episodes(String releaseId) async {
    final episodes = await database.query('media_entities',
        where: 'parent_id = ? AND kind = ?', whereArgs: [releaseId, 'episode']);
    final ordered = List<JsonMap>.of(episodes)
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

  Future<void> unbindFile(String fileId, int revision, Invocation invocation) =>
      database.transaction((tx) async {
        final file = await entity(fileId, db: tx);
        if (file['kind'] != 'file') {
          throw const Failure(FailureCode.invalidInput,
              'Only file identity can be unbound here.');
        }
        final attrs = file['attributes'] as JsonMap;
        if (attrs['bindingRevision'] != revision) {
          throw const Failure(FailureCode.conflict, 'Stale binding revision.');
        }
        final dandanplay = await tx.rawQuery(
            'SELECT o.external_id,o.scope FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.entity_id = ? AND b.status = ? AND o.provider = ?',
            [fileId, 'accepted', 'dandanplay']);
        await tx.update('media_bindings',
            {'status': 'revoked', 'invocation_id': invocation.id},
            where: 'entity_id = ? AND status = ?',
            whereArgs: [fileId, 'accepted']);
        await tx.delete('media_file_episodes',
            where: 'file_id = ?', whereArgs: [fileId]);
        await tx.update(
            'media_entities',
            {
              'attributes':
                  jsonEncode({...attrs, 'bindingRevision': revision + 1})
            },
            where: 'id = ?',
            whereArgs: [fileId]);
        if (dandanplay.length == 1) {
          await tx.insert('media_projection_outbox', {
            'id': stableMediaId('projection', [fileId, revision + 1]),
            'file_id': fileId,
            'file_revision': file['revision'],
            'binding_revision': revision + 1,
            'payload': jsonEncode({
              'clear': true,
              'expectedAnimeId': int.parse(
                  (dandanplay.single['scope'] as String).split('/').last),
              'expectedEpisodeId':
                  int.parse(dandanplay.single['external_id'] as String)
            }),
            'state': 'pending'
          });
        }
      });
}
