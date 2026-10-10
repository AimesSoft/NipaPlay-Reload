import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateMetadataEdits(DatabaseExecutor db) async {
  await db.execute(
      "ALTER TABLE media_overrides ADD COLUMN mode TEXT NOT NULL DEFAULT 'persistent'");
  await db.execute(
      "ALTER TABLE media_overrides ADD COLUMN actor TEXT NOT NULL DEFAULT 'user'");
  await db.execute(
      "ALTER TABLE media_overrides ADD COLUMN origin TEXT NOT NULL DEFAULT 'gui'");
  await db.execute(
      "ALTER TABLE media_overrides ADD COLUMN changed_at TEXT NOT NULL DEFAULT ''");
  await db.execute('''CREATE TABLE media_metadata_edits (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT, entity_id TEXT NOT NULL,
    field TEXT NOT NULL, value TEXT NOT NULL, mode TEXT NOT NULL,
    actor TEXT NOT NULL, origin TEXT NOT NULL, invocation_id TEXT NOT NULL,
    changed_at TEXT NOT NULL)''');
}
