import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../media/media_migration.dart';
import '../danmaku/migration.dart';

final class SqliteJobStore implements JobStore {
  SqliteJobStore._(this._database);
  final Database _database;
  Database get database => _database;

  static Future<SqliteJobStore> open(Directory root,
      {DatabaseFactory? factory}) async {
    await root.create(recursive: true);
    if (factory == null) {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        factory = databaseFactoryFfi;
      } else {
        factory = databaseFactory;
      }
    }
    final database = await factory.openDatabase('${root.path}/next.db',
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE jobs ('
                'job_id TEXT PRIMARY KEY, type TEXT NOT NULL, state TEXT NOT NULL, '
                'revision INTEGER NOT NULL, created_at TEXT NOT NULL, snapshot TEXT NOT NULL)');
            await db
                .execute('CREATE INDEX jobs_state_type ON jobs(state, type)');
            await db.execute('CREATE TABLE job_events ('
                'job_id TEXT NOT NULL REFERENCES jobs(job_id), revision INTEGER NOT NULL, '
                'kind TEXT NOT NULL, at TEXT NOT NULL, snapshot TEXT NOT NULL, '
                'PRIMARY KEY(job_id, revision))');
            await migrateMediaIdentity(db);
            await migrateDanmaku(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) await migrateMediaIdentity(db);
            if (oldVersion < 3) await migrateDanmaku(db);
          },
        ));
    return SqliteJobStore._(database);
  }

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
        'snapshot': jsonEncode(event.snapshot)
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
