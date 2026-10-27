import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateWorkMerges(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE media_entity_aliases (
    old_id TEXT PRIMARY KEY REFERENCES media_entities(id),
    entity_id TEXT NOT NULL REFERENCES media_entities(id))''');
  await db.execute('''CREATE TABLE media_work_merges (
    id TEXT PRIMARY KEY, origin TEXT NOT NULL, request_id TEXT NOT NULL,
    fingerprint TEXT NOT NULL, snapshot TEXT NOT NULL, result TEXT NOT NULL,
    state TEXT NOT NULL CHECK(state IN ('committed','undone')),
    UNIQUE(origin, request_id))''');
  for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
    await db.execute(
        'CREATE TRIGGER media_entity_aliases_epoch_${event.toLowerCase()} '
        'AFTER $event ON media_entity_aliases BEGIN '
        "INSERT INTO change_epochs VALUES ('catalogue', 1) "
        'ON CONFLICT(name) DO UPDATE SET n=n+1; END');
  }
}
