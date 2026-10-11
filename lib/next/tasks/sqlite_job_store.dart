import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../next_database.dart';
import '../state/change_history.dart';

final class SqliteJobStore implements JobStore {
  SqliteJobStore.fromDatabase(this._database);
  final Database _database;
  Database get database => _database;

  static Future<SqliteJobStore> open(Directory root,
          {DatabaseFactory? factory}) async =>
      SqliteJobStore.fromDatabase(
          await openNextDatabase(root, factory: factory));

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
    final rows = await _database.query('jobs',
        where: clauses.isEmpty ? null : clauses.join(' AND '),
        whereArgs: arguments,
        orderBy: 'created_at ASC, job_id ASC');
    return rows.map(_decode).toList();
  }

  @override
  Future<void> commit(Job job, JobEvent event,
      {required int? expectedRevision}) async {
    if (event.jobId != job.jobId ||
        event.revision != job.revision ||
        event.at != job.updatedAt ||
        jsonEncode(event.snapshot) != jsonEncode(job.toJson()) ||
        job.revision != (expectedRevision == null ? 0 : expectedRevision + 1)) {
      throw ArgumentError(
          'Snapshot and event must describe the same revision.');
    }
    await _database.transaction((transaction) async {
      final values = {
        'job_id': job.jobId,
        'type': job.type,
        'state': job.state.wireName,
        'revision': job.revision,
        'created_at': job.createdAt.toIso8601String(),
        'snapshot': jsonEncode(job.toStorageJson())
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
              ? 'hook:${job.details['event']}' : invocation?.origin ?? 'application',
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
        'origin': job.type == 'harness.hook' ? 'hook:${job.details['event']}' : BodyChanges.invocation?.origin,
        'invocation_id': BodyChanges.invocation?.id,
      });
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

  Job _decode(Map<String, Object?> row) =>
      Job.fromJson(jsonDecode(row['snapshot'] as String) as JsonMap);

  @override
  Future<void> close() => _database.close();
}
