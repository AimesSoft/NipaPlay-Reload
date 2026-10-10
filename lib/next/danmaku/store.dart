import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../media/identity_store.dart';
import '../media/metadata_provider.dart';
import 'source.dart';

final class DanmakuStore {
  const DanmakuStore(this.identities);
  final IdentityStore identities;
  Database get db => identities.database;
  String get now => DateTime.now().toUtc().toIso8601String();
  JsonMap decodeBinding(JsonMap b) => {
        ...b,
        'video': decodeMediaJson(b['video']),
        'evidence': decodeMediaJson(b['evidence']),
        'alignment': decodeMediaJson(b['alignment'])
      };
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
      db.transaction((tx) async {
        final entity = await identities.entity(entityId, db: tx);
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
          'video': video.toJson(),
          'reason': reason,
          'url': url
        });
        return id;
      });
  Future<List<JsonMap>> bindings(String entityId) async {
    await identities.entity(entityId);
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
  }

  Future<JsonMap> change(
          String id, int revision, JsonMap values, Invocation invocation,
          {JsonMap? alignment, String? reason}) =>
      db.transaction((tx) async {
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
        return binding(id, tx: tx, active: values['status'] != 'revoked');
      });
  Future<void> assignCache(String id, String key, String jobId) =>
      db.transaction((tx) async {
        final b = await binding(id, tx: tx);
        if (b['cache_job_id'] == jobId && b['cache_key'] == key) return;
        await tx.update(
            'danmaku_bindings',
            {
              'cache_key': key,
              'cache_revision': (b['cache_revision'] as int) + 1,
              'cache_job_id': jobId
            },
            where: 'id = ?',
            whereArgs: [id]);
      });
  String cacheKey(DanmakuVideo v, DanmakuSource source, DanmakuAccess? access,
          {String? refreshJobId}) =>
      stableMediaId('danmaku-cache', [
        v.sourceId,
        v.videoId,
        source.describe.version,
        source.describe.hosts,
        access?.credentialRef ?? 'public',
        'related=true',
        if (refreshJobId != null) {'refreshJobId': refreshJobId}
      ]);
  Future<DanmakuChunkResult?> chunk(String key, DanmakuChunk c,
      {bool fresh = true}) async {
    final rows = await db.query('danmaku_cache_chunks',
        where: 'cache_key = ? AND chunk_index = ?', whereArgs: [key, c.index]);
    if (rows.isEmpty) return null;
    final row = rows.single;
    if (row['start_ms'] != c.startMs ||
        row['end_ms'] != c.endMs ||
        fresh &&
            DateTime.parse(row['fetched_at'] as String).isBefore(
                DateTime.now().toUtc().subtract(const Duration(hours: 2)))) {
      return null;
    }
    return DanmakuChunkResult([
      for (final e in jsonDecode(row['payload'] as String) as List)
        DanmakuEntry.fromJson(Map<String, Object?>.from(e as Map))
    ], coverage: row['coverage'] as String);
  }

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
    await db.insert(
        'danmaku_cache_chunks',
        {
          'cache_key': key,
          'chunk_index': c.index,
          'start_ms': c.startMs,
          'end_ms': c.endMs,
          'payload': jsonEncode([for (final e in result.entries) e.toJson()]),
          'coverage': result.coverage,
          'fetched_at': now
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    final readback = await chunk(key, c, fresh: false);
    if (readback == null ||
        jsonEncode([for (final e in readback.entries) e.toJson()]) !=
            jsonEncode([for (final e in result.entries) e.toJson()])) {
      throw const Failure(
          FailureCode.conflict, 'Danmaku cache readback failed.');
    }
  }

  Future<List<DanmakuEntry>> entries(String key) async {
    final rows = await db.query('danmaku_cache_chunks',
        where: 'cache_key = ?', whereArgs: [key], orderBy: 'chunk_index');
    final entries = <DanmakuEntry>[];
    final seen = <String>{};
    for (final row in rows) {
      for (final raw in jsonDecode(row['payload'] as String) as List) {
        final e = DanmakuEntry.fromJson(Map<String, Object?>.from(raw as Map));
        final identity = e.sourceEntryId != null
            ? jsonEncode([e.sourceId, e.videoId, e.sourceEntryId])
            : e.platformId != null
                ? jsonEncode([
                    e.sourceId,
                    e.videoId,
                    e.platform,
                    e.originVideoId,
                    e.platformId
                  ])
                : e.sender != null
                    ? jsonEncode([
                        e.sourceId,
                        e.videoId,
                        e.platform,
                        e.sender,
                        e.sourceTimeMs,
                        e.text,
                        e.mode,
                        e.colorRgb
                      ])
                    : null;
        if (identity == null || seen.add(identity)) {
          if (entries.length >= 100000) {
            throw const SourceFailure(SourceStatus.schemaChanged);
          }
          entries.add(e);
        }
      }
    }
    entries.sort((a, b) => a.sourceTimeMs.compareTo(b.sourceTimeMs));
    return entries;
  }

  Future<List<JsonMap>> coverage(String key) async => db.query(
      'danmaku_cache_chunks',
      columns: ['chunk_index', 'start_ms', 'end_ms', 'coverage', 'fetched_at'],
      where: 'cache_key = ?',
      whereArgs: [key],
      orderBy: 'chunk_index');
  Future<void> deleteCache(String key) => db.transaction((tx) async {
        await tx.delete('danmaku_cache_chunks',
            where: 'cache_key = ?', whereArgs: [key]);
        await tx.update('danmaku_bindings', {'cache_key': null},
            where: 'cache_key = ?', whereArgs: [key]);
      });
}
