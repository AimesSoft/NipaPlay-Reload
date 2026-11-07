import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sqlite_library.dart';

const _table = 'next_external_sources_retirement';
const _types = {'jellyfin', 'emby', 'dandanplay_remote', 'nipaplay'};
bool _source(Object? value) =>
    value is String && _types.contains(value.split(':').first);
Map<String, dynamic> _json(Object? value) =>
    jsonDecode(value as String) as Map<String, dynamic>;

/// The schema upgrade only schedules work. JSON, graph cleanup and filesystem
/// work execute on a separate database connection in the retirement worker,
/// before Core constructs or starts the task engine.
Future<void> migrateExternalSources(DatabaseExecutor db) async {
  await db.execute('CREATE TABLE IF NOT EXISTS $_table '
      '(id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
  await db
      .rawInsert("INSERT OR IGNORE INTO $_table VALUES ('phase','pending')");
  // Fresh databases have nothing to scan. Preferences are still cleaned by
  // Core, whose platform services are attached before task restoration.
  await db.rawUpdate(
      "UPDATE $_table SET payload='database_done' WHERE id='phase' AND payload='pending' AND NOT EXISTS(SELECT 1 FROM media_entities) AND NOT EXISTS(SELECT 1 FROM jobs) AND NOT EXISTS(SELECT 1 FROM ui_cache)");
}

Future<void> finishExternalSourcesMigration(Directory root, Database db) async {
  final phase = await db.query(_table, where: 'id=?', whereArgs: ['phase']);
  if (phase.single['payload'] == 'done') return;
  if (phase.single['payload'] == 'database_done' &&
      (await db.query(_table, where: "id LIKE 'artwork:%'", limit: 1))
          .isEmpty) {
    return;
  }
  final databasePath = db.path, rootPath = root.path;
  await Isolate.run(() => _retireWorker(databasePath, rootPath));
}

/// Removes the retired sources' `next.source.<id>.*` preferences through
/// [keys] and [remove] (the application's preference store; a headless host
/// has none), then marks the retirement done.
Future<void> finishExternalSourcesPreferences(Database db,
    {required Future<Set<String>> Function() keys,
    required Future<bool> Function(String key) remove}) async {
  final phase = await db.query(_table, where: 'id=?', whereArgs: ['phase']);
  if (phase.single['payload'] == 'done') return;
  final rootPath = File(db.path).parent.path, databasePath = db.path;
  // Retry pending filesystem cleanup even after the database committed.
  if ((await db.query(_table, where: "id LIKE 'artwork:%'", limit: 1))
      .isNotEmpty) {
    await Isolate.run(() => _retireWorker(databasePath, rootPath));
  }
  // Only Next keys are removed; credentials and Classic source configuration
  // are never read here.
  for (final key in await keys()) {
    if (key.startsWith('next.source.') &&
        _source(key.substring('next.source.'.length))) {
      if (!await remove(key)) {
        throw StateError('无法清理已移除来源的 Next 偏好。');
      }
    }
  }
  await db.transaction((tx) async {
    await tx.delete(_table, where: 'id<>?', whereArgs: ['phase']);
    await tx.update(_table, {'payload': 'done'},
        where: 'id=?', whereArgs: ['phase']);
  });
}

Future<void> _retireWorker(String databasePath, String rootPath) async {
  sqfliteFfiInit();
  ensureSqliteLibrary();
  final db = await databaseFactoryFfiNoIsolate.openDatabase(databasePath,
      options: OpenDatabaseOptions(
          singleInstance: false,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys=ON');
            await db.execute('PRAGMA busy_timeout=5000');
          }));
  try {
    final phase = await db.query(_table, where: 'id=?', whereArgs: ['phase']);
    if (phase.single['payload'] == 'pending') {
      await retireExternalSources(db, rootPath);
    }
    // A failed unlink leaves its queue intact. Restart resumes these deletes
    // even though the database transaction already committed.
    for (final row in await db.query(_table, where: "id LIKE 'artwork:%'")) {
      final file = File(row['payload'] as String);
      if (await file.exists()) await file.delete();
    }
  } finally {
    await db.close();
  }
}

/// Called by the worker; also exposed for database fixture verification.
/// The database transaction is atomic and rerunning it is harmless.
Future<void> retireExternalSources(Database db, String rootPath) async {
  await db.transaction((tx) async {
    await tx.execute('PRAGMA defer_foreign_keys=ON');
    final schema = await tx.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    final dependants = <String, List<(String, String, String)>>{};
    for (final table in schema) {
      final name = table['name'] as String;
      for (final fk in await tx.rawQuery('PRAGMA foreign_key_list("$name")')) {
        (dependants[fk['table'] as String] ??= [])
            .add((name, fk['from'] as String, fk['to'] as String));
      }
    }
    final deleting = <String>{};
    Future<void> erase(String table, String column, Object? value) async {
      for (final row in await tx.rawQuery(
          'SELECT rowid AS retirement_rowid,* FROM "$table" WHERE "$column"=?',
          [value])) {
        final key = '$table:${row['retirement_rowid']}';
        if (!deleting.add(key)) continue;
        for (final (child, from, to)
            in dependants[table] ?? <(String, String, String)>[]) {
          if (child == 'media_entities') continue;
          await erase(child, from, row[to]);
        }
        await tx.rawDelete(
            'DELETE FROM "$table" WHERE rowid=?', [row['retirement_rowid']]);
      }
    }

    final entities = {
      for (final row in await tx.query('media_entities'))
        row['id'] as String: row
    };
    final doomed = <String>{}, locations = <String>{}, objects = <String>{};
    for (final row in await tx.query('media_external_objects')) {
      if (row['provider'] != 'https://sources.nipaplay.app') continue;
      final scope = jsonDecode(row['scope'] as String);
      if (scope is List && scope.any(_source)) objects.add(row['id'] as String);
    }
    for (final row in await tx.query('media_locations')) {
      final attrs = _json(entities[row['file_id']]?['attributes'] ?? '{}');
      final remote = attrs['remoteSource'] as Map?;
      final locator = row['locator'] as String;
      if (_source(row['source']) ||
          const {'jellyfin', 'emby', 'dandanplay'}
              .contains(Uri.tryParse(locator)?.scheme) ||
          (row['source'] == 'remote' && _types.contains(remote?['type']))) {
        locations.add(row['id'] as String);
      }
    }
    for (final id in locations) {
      await tx.delete('media_classic_current',
          where: 'location_id=?', whereArgs: [id]);
      await tx.delete('media_classic_observations',
          where: 'location_id=?', whereArgs: [id]);
      await tx.delete('media_legacy_history',
          where: 'location_id=?', whereArgs: [id]);
      await erase('media_locations', 'id', id);
    }
    final held = {
      for (final row in await tx.query('media_locations', columns: ['file_id']))
        row['file_id']
    };
    for (final entry in entities.entries) {
      final attrs = _json(entry.value['attributes']);
      if (entry.value['kind'] == 'file') {
        if (!held.contains(entry.key) &&
            _types.contains((attrs['remoteSource'] as Map?)?['type'])) {
          doomed.add(entry.key);
        }
      } else if (entry.key.startsWith('source-') &&
          (_source((attrs['sourceCatalog'] as Map?)?['sourceId']) ||
              _retiredEntity(entry.key))) {
        doomed.add(entry.key);
      }
    }
    // Old source entities may predate sourceCatalog attributes. Their native
    // binding still provides a scoped, explicit source ID.
    for (final row in await tx.query('media_bindings')) {
      if (objects.contains(row['object_id']) &&
          row['source'] == 'source_catalog' &&
          (row['entity_id'] as String).startsWith('source-')) {
        doomed.add(row['entity_id'] as String);
      }
    }
    // A person may have given a native entity an explicit platform identity.
    // It now belongs to that identity, including its local file relationships.
    // Keep its ID and hierarchy, removing only source-catalogue ownership.
    final retainedIdentities = <String>{};
    for (final row in await tx.rawQuery(
        "SELECT b.entity_id FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.status='accepted' AND b.source<>'source_catalog' AND o.provider<>'https://sources.nipaplay.app'")) {
      var id = row['entity_id'] as String?;
      while (id != null &&
          entities[id]?['kind'] != 'file' &&
          retainedIdentities.add(id)) {
        id = entities[id]?['parent_id'] as String?;
      }
    }
    for (final id in doomed.intersection(retainedIdentities).toList()) {
      doomed.remove(id);
      final attrs = _json(entities[id]!['attributes'])..remove('sourceCatalog');
      await tx.update('media_entities', {'attributes': jsonEncode(attrs)},
          where: 'id=?', whereArgs: [id]);
    }
    for (final row in await tx.query('media_file_episodes',
        where: "relation='source_catalog'")) {
      if (_retiredEntity(row['episode_id'] as String)) {
        await tx.delete('media_file_episodes',
            where: 'file_id=? AND episode_id=?',
            whereArgs: [row['file_id'], row['episode_id']]);
      }
    }

    final removedText = <String>[];
    for (final id in doomed) {
      removedText.add(jsonEncode(entities[id]));
    }
    for (final row in await tx.query('media_snapshots')) {
      if (objects.contains(row['object_id'])) {
        removedText.add(row['fields'] as String);
      }
    }
    for (final row in await tx.query('ui_cache')) {
      final id = row['id'] as String;
      if (_retiredCache(id)) {
        removedText.add(row['payload'] as String);
        await tx.delete('ui_cache', where: 'id=?', whereArgs: [id]);
      }
    }
    await tx.rawDelete(
        r"DELETE FROM media_projection_outbox WHERE json_type(payload,'$.remoteTarget') IS NOT NULL");
    // Remove foreign-key dependants first. No Classic database is opened.
    final bindings = <String>{};
    for (final row in await tx.query('media_bindings')) {
      if (doomed.contains(row['entity_id']) ||
          objects.contains(row['object_id'])) {
        bindings.add(row['id'] as String);
      }
    }
    for (final id in bindings) {
      await tx.delete('media_evidence', where: 'binding_id=?', whereArgs: [id]);
      await tx.update('media_bindings', {'supersedes': null},
          where: 'supersedes=?', whereArgs: [id]);
      await tx.update('media_classic_observations', {'binding_id': null},
          where: 'binding_id=?', whereArgs: [id]);
      await tx.delete('media_bindings', where: 'id=?', whereArgs: [id]);
    }
    for (final id in doomed) {
      await tx.update('media_entities', {'parent_id': null},
          where: 'parent_id=?', whereArgs: [id]);
    }
    for (final id in doomed) {
      await erase('media_entities', 'id', id);
    }
    for (final id in objects) {
      await erase('media_external_objects', 'id', id);
    }
    await _retireJobs(tx);

    final retainedText = <String>[];
    for (final table in [
      'media_entities',
      'media_snapshots',
      'ui_cache',
      'media_overrides',
      'media_metadata_edits'
    ]) {
      retainedText.add(jsonEncode(await tx.query(table)));
    }
    final artwork = Directory('$rootPath/source-artwork');
    if (await artwork.exists()) {
      final removed = removedText.join('\n'),
          retained = retainedText.join('\n');
      await for (final entry in artwork.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        // Covers are content-addressed; conservatively keep any file still
        // referenced by surviving metadata, including a shared local binding.
        if (removed.contains(name) && !retained.contains(name)) {
          await tx.insert(
              _table, {'id': 'artwork:$name', 'payload': entry.path},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    }
    await tx.update(_table, {'payload': 'database_done'},
        where: 'id=? AND payload<>?', whereArgs: ['phase', 'done']);
  });
}

bool _retiredCache(String id) {
  if (id.startsWith('library:layout:')) {
    return _source(id.substring('library:layout:'.length));
  }
  if (id.startsWith('library:parent:') ||
      id.startsWith('library:source-cache:') ||
      id.startsWith('library:directory:')) {
    try {
      final encoded = id.split(':')[2];
      final parts = jsonDecode(utf8.decode(base64Url.decode(encoded)));
      if (parts is List && parts.isNotEmpty) {
        final first = parts.first;
        return _source(first) || (first is String && _retiredCache(first));
      }
    } on FormatException {
      return false;
    }
  }
  return false;
}

bool _retiredEntity(String id) {
  if (!id.startsWith('source-')) return false;
  try {
    final ref = jsonDecode(
        utf8.decode(base64Url.decode(id.substring(id.indexOf(':') + 1))));
    return ref is List && ref.isNotEmpty && _source(ref.first);
  } on FormatException {
    return false;
  }
}

Future<void> _retireJobs(DatabaseExecutor tx) async {
  for (final row in await tx.query('jobs')) {
    final old = Job.fromJson(_json(row['snapshot']));
    if (old.state.isTerminal) continue;
    if (!_source(old.input['sourceId']) &&
        !old.type.startsWith('media.sources.remote_admin.') &&
        !old.type.startsWith('remote_admin.') &&
        !old.type.startsWith('remote.')) {
      continue;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final next = Job.fromJson({
      ...old.toStorageJson(),
      'state': 'failed',
      'phase': 'retired',
      'revision': old.revision + 1,
      'updatedAt': now,
      'decision': null,
      'retryAt': null,
      'error': const Failure(
              FailureCode.unavailable, 'Next 已移除此媒体来源；请在 Classic 中使用。')
          .toJson(),
      'receipt': JobReceipt(
          verification: VerificationLevel.acknowledged,
          details: {'reason': 'external_media_source_retired'}).toJson(),
    });
    await tx.update(
        'jobs',
        {
          'state': 'failed',
          'revision': next.revision,
          'snapshot': jsonEncode(next.toStorageJson())
        },
        where: 'job_id=?',
        whereArgs: [old.jobId]);
    await tx.insert('job_events', {
      'job_id': old.jobId,
      'revision': next.revision,
      'kind': 'source_retired',
      'at': now,
      'snapshot': jsonEncode(next.toJson())
    });
  }
}
