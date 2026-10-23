import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../util/slicer.dart';

/// Disposable local projection of the authenticated X47 catalogue.
Future<void> migrateLibraryIndex(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE next_library_index (
    id TEXT PRIMARY KEY, added INTEGER NOT NULL, payload TEXT NOT NULL,
    facts TEXT NOT NULL)''');
  await db.execute(
      'CREATE INDEX next_library_added ON next_library_index(added DESC,id)');
}

/// Makes the index hold [rows]: a row that is new or whose text differs is
/// written, the rest are left, and rows no longer wanted are deleted. The
/// existing rows are not read back; the database compares them.
Future<void> replaceLibraryIndex(
    Database db, List<Map<String, Object?>> rows,
    {Slicer? slice}) async {
  final encoded = <List<Object?>>[];
  for (final row in rows) {
    encoded.add([
      row['id'],
      row['added'],
      jsonEncode(row['payload']),
      jsonEncode(row['facts'])
    ]);
    if (slice != null) await slice();
  }
  await db.transaction((tx) async {
    final batch = tx.batch();
    for (final r in encoded) {
      batch.rawInsert(
          'INSERT INTO next_library_index(id,added,payload,facts) VALUES(?,?,?,?) '
          'ON CONFLICT(id) DO UPDATE SET added=excluded.added, payload=excluded.payload, facts=excluded.facts '
          'WHERE added IS NOT excluded.added OR payload IS NOT excluded.payload OR facts IS NOT excluded.facts',
          r);
    }
    batch.rawDelete(
        'DELETE FROM next_library_index WHERE id NOT IN (SELECT value FROM json_each(?))',
        [jsonEncode([for (final r in encoded) r[0]])]);
    await batch.commit(noResult: true);
  });
}
