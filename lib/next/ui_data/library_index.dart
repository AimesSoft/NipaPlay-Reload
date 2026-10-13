import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Disposable local projection of the authenticated X47 catalogue.
Future<void> migrateLibraryIndex(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE next_library_index (
    id TEXT PRIMARY KEY, added INTEGER NOT NULL, payload TEXT NOT NULL,
    facts TEXT NOT NULL)''');
  await db.execute(
      'CREATE INDEX next_library_added ON next_library_index(added DESC,id)');
}

Future<void> replaceLibraryIndex(
    Database db, List<Map<String, Object?>> rows) async {
  await db.transaction((tx) async {
    final existing = {
      for (final r in await tx.query('next_library_index')) r['id']: r
    };
    final batch = tx.batch();
    for (final row in rows) {
      final value = {
        'id': row['id'],
        'added': row['added'],
        'payload': jsonEncode(row['payload']),
        'facts': jsonEncode(row['facts'])
      };
      final old = existing.remove(row['id']);
      if (old == null ||
          old['payload'] != value['payload'] ||
          old['facts'] != value['facts'] ||
          old['added'] != value['added']) {
        batch.insert('next_library_index', value,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    for (final id in existing.keys) {
      batch.delete('next_library_index', where: 'id=?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  });
}
