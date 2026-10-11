import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/danmaku/migration.dart';
import 'package:nipaplay/next/media/media_migration.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/followups/migration.dart';
import 'package:nipaplay/next/ui_data/migration.dart';
import 'package:nipaplay/next/tasks/job_migration.dart';
import 'package:nipaplay/next/settings/migration.dart';
import 'package:nipaplay/next/media/primitives_migration.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/metadata_edit_migration.dart';
import 'package:nipaplay/next/media/classic_match_migration.dart';
import 'package:nipaplay/next/state/change_history.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('v5 user overrides retain values and host provenance after migration',
      () async {
    final root = await Directory.systemTemp.createTemp('next-overrides-v5-');
    addTearDown(() => root.delete(recursive: true));
    final old = await databaseFactoryFfi.openDatabase('${root.path}/next.db',
        options: OpenDatabaseOptions(
            version: 5,
            onCreate: (db, version) async {
              for (final migration in [
                migrateJobs,
                migrateMediaIdentity,
                migrateDanmaku,
                migrateSettings,
                migrateMediaPrimitives
              ]) {
                await migration(db);
              }
            }));
    await old.insert('media_entities', {
      'id': 'legacy-work',
      'kind': 'work',
      'revision': 0,
      'attributes': '{"title":"Legacy"}'
    });
    await old.insert('media_overrides', {
      'entity_id': 'legacy-work',
      'field': 'title',
      'value': '"User title"',
      'invocation_id': 'legacy-invocation'
    });
    await old.close();
    final db = await openNextDatabase(root, factory: databaseFactoryFfi);
    addTearDown(db.close);
    final row = (await db.query('media_overrides')).single;
    expect(row['mode'], 'persistent');
    expect(row['actor'], 'user');
    expect(row['origin'], 'gui');
    final metadata =
        await IdentityStore(db, 'device').mergedMetadata('legacy-work');
    expect((metadata['fields'] as Map)['title'], 'User title');
    expect(((metadata['provenance'] as Map)['title'] as Map)['invocationId'],
        'legacy-invocation');
  });
  for (final oldVersion in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]) {
    test('database v$oldVersion upgrades to the complete shared schema',
        () async {
      final root = await Directory.systemTemp.createTemp('next-migration-');
      addTearDown(() => root.delete(recursive: true));
      const migrations = [
        migrateJobs,
        migrateMediaIdentity,
        migrateDanmaku,
        migrateSettings,
        migrateMediaPrimitives,
        migrateMetadataEdits,
        migrateDanmakuImports,
        migrateClassicMatches,
        migrateChangeHistory,
        migrateFollowups,
        migrateUiData,
      ];
      if (oldVersion > 0) {
        final old =
            await databaseFactoryFfi.openDatabase('${root.path}/next.db',
                options: OpenDatabaseOptions(
                  version: oldVersion,
                  onCreate: (db, version) async {
                    for (var i = 0; i < version; i++) {
                      await migrations[i](db);
                    }
                  },
                ));
        await old.close();
      }
      var db = await openNextDatabase(root, factory: databaseFactoryFfi);
      addTearDown(() => db.close());
      expect(await db.getVersion(), 12);
      for (final table in [
        'ui_presentations',
        'ui_shelves',
        'ui_cache',
        'body_changes',
        'followups',
        'followup_events',
        'followup_hook_events',
        'task_origins',
        'jobs',
        'media_entities',
        'danmaku_bindings',
        'settings_changes',
        'media_metadata_edits',
        'media_classic_observations',
        'media_classic_current',
      ]) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      await db.insert('settings_changes', {
        'key': 'danmaku.opacity',
        'previous_value': '1.0',
        'value': '0.5',
        'changed_at': '2026-10-11T00:00:00Z',
        'changed_by': 'user',
        'origin': 'gui',
        'invocation_id': 'migration-test',
        'revision': 1,
      });
      expect((await db.query('settings_changes')).single['value'], '0.5');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
      db = await openNextDatabase(root, factory: databaseFactoryFfi);
      expect((await db.query('settings_changes')).single['revision'], 1);
    });
  }

  test(
      'v7 upgrade preserves every released table row including identity and receipts',
      () async {
    final root = await Directory.systemTemp.createTemp('next-library-v7-');
    addTearDown(() => root.delete(recursive: true));
    final old = await databaseFactoryFfi.openDatabase('${root.path}/next.db',
        options: OpenDatabaseOptions(
            version: 7,
            onCreate: (db, version) async {
              for (final migration in [
                migrateJobs,
                migrateMediaIdentity,
                migrateDanmaku,
                migrateSettings,
                migrateMediaPrimitives,
                migrateMetadataEdits,
                migrateDanmakuImports
              ]) {
                await migration(db);
              }
            }));
    await old.insert('jobs', {
      'job_id': 'original-job',
      'type': 'fixture',
      'state': 'succeeded',
      'revision': 2,
      'created_at': '2026-10-10T00:00:00Z',
      'snapshot': '{"receipt":{"original":true}}'
    });
    await old.insert('job_events', {
      'job_id': 'original-job',
      'revision': 2,
      'kind': 'succeeded',
      'at': '2026-10-10T00:00:00Z',
      'snapshot': '{"receipt":{"original":true}}'
    });
    await old.insert('media_entities', {
      'id': 'original-file',
      'kind': 'file',
      'revision': 3,
      'attributes': '{"probe":{},"bindingRevision":5}'
    });
    await old.insert('media_locations', {
      'id': 'original-location',
      'file_id': 'original-file',
      'source': 'local',
      'owner_device_id': 'fixture-device',
      'locator': '/fixture/media/video.mkv',
      'available': 1
    });
    await old.insert('media_external_objects', {
      'id': 'original-object',
      'provider': 'dandanplay',
      'object_type': 'episode',
      'external_id': '7101',
      'scope': 'anime/7001'
    });
    await old.insert('media_bindings', {
      'id': 'original-binding',
      'entity_id': 'original-file',
      'object_id': 'original-object',
      'relation': 'exact',
      'scope': '{}',
      'status': 'accepted',
      'source': 'agent_evidence',
      'bound_by': 'agent',
      'revision': 5,
      'job_id': 'original-job',
      'created_at': '2026-10-10T00:00:00Z'
    });
    await old.insert('media_evidence', {
      'id': 'original-evidence',
      'binding_id': 'original-binding',
      'job_id': 'original-job',
      'source': 'agent_evidence',
      'payload': '{"reason":"original"}',
      'created_at': '2026-10-10T00:00:00Z'
    });
    await old.insert('media_snapshots', {
      'id': 'original-snapshot',
      'object_id': 'original-object',
      'language': 'zh-CN',
      'fetched_at': '2026-10-10T00:00:00Z',
      'fields': '{"title":"Original title"}'
    });
    await old.insert('media_projection_outbox', {
      'id': 'original-projection',
      'file_id': 'original-file',
      'file_revision': 3,
      'binding_revision': 5,
      'payload': '{"animeId":7001,"episodeId":7101}',
      'state': 'delivered'
    });
    await old.insert('media_legacy_history', {
      'location_id': 'original-location',
      'fingerprint': 'original-fingerprint',
      'payload': '{"provenance":"legacy_unknown","animeId":7001}'
    });
    final tables = await old.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
    final before = {
      for (final row in tables)
        row['name'] as String:
            await old.rawQuery('SELECT * FROM "${row['name']}" ORDER BY rowid')
    };
    await old.close();
    final upgraded = await openNextDatabase(root, factory: databaseFactoryFfi);
    addTearDown(upgraded.close);
    await migrateClassicMatches(upgraded);
    for (final entry in before.entries) {
      expect(
          await upgraded
              .rawQuery('SELECT * FROM "${entry.key}" ORDER BY rowid'),
          [for (final row in entry.value) {...row,
            if (entry.key == 'job_events') ...{'origin': null, 'invocation_id': null}}],
          reason: entry.key);
    }
    expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
