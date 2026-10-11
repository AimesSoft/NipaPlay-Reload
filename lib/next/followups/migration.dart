import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateFollowups(Database db) async {
  await db.execute('''CREATE TABLE followups (
    id TEXT PRIMARY KEY,
    state TEXT NOT NULL CHECK(state IN ('waiting','ready','dispatching','started','completed','execution_failed','cancelled')),
    snapshot TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE followup_events (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    followup_id TEXT NOT NULL REFERENCES followups(id),
    at TEXT NOT NULL,
    type TEXT NOT NULL,
    origin TEXT NOT NULL,
    invocation_id TEXT,
    facts TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE followup_hook_events (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    event TEXT NOT NULL,
    object_id TEXT NOT NULL,
    payload TEXT NOT NULL
  )''');
}
