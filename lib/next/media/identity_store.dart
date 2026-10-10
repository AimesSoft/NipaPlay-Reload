import 'dart:async';
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
  IdentityStore(this.database, this.ownerDeviceId);
  final Database database;
  final String ownerDeviceId;
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
              database.transaction((tx) => _ensureFile(tx, locator, added)))
          : _ensureFile(db, locator);

  Future<String> _ensureFile(DatabaseExecutor tx, String locator,
      [List<JsonMap>? added]) async {
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
    added?.add({'fileId': id, 'path': locator});
    return id;
  }

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
      _filesChanged((added) => database.transaction((tx) async {
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
                    'id':
                        stableMediaId('projection', [fileId, bindingRevision]),
                    'file_id': fileId,
                    'file_revision': (file['revision'] as int) + 1,
                    'binding_revision': bindingRevision,
                    'payload': jsonEncode({
                      'clear': true,
                      'expectedAnimeId': int.parse(
                          (dandanplay.single['scope'] as String)
                              .split('/')
                              .last),
                      'expectedEpisodeId':
                          int.parse(dandanplay.single['external_id'] as String)
                    }),
                    'state': 'pending'
                  });
                }
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
      int revision) async {
    final objectId = await _object(tx, record.ref);
    final accepted = await tx.query('media_bindings',
        where: 'entity_id = ? AND object_id = ? AND status = ?',
        whereArgs: [entityId, objectId, 'accepted']);
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
      if (row['mode'] == 'correction' &&
          rows.any((snapshot) =>
              (snapshot['fetched_at'] as String)
                  .compareTo(row['changed_at'] as String) >
              0)) {
        continue;
      }
      fields[row['field'] as String] = jsonDecode(row['value'] as String);
      provenance[row['field'] as String] = {
        'provider': row['actor'],
        'invocationId': row['invocation_id'],
        'origin': row['origin'],
        'mode': row['mode']
      };
    }
    return {'fields': fields, 'provenance': provenance};
  }

  Future<void> overrideField(
      String id, String field, Object? value, Invocation invocation,
      {String mode = 'persistent'}) async {
    await entity(id);
    final edit = {
      'entity_id': id,
      'field': field,
      'value': jsonEncode(value),
      'mode': mode,
      'actor': invocation.origin == 'gui' ? 'user' : 'agent',
      'origin': invocation.origin,
      'invocation_id': invocation.id,
      'changed_at': _now
    };
    await database.transaction((tx) async {
      await tx.insert('media_metadata_edits', edit);
      if (mode == 'clear') {
        await tx.delete('media_overrides',
            where: 'entity_id=? AND field=?', whereArgs: [id, field]);
      } else {
        await tx.insert('media_overrides', edit,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
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
      {String event = 'bind', JsonMap? file}) async {
    await tx.insert('media_evidence', {
      'id': newMediaId('evidence'),
      'binding_id': bindingId,
      'source': 'explicit_binding',
      'created_at': _now,
      'payload': jsonEncode({
        'event': event,
        'reason': input['reason'],
        'evidence': input['evidence'] ?? [],
        'boundBy': invocation.origin == 'gui' ? 'user' : 'agent',
        'invocationId': invocation.id,
        'origin': invocation.origin,
        if (file != null) ...{
          'fileRevision': file['revision'],
          'probe': (file['attributes'] as JsonMap)['probe']
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
        'WHERE b.entity_id=? AND b.status=? AND o.provider=?',
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
          '$id is not a $kind under the selected parent.');
    }
    return id;
  }

  Future<JsonMap> bindBatch(List<JsonMap> entries, String key,
          String fingerprint, Invocation invocation) =>
      _filesChanged((newFiles) => database.transaction((tx) async {
            final saved = await operation(key, fingerprint, db: tx);
            if (saved != null) return saved;
            final results = <JsonMap>[];
            for (var index = 0; index < entries.length; index++) {
              final entry = entries[index];
              try {
                final kind = entry['kind'] as String;
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
                  if (links.isNotEmpty &&
                      stableMediaId('links',
                              links.map((row) => row['episode_id']).toList()) !=
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
                    final same = links
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
      database.transaction((tx) async {
        final saved = await operation(key, fingerprint, db: tx);
        if (saved != null) return saved;
        final results = <JsonMap>[];
        for (var index = 0; index < entries.length; index++) {
          final entry = entries[index];
          try {
            final id = entry['entityId'] as String;
            final entityRow = await entity(id, db: tx);
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
                .where((b) => requested == null || requested.contains(b['id']))
                .toList();
            for (final binding in selected) {
              await tx.update('media_bindings', {'status': 'revoked'},
                  where: 'id=?', whereArgs: [binding['id']]);
              await _audit(tx, binding['id'] as String, entry, invocation,
                  event: 'unbind');
            }
            if (entityRow['kind'] == 'file' && selected.isNotEmpty) {
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
                  removed: selected
                      .where((b) => b['provider'] == 'dandanplay')
                      .toList());
            }
            results.add({
              'index': index,
              'entityId': id,
              'bindingIds': [for (final b in selected) b['id']]
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

  Future<void> _queueFileProjection(
      DatabaseExecutor tx, String fileId, int fileRevision, int bindingRevision,
      {List<JsonMap> removed = const []}) async {
    final current = await tx.rawQuery(
        'SELECT b.relation,o.external_id,o.scope AS object_scope,o.id FROM media_bindings b '
        'JOIN media_external_objects o ON o.id=b.object_id WHERE b.entity_id=? AND b.status=? AND o.provider=?',
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
      Future<String> title(String objectId) async {
        final snapshots = await tx.query('media_snapshots',
            where: 'object_id=?',
            whereArgs: [objectId],
            orderBy: 'fetched_at DESC',
            limit: 1);
        if (snapshots.isEmpty) {
          throw const Failure(FailureCode.conflict,
              'Dandanplay metadata snapshot is missing for projection.');
        }
        return decodeMediaJson(snapshots.single['fields'])['title'] as String;
      }

      payload = {
        'animeId': animeId,
        'episodeId': int.parse(row['external_id'] as String),
        'animeName': await title(animeObjects.single['id'] as String),
        'episodeTitle': await title(row['id'] as String)
      };
    } else if (removed.length == 1 && removed.single['relation'] == 'exact') {
      payload = {
        'clear': true,
        'expectedAnimeId': int.parse(
            (removed.single['object_scope'] as String).split('/').last),
        'expectedEpisodeId': int.parse(removed.single['external_id'] as String)
      };
    }
    if (payload == null) return;
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
