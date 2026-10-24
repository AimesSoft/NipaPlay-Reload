import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../next_database.dart';
import '../state/change_history.dart';
import '../util/slicer.dart';

final class SqliteJobStore implements JobStore {
  SqliteJobStore.fromDatabase(this._database);
  final Database _database;
  Database get database => _database;

  static Future<SqliteJobStore> open(Directory root,
          {DatabaseFactory? factory}) async =>
      SqliteJobStore.fromDatabase(
          await openNextDatabase(root, factory: factory));

  /// Each job as last decoded, with the revision it was decoded at. A stored
  /// snapshot never changes without its revision moving (commit requires the
  /// next revision), and a Job is immutable, so a job whose stored revision
  /// matches is returned as it was decoded instead of decoding and copying
  /// its snapshot again: listing every task costs what changed, not what the
  /// task history holds.
  final _decoded = <String, Job>{};

  @override
  Future<Job?> get(String jobId) async {
    final rows =
        await _database.query('jobs', where: 'job_id = ?', whereArgs: [jobId]);
    return rows.isEmpty ? null : _decode(rows.single);
  }

  @override
  Future<List<Job>> list({JobState? state, String? type}) async {
    final clauses = <String>[], arguments = <Object?>[];
    if (state != null) {
      clauses.add('state = ?');
      arguments.add(state.wireName);
    }
    if (type != null) {
      clauses.add('type = ?');
      arguments.add(type);
    }
    return _listWhere(clauses, arguments);
  }

  @override
  Future<List<Job>> listActive() => _listWhere([
        'state NOT IN (?, ?, ?)'
      ], [
        JobState.succeeded.wireName,
        JobState.failed.wireName,
        JobState.cancelled.wireName,
      ]);

  Future<List<Job>> _listWhere(
      List<String> clauses, List<Object?> arguments) async {
    final where = clauses.isEmpty ? null : clauses.join(' AND ');
    final count = (await _database.rawQuery(
            'SELECT COUNT(*) AS n FROM jobs${where == null ? "" : " WHERE $where"}',
            arguments))
        .single['n'] as int;
    final slice = Slicer();
    final rows = <Map<String, Object?>>[];
    for (var offset = 0; offset < count || offset == 0; offset += 250) {
      final page = await _database.query('jobs',
          columns: ['job_id', 'revision'],
          where: where,
          whereArgs: arguments,
          orderBy: 'created_at ASC, job_id ASC',
          limit: 250,
          offset: offset);
      rows.addAll(page);
      await slice();
      if (page.length < 250) break;
    }
    final known = <String, Job>{};
    final stale = <String>[];
    for (final row in rows) {
      final id = row['job_id'] as String, job = _decoded[id];
      if (job != null && job.revision == row['revision']) {
        known[id] = job;
      } else {
        stale.add(id);
      }
    }
    // Only what changed since it was last decoded is read in full. A job
    // that moved on between the two reads is returned at its newer revision.
    for (var start = 0; start < stale.length; start += 64) {
      final ids = stale.sublist(start, (start + 64).clamp(0, stale.length));
      for (final row in await _database.query('jobs',
          where: 'job_id IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids)) {
        known[row['job_id'] as String] = _decode(row);
        await slice();
      }
    }
    return [
      for (final row in rows)
        if (known[row['job_id']] case final job?) job
    ];
  }

  @override
  Future<List<Job>> listRecent(
      {JobState? state, String? type, int limit = 20, int offset = 0}) async {
    if (limit < 1 || limit > 500 || offset < 0) {
      throw ArgumentError('Recent job pages require 1..500 rows.');
    }
    final clauses = <String>[], arguments = <Object?>[];
    if (state != null) {
      clauses.add('state = ?');
      arguments.add(state.wireName);
    }
    if (type != null) {
      clauses.add('type = ?');
      arguments.add(type);
    }
    final where = clauses.isEmpty ? null : clauses.join(' AND ');
    final rows = await _database.query('jobs',
        columns: ['job_id', 'revision'],
        where: where,
        whereArgs: arguments,
        orderBy: r"json_extract(snapshot, '$.updatedAt') DESC, job_id DESC",
        limit: limit,
        offset: offset);
    final stale = <String>[];
    final known = <String, Job>{};
    for (final row in rows) {
      final cached = _decoded[row['job_id'] as String];
      if (cached != null && cached.revision == row['revision']) {
        known[cached.jobId] = cached;
      } else {
        stale.add(row['job_id'] as String);
      }
    }
    for (var start = 0; start < stale.length; start += 64) {
      final ids = stale.sublist(start, (start + 64).clamp(0, stale.length));
      for (final row in await _database.query('jobs',
          where: 'job_id IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids)) {
        final job = _decode(row);
        known[job.jobId] = job;
      }
    }
    return [
      for (final row in rows)
        if (known[row['job_id']] case final job?) job
    ];
  }

  /// Terminal download records whose backend session disappeared from the
  /// current listing. This asks SQLite for the few fields needed to decide,
  /// rather than decoding every historical download snapshot (whose
  /// checkpoints grow with their completed files) on the UI isolate.
  Future<List<String>> missingDownloadSessionIds({
    required String backendKind,
    required String? backendId,
    required Set<String> presentHashes,
  }) async {
    const pageSize = 256;
    final ids = <String>[];
    final slice = Slicer();
    for (var offset = 0;; offset += pageSize) {
      final rows = await _database.rawQuery(r'''
SELECT job_id, json_extract(snapshot, '$.input.infoHash') AS info_hash
FROM jobs
WHERE type = 'download'
  AND state IN ('succeeded', 'failed', 'cancelled')
  AND json_extract(snapshot, '$.sideEffectCommitted') = 1
  AND json_extract(snapshot, '$.details.backend.kind') = ?
  AND COALESCE(json_extract(snapshot, '$.details.backend.id'), '') = ?
  AND COALESCE(
        json_extract(snapshot, '$.receipt.details.sessionPresent'), 1) != 0
ORDER BY created_at ASC, job_id ASC
LIMIT ? OFFSET ?''', [backendKind, backendId ?? '', pageSize, offset]);
      for (final row in rows) {
        final hash = row['info_hash'];
        if (hash is String && !presentHashes.contains(hash)) {
          ids.add(row['job_id'] as String);
        }
      }
      await slice();
      if (rows.length < pageSize) break;
    }
    return ids;
  }

  @override
  Future<void> commit(Job job, JobEvent event,
      {required int? expectedRevision}) async {
    if (event.jobId != job.jobId ||
        event.revision != job.revision ||
        event.at != job.updatedAt ||
        (!identical(event.snapshot, job.toJson()) &&
            jsonEncode(event.snapshot) != jsonEncode(job.toJson())) ||
        job.revision != (expectedRevision == null ? 0 : expectedRevision + 1)) {
      throw ArgumentError(
          'Snapshot and event must describe the same revision.');
    }
    final encodedSnapshot = jsonEncode(job.toStorageJson());
    await _database.transaction((transaction) async {
      final values = {
        'job_id': job.jobId,
        'type': job.type,
        'state': job.state.wireName,
        'revision': job.revision,
        'created_at': job.createdAt.toIso8601String(),
        'snapshot': encodedSnapshot
      };
      if (expectedRevision == null) {
        final existing = await transaction.query('jobs',
            columns: ['job_id'], where: 'job_id = ?', whereArgs: [job.jobId]);
        if (existing.isNotEmpty) {
          throw const Failure(FailureCode.conflict, 'Job already exists.');
        }
        await transaction.insert('jobs', values);
        final invocation = BodyChanges.invocation;
        await transaction.insert('task_origins', {
          'job_id': job.jobId,
          'origin': job.type == 'harness.hook'
              ? 'hook:${job.details['event']}'
              : invocation?.origin ?? 'application',
          'invocation_id': invocation?.id,
        });
      } else {
        final count = await transaction.update('jobs', values,
            where: 'job_id = ? AND revision = ?',
            whereArgs: [job.jobId, expectedRevision]);
        if (count != 1) {
          throw const Failure(FailureCode.conflict, 'Stale job revision.');
        }
      }
      await transaction.insert('job_events', {
        'job_id': event.jobId,
        'revision': event.revision,
        'kind': event.kind,
        'at': event.at.toIso8601String(),
        'snapshot': jsonEncode(event.snapshot),
        'origin': job.type == 'harness.hook'
            ? 'hook:${job.details['event']}'
            : BodyChanges.invocation?.origin,
        'invocation_id': BodyChanges.invocation?.id,
      });
    });
    _decode({
      'job_id': job.jobId,
      'revision': job.revision,
      'snapshot': encodedSnapshot
    });
  }

  @override
  Future<List<JobEvent>> events(String jobId, {int afterRevision = -1}) async {
    final rows = await _database.query('job_events',
        where: 'job_id = ? AND revision > ?',
        whereArgs: [jobId, afterRevision],
        orderBy: 'revision ASC');
    return [
      for (final row in rows)
        JobEvent(
            jobId: row['job_id'] as String,
            revision: row['revision'] as int,
            kind: row['kind'] as String,
            at: DateTime.parse(row['at'] as String).toUtc(),
            snapshot: jsonDecode(row['snapshot'] as String) as JsonMap)
    ];
  }

  /// What is returned is always decoded from storage, as before; the job
  /// committed in memory is not cached, since storage keeps less of it (a
  /// failure's details, for one).
  Job _decode(Map<String, Object?> row) {
    final id = row['job_id'] as String;
    final cached = _decoded[id];
    if (cached != null && cached.revision == row['revision']) return cached;
    final job = Job.fromJson(jsonDecode(row['snapshot'] as String) as JsonMap);
    if (cached == null || cached.revision < job.revision) _decoded[id] = job;
    return job;
  }

  @override
  Future<void> close() => _database.close();
}
