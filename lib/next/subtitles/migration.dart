import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateSubtitles(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS file_subtitles (
    file_id TEXT PRIMARY KEY REFERENCES media_entities(id),
    facts TEXT NOT NULL)''');
}
