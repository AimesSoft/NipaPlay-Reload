import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateSessions(Database db) async {
  await db.execute('''CREATE TABLE harness_sessions (
    repository TEXT PRIMARY KEY, main_thread TEXT NOT NULL,
    current_thread TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE harness_discoveries (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT NOT NULL,
    origin TEXT NOT NULL, invocation_id TEXT NOT NULL, repository TEXT NOT NULL,
    title TEXT NOT NULL, source TEXT NOT NULL, facts TEXT NOT NULL)''');
}

/// Stores identifiers only; transcripts and compression belong to Codex.
final class SessionStore {
  const SessionStore(this.database);
  final Database database;
  Future<String?> main(String repository) async =>
      (await database.query('harness_sessions',
              where: 'repository=?', whereArgs: [repository]))
          .firstOrNull?['main_thread'] as String?;
  Future<void> select(String repository, String id) async {
    await database.rawInsert('''INSERT INTO harness_sessions
      (repository,main_thread,current_thread) VALUES (?,?,?)
      ON CONFLICT(repository) DO UPDATE SET current_thread=excluded.current_thread''',
        [repository, id, id]);
  }
}
