import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateUiData(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE ui_presentations (
    id INTEGER PRIMARY KEY AUTOINCREMENT, thread_id TEXT NOT NULL,
    turn_id TEXT NOT NULL, cards TEXT NOT NULL, origin TEXT NOT NULL,
    invocation_id TEXT NOT NULL, created_at TEXT NOT NULL)''');
  await db.execute('''CREATE INDEX ui_presentations_turn
    ON ui_presentations(thread_id,turn_id)''');
  await db.execute('''CREATE TABLE ui_shelves (
    id TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE ui_cache (
    id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, payload TEXT NOT NULL)''');
}
