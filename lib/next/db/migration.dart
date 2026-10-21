import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Audit of direct database writes. `changes` keeps the full row images that
/// `db.undo` restores from; `undoes` names the commit an undo reverses.
Future<void> migrateDbCommits(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS db_commits (
    id TEXT PRIMARY KEY,
    sequence INTEGER NOT NULL UNIQUE,
    kind TEXT NOT NULL CHECK(kind IN ('write','undo')),
    at TEXT NOT NULL,
    actor TEXT NOT NULL,
    origin TEXT NOT NULL,
    invocation_id TEXT,
    reason TEXT,
    statements TEXT NOT NULL,
    counts TEXT NOT NULL,
    changes TEXT NOT NULL,
    undoes TEXT REFERENCES db_commits(id))''');
}
