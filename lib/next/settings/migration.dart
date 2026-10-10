import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateSettings(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE settings_changes (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT NOT NULL,
    previous_value TEXT NOT NULL,
    value TEXT NOT NULL,
    changed_at TEXT NOT NULL,
    changed_by TEXT NOT NULL,
    origin TEXT NOT NULL,
    reason TEXT,
    invocation_id TEXT NOT NULL,
    revision INTEGER NOT NULL,
    UNIQUE(key, revision)
  )''');
  await db.execute(
      'CREATE INDEX settings_changes_key ON settings_changes(key, revision)');
}
