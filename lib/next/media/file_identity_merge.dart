import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateFileAliases(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE media_file_aliases (
    old_id TEXT PRIMARY KEY REFERENCES media_entities(id),
    file_id TEXT NOT NULL REFERENCES media_entities(id),
    archived TEXT NOT NULL)''');
  final paths = await db.rawQuery(
      "SELECT owner_device_id,locator FROM media_locations WHERE source='remote'");
  for (final path in paths) {
    await mergeLegacyRemoteFile(
        db, path['owner_device_id'] as String, path['locator'] as String);
  }
}

/// Only the ambiguous legacy scope can be absorbed. Distinct server scopes
/// remain distinct even when a server reuses the same URL.
Future<void> mergeLegacyRemoteFile(
    DatabaseExecutor db, String owner, String locator) async {
  final rows = await db.query('media_locations',
      where: 'owner_device_id=? AND locator=?',
      whereArgs: [owner, locator],
      orderBy: 'rowid');
  final legacy = rows.where((r) => r['source'] == 'remote').firstOrNull;
  final scoped = rows.where((r) => r['source'] != 'remote').toList();
  if (legacy == null ||
      scoped.isEmpty ||
      scoped.map((r) => r['file_id']).toSet().length != 1) return;
  final old = legacy['file_id'] as String,
      target = scoped.first['file_id'] as String;
  if (old == target) return;
  final entity =
      (await db.query('media_entities', where: 'id=?', whereArgs: [old]))
          .single;
  final canonical =
      (await db.query('media_entities', where: 'id=?', whereArgs: [target]))
          .single;
  final archive = <String, Object?>{'entity': entity};
  for (final spec in [
    ('media_locations', 'file_id'),
    ('media_file_episodes', 'file_id'),
    ('media_bindings', 'entity_id'),
    ('media_overrides', 'entity_id'),
    ('media_projection_outbox', 'file_id'),
    ('media_scan_items', 'file_id'),
    ('danmaku_bindings', 'entity_id'),
    ('media_metadata_edits', 'entity_id')
  ]) {
    archive[spec.$1] =
        await db.query(spec.$1, where: '${spec.$2}=?', whereArgs: [old]);
  }
  await db.insert('media_file_aliases',
      {'old_id': old, 'file_id': target, 'archived': jsonEncode(archive)});
  final attrs = jsonDecode(canonical['attributes'] as String) as Map;
  final previous = jsonDecode(entity['attributes'] as String) as Map;
  final bindingRevision = (attrs['bindingRevision'] as int) >
          (previous['bindingRevision'] as int)
      ? attrs['bindingRevision'] : previous['bindingRevision'];
  // Keep the content revision and advance from both binding histories.
  await db.update(
      'media_entities',
      {
        'attributes': jsonEncode({...previous, ...attrs,
          'bindingRevision': bindingRevision})
      },
      where: 'id=?',
      whereArgs: [target]);
  for (final spec in [
    ('media_locations', 'file_id'),
    ('media_bindings', 'entity_id'),
    ('media_projection_outbox', 'file_id'),
    ('media_metadata_edits', 'entity_id')
  ]) {
    await db.update(spec.$1, {spec.$2: target},
        where: '${spec.$2}=?', whereArgs: [old]);
  }
  for (final row
      in (archive['danmaku_bindings'] as List).cast<Map<String, Object?>>()) {
    await db.update(
        'danmaku_bindings',
        {
          'entity_id': target,
          'entity_revision': row['entity_revision'] == entity['revision']
              ? canonical['revision']
              : -1
        },
        where: 'id=?',
        whereArgs: [row['id']]);
  }
  for (final spec in [
    ('media_file_episodes', 'file_id'),
    ('media_overrides', 'entity_id'),
    ('media_scan_items', 'file_id')
  ]) {
    for (final row in (archive[spec.$1] as List).cast<Map<String, Object?>>()) {
      await db.insert(spec.$1, {...row, spec.$2: target},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await db.delete(spec.$1, where: '${spec.$2}=?', whereArgs: [old]);
  }
  // Keep old entity IDs for immutable task inputs, receipts and audit references.
  await db.update('media_file_aliases', {'file_id': target},
      where: 'file_id=?', whereArgs: [old]);
}

Future<String> canonicalFileId(DatabaseExecutor db, String id) async {
  final rows = await db.query('media_file_aliases',
      columns: ['file_id'], where: 'old_id=?', whereArgs: [id]);
  return rows.isEmpty ? id : rows.single['file_id'] as String;
}
