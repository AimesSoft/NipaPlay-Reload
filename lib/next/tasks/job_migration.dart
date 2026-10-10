import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateJobs(DatabaseExecutor db) async {
  await db.execute('CREATE TABLE jobs ('
      'job_id TEXT PRIMARY KEY, type TEXT NOT NULL, state TEXT NOT NULL, '
      'revision INTEGER NOT NULL, created_at TEXT NOT NULL, snapshot TEXT NOT NULL)');
  await db.execute('CREATE INDEX jobs_state_type ON jobs(state, type)');
  await db.execute('CREATE TABLE job_events ('
      'job_id TEXT NOT NULL REFERENCES jobs(job_id), revision INTEGER NOT NULL, '
      'kind TEXT NOT NULL, at TEXT NOT NULL, snapshot TEXT NOT NULL, '
      'PRIMARY KEY(job_id, revision))');
}
