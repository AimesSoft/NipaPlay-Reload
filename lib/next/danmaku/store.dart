import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../media/identity_store.dart';
import '../media/metadata_provider.dart';
import 'source.dart';
import 'sidecar.dart';
import 'files.dart';
import '../events/signals.dart';

final class DanmakuStore {
  const DanmakuStore(this.identities);
  final IdentityStore identities;
  Database get db => identities.database;
  DanmakuFiles get files => DanmakuFiles(db);
  String get now => DateTime.now().toUtc().toIso8601String();
  Future<T> _transaction<T>(Future<T> Function(Transaction) action) => BodySignals.transaction(db, action);
  JsonMap decodeBinding(JsonMap b) => {
        ...b,
        'local_file':
            b['local_file'] == null ? null : decodeMediaJson(b['local_file']),
        'video': decodeMediaJson(b['video']),
        'evidence': decodeMediaJson(b['evidence']),
        'alignment': decodeMediaJson(b['alignment']),
        'provenance':
            b['provenance'] == null ? null : decodeMediaJson(b['provenance'])
      };

  Future<void> recordSidecar(String entityId, JsonMap facts) =>
      _transaction((tx) async {
        final entity = await identities.entity(entityId, db: tx);
        final imported = await tx.query('danmaku_bindings', columns: ['id'],
            where: "entity_id=? AND entity_revision=? AND status='accepted' AND local_file IS NULL AND json_extract(provenance, '\$.filePath')=?",
            whereArgs: [entity['id'], entity['revision'], facts['path']]);
        if (imported.isNotEmpty) return;
        final id = stableMediaId('danmaku-sidecar', entity['id'] as String);
        final previous =
            await tx.query('danmaku_bindings', where: 'id=?', whereArgs: [id]);
        final b = previous.firstOrNull;
        final video = DanmakuVideo(
            sourceId: 'local',
            videoId: facts['path'] as String,
            title: (facts['path'] as String).split('/').last,
            durationMs: 0,
            objectType: 'file');
        final objectId = stableMediaId('object', ExternalRef('local', 'file', facts['path'] as String).toJson());
        await tx.insert(
            'media_external_objects',
            {
              'id': objectId,
              'provider': 'local',
              'object_type': 'file',
              'external_id': facts['path'],
              'scope': ''
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        final revision = (b?['revision'] as int? ?? -1) + 1;
        final values = <String, Object?>{
          'entity_id': entity['id'],
          'entity_revision': entity['revision'],
          'object_id': objectId,
          'video': jsonEncode(video.toJson()),
          'revision': revision,
          'cache_key': facts['available'] == true ? 'sidecar:$id' : null,
          'cache_revision': (b?['cache_revision'] as int? ?? 0) + 1,
          'local_file': jsonEncode(facts),
        };
        if (b == null) {
          await tx.insert('danmaku_bindings', {
            ...values,
            'id': id,
            'status': 'accepted',
            'enabled': 1,
            'deduplicate': 1,
            'offset_ms': 0,
            'alignment': jsonEncode({'method': 'identity', 'confirmed': false}),
            'evidence':
                jsonEncode({'reason': 'Video sidecar file', 'url': null}),
            'bound_by': 'automatic',
            'invocation_id': 'application:sidecar',
            'created_at': now
          });
        } else {
          await tx.update('danmaku_bindings', values,
              where: 'id=?', whereArgs: [id]);
        }
        await _event(tx, id, revision, 'application:sidecar', {
          'operation': 'sidecar_observed',
          'actor': 'automatic',
          'origin': 'application',
          for (final entry in facts.entries)
            if (entry.key != 'timeCounts') entry.key: entry.value
        });
      });

  Future<JsonMap> importEntries(
          String entityId,
          DanmakuVideo video,
          List<DanmakuEntry> entries,
          String filePath,
          String? note,
          Invocation invocation) =>
      _transaction((tx) async {
        final entity = await identities.entity(entityId, db: tx);
        entityId = entity['id'] as String;
        if (!['file', 'episode'].contains(entity['kind'])) {
          throw const Failure(
              FailureCode.invalidInput, 'Danmaku binds to a file or episode.');
        }
        final previous = await tx.query('danmaku_bindings',
            where: 'entity_id = ? AND entity_revision = ? AND status = ? '
                "AND json_extract(video, '\$.sourceId') = ? "
                "AND json_extract(video, '\$.videoId') = ?",
            whereArgs: [
              entityId,
              entity['revision'],
              'accepted',
              video.sourceId,
              video.videoId
            ],
            orderBy: 'created_at,id');
        final b = previous.isEmpty ? null : previous.first;
        final id = b?['id'] as String? ?? newMediaId('danmaku');
        final revision = b == null ? 0 : (b['revision'] as int) + 1;
        final storedVideo = b == null
            ? video
            : DanmakuVideo.fromJson(decodeMediaJson(b['video']));
        final ref = ExternalRef(
            storedVideo.sourceId, storedVideo.objectType, storedVideo.videoId);
        final objectId = stableMediaId('object', ref.toJson());
        await tx.insert(
            'media_external_objects',
            {
              'id': objectId,
              'provider': ref.provider,
              'object_type': ref.objectType,
              'external_id': ref.externalId,
              'scope': ref.scope
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        final timestamp = now;
        final provenance = {
          'platform': video.sourceId,
          'platformVideoId': video.videoId,
          'actor': invocation.origin == 'application:playback'
              ? 'automatic'
              : invocation.origin == 'gui'
                  ? 'user'
                  : 'agent',
          'origin': invocation.origin,
          'importedAt': timestamp,
          'filePath': filePath,
          'note': note,
        };
        final key = newMediaId('danmaku-import');
        final reference = await files.write(
            [for (final e in entries) e.toJson()],
            invocation.origin == 'application:playback' ? 'cache' : 'imported');
        await tx.insert('danmaku_cache_chunks', {
          'cache_key': key,
          'chunk_index': 0,
          'start_ms': 0,
          'end_ms': entries.fold<int>(
              0, (end, e) => e.sourceTimeMs >= end ? e.sourceTimeMs + 1 : end),
          ...reference,
          'coverage': 'importedPool',
          'fetched_at': timestamp,
        });
        final values = {
          'entity_id': entityId,
          'entity_revision': entity['revision'],
          'object_id': objectId,
          'video': jsonEncode(storedVideo.toJson()),
          'status': 'accepted',
          'evidence':
              jsonEncode({'reason': note ?? 'Imported danmaku', 'url': null}),
          'bound_by': provenance['actor'],
          'invocation_id': invocation.id,
          'revision': revision,
          'cache_key': key,
          'cache_revision': (b?['cache_revision'] as int? ?? 0) + 1,
          'cache_job_id': null,
          'provenance': jsonEncode(provenance),
          'local_file': null,
        };
        if (b == null) {
          await tx.insert('danmaku_bindings', {
            ...values,
            'id': id,
            'enabled': 1,
            'deduplicate': 1,
            'offset_ms': 0,
            'alignment': jsonEncode({'method': 'identity', 'confirmed': false}),
            'created_at': timestamp,
          });
        } else {
          await tx.update('danmaku_bindings', values,
              where: 'id = ?', whereArgs: [id]);
        }
        final pointers = await tx.query('danmaku_bindings',
            where: "entity_id=? AND status='accepted' AND local_file IS NOT NULL AND json_extract(local_file, '\$.path')=? AND id!=?",
            whereArgs: [entityId, filePath, id]);
        for (final duplicate in [...previous.skip(1), ...pointers]) {
          final rev = (duplicate['revision'] as int) + 1;
          await tx.update(
              'danmaku_bindings', {'status': 'revoked', 'revision': rev},
              where: 'id = ?', whereArgs: [duplicate['id']]);
          await _event(tx, duplicate['id'] as String, rev, invocation.id,
              {'operation': 'replaced', 'replacementId': id, ...provenance});
        }
        await _event(tx, id, revision, invocation.id, {
          'operation': 'import',
          'entryCount': entries.length,
          'cacheKey': key,
          'video': video.toJson(),
          ...provenance
        });
        await files.release(tx, [
          for (final old in [...previous, ...pointers])
            if (old['cache_key'] != null) old['cache_key'] as String
        ]);
        return binding(id, tx: tx);
      }).then((b) async {
        await files.collect();
        return b;
      });
  Future<JsonMap> binding(String id,
      {DatabaseExecutor? tx, bool active = true}) async {
    final rows = await (tx ?? db)
        .query('danmaku_bindings', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw const Failure(FailureCode.notFound, 'Danmaku binding not found.');
    }
    final b = decodeBinding(rows.single);
    final entity = await identities.entity(b['entity_id'] as String, db: tx);
    if (active &&
        (b['status'] != 'accepted' ||
            entity['revision'] != b['entity_revision'])) {
      throw const Failure(FailureCode.conflict,
          'Danmaku binding is revoked or media content changed.');
    }
    return b;
  }

  Future<String> attach(String entityId, DanmakuVideo video, String reason,
          String? url, Invocation invocation) =>
      _transaction((tx) async {
        final entity = await identities.entity(entityId, db: tx);
        entityId = entity['id'] as String;
        if (!['file', 'episode'].contains(entity['kind'])) {
          throw const Failure(
              FailureCode.invalidInput, 'Danmaku binds to a file or episode.');
        }
        final ref =
            ExternalRef(video.sourceId, video.objectType, video.videoId);
        final objectId = stableMediaId('object', ref.toJson());
        await tx.insert(
            'media_external_objects',
            {
              'id': objectId,
              'provider': ref.provider,
              'object_type': ref.objectType,
              'external_id': ref.externalId,
              'scope': ref.scope
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        final previous = await tx.query('danmaku_bindings',
            where:
                'entity_id = ? AND object_id = ? AND status = ? AND entity_revision = ?',
            whereArgs: [entityId, objectId, 'accepted', entity['revision']]);
        if (previous.isNotEmpty) {
          if (jsonEncode(decodeMediaJson(previous.single['video'])) !=
              jsonEncode(video.toJson())) {
            throw const Failure(FailureCode.conflict,
                'Existing binding has different video metadata. Detach before replacing it.');
          }
          return previous.single['id'] as String;
        }
        final id = newMediaId('danmaku');
        await tx.insert('danmaku_bindings', {
          'id': id,
          'entity_id': entityId,
          'entity_revision': entity['revision'],
          'object_id': objectId,
          'video': jsonEncode(video.toJson()),
          'status': 'accepted',
          'enabled': 1,
          'offset_ms': 0,
          'alignment': jsonEncode({'method': 'identity', 'confirmed': false}),
          'evidence': jsonEncode({'reason': reason, 'url': url}),
          'bound_by': invocation.origin == 'gui' ? 'user' : 'agent',
          'invocation_id': invocation.id,
          'revision': 0,
          'created_at': now
        });
        await _event(tx, id, 0, invocation.id, {
          'operation': 'attach',
          'origin': invocation.origin,
          'actor': invocation.origin == 'gui' ? 'user' : 'agent',
          'video': video.toJson(),
          'reason': reason,
          'url': url
        });
        return id;
      });
  Future<List<JsonMap>> bindings(String entityId) async {
    entityId = (await identities.entity(entityId))['id'] as String;
    return [
      for (final b in await db.query('danmaku_bindings',
          where: 'entity_id = ?',
          whereArgs: [entityId],
          orderBy: 'created_at,id'))
        decodeBinding(b)
    ];
  }

  Future<void> _event(DatabaseExecutor tx, String id, int rev,
      String invocation, JsonMap payload) async {
    await tx.insert('danmaku_binding_events', {
      'id': stableMediaId('danmaku-event', [id, rev]),
      'binding_id': id,
      'revision': rev,
      'invocation_id': invocation,
      'payload': jsonEncode(payload),
      'created_at': now
    });
    BodySignals.changed('media.assets.changed', id,
        {'kind': 'danmaku', 'bindingId': id, 'revision': rev,
          'changedFields': payload.keys.toList(), 'facts': payload});
  }

  Future<JsonMap> change(
          String id, int revision, JsonMap values, Invocation invocation,
          {JsonMap? alignment, String? reason}) =>
      _transaction((tx) async {
        final b = await binding(id, tx: tx);
        if (b['revision'] != revision) {
          throw const Failure(
              FailureCode.conflict, 'Stale danmaku binding revision.');
        }
        await tx.update(
            'danmaku_bindings',
            {
              ...values,
              'revision': revision + 1,
              'invocation_id': invocation.id,
              if (alignment != null) 'alignment': jsonEncode(alignment)
            },
            where: 'id = ?',
            whereArgs: [id]);
        await _event(tx, id, revision + 1, invocation.id, {
          ...values,
          if (alignment != null) 'alignment': alignment,
          if (reason != null) 'reason': reason,
          'origin': invocation.origin,
          'actor': invocation.origin == 'gui' ? 'user' : 'agent'
        });
        if (values['status'] == 'revoked' && b['cache_key'] != null) {
          await files.release(tx, [b['cache_key'] as String]);
        }
        return binding(id, tx: tx, active: values['status'] != 'revoked');
      }).then((b) async {
        if (values['status'] == 'revoked') await files.collect();
        return b;
      });
  Future<void> assignCache(String id, String key, String jobId,
          {int? expectedCacheRevision}) =>
      _transaction((tx) async {
        final b = await binding(id, tx: tx);
        if (expectedCacheRevision != null &&
            b['cache_revision'] != expectedCacheRevision) {
          throw const Failure(FailureCode.conflict,
              'Danmaku pool was replaced during acquisition.');
        }
        if (b['cache_job_id'] == jobId && b['cache_key'] == key) return;
        await tx.update(
            'danmaku_bindings',
            {
              'cache_key': key,
              'provenance': null,
              'cache_revision': (b['cache_revision'] as int) + 1,
              'cache_job_id': jobId
            },
            where: 'id = ?',
            whereArgs: [id]);
        if (b['cache_key'] != null && b['cache_key'] != key) {
          await files.release(tx, [b['cache_key'] as String]);
        }
      }).then((_) => files.collect());
  String cacheKey(DanmakuVideo v, DanmakuSource source,
          {String? refreshJobId}) =>
      stableMediaId('danmaku-cache', [
        v.sourceId,
        v.videoId,
        source.describe.version,
        source.describe.hosts,
        'public',
        'related=true',
        if (refreshJobId != null) {'refreshJobId': refreshJobId}
      ]);
  Future<DanmakuChunkResult?> chunk(String key, DanmakuChunk c,
          {bool fresh = true}) =>
      db.transaction((tx) async {
        final rows = await tx.query('danmaku_cache_chunks',
            where: 'cache_key = ? AND chunk_index = ?',
            whereArgs: [key, c.index]);
        if (rows.isEmpty) return null;
        final row = rows.single;
        if (row['start_ms'] != c.startMs ||
            row['end_ms'] != c.endMs ||
            fresh &&
                DateTime.parse(row['fetched_at'] as String).isBefore(
                    DateTime.now()
                        .toUtc()
                        .subtract(const Duration(hours: 2)))) {
          return null;
        }
        return DanmakuChunkResult([
          for (final e in await files.read(row))
            DanmakuEntry.fromJson(Map<String, Object?>.from(e as Map))
        ], coverage: row['coverage'] as String);
      });

  Future<void> saveChunk(
      String key, DanmakuChunk c, DanmakuChunkResult result) async {
    for (final e in result.entries) {
      if (e.sourceTimeMs < 0 ||
          e.colorRgb < 0 ||
          e.colorRgb > 16777215 ||
          e.text.length > 16384) {
        throw const SourceFailure(SourceStatus.schemaChanged);
      }
    }
    await db.transaction((tx) async {
      final reference = await files
          .write([for (final e in result.entries) e.toJson()], 'cache');
      await tx.insert(
          'danmaku_cache_chunks',
          {
            'cache_key': key,
            'chunk_index': c.index,
            'start_ms': c.startMs,
            'end_ms': c.endMs,
            ...reference,
            'coverage': result.coverage,
            'fetched_at': now
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    final readback = await chunk(key, c, fresh: false);
    if (readback == null ||
        jsonEncode([for (final e in readback.entries) e.toJson()]) !=
            jsonEncode([for (final e in result.entries) e.toJson()])) {
      throw const Failure(
          FailureCode.conflict, 'Danmaku cache readback failed.');
    }
    await files.collect();
  }

  Future<List<DanmakuEntry>> entries(String key) async {
    if (key.startsWith('sidecar:')) {
      final b = await binding(key.substring(8));
      final facts = b['local_file'] as JsonMap;
      if (facts['available'] != true) return [];
      return readSidecarEntries(facts['path'] as String);
    }
    // The transaction holds the content files until they are read.
    return db.transaction((tx) async => files.entries(
        key,
        await tx.query('danmaku_cache_chunks',
            where: 'cache_key = ?', whereArgs: [key], orderBy: 'chunk_index')));
  }

  /// How many comments a cache holds, as its chunks say (no content is read).
  Future<int> entryCount(String key) async => (await db.rawQuery(
          'SELECT COALESCE(SUM(COALESCE(entry_count,json_array_length(payload))),0) AS n '
          'FROM danmaku_cache_chunks WHERE cache_key = ?',
          [key]))
      .single['n'] as int;

  Future<List<JsonMap>> coverage(String key) async {
    if (key.startsWith('sidecar:')) {
      final b = await binding(key.substring(8), active: false);
      final facts = b['local_file'] as JsonMap;
      return [
        {...facts}..remove('timeCounts')
      ];
    }
    return db.query('danmaku_cache_chunks',
        columns: [
          'chunk_index',
          'start_ms',
          'end_ms',
          'coverage',
          'fetched_at',
          'file_path',
          'entry_count',
          'byte_count',
          'storage_kind'
        ],
        where: 'cache_key = ?',
        whereArgs: [key],
        orderBy: 'chunk_index');
  }

  Future<void> deleteCache(String key) => db.transaction((tx) async {
        await tx.delete('danmaku_cache_chunks',
            where: 'cache_key = ?', whereArgs: [key]);
        await tx.update('danmaku_bindings', {'cache_key': null},
            where: 'cache_key = ?', whereArgs: [key]);
      }).then((_) => files.collect());
}
