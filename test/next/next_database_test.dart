import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/danmaku/migration.dart';
import 'package:nipaplay/next/media/media_migration.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/tasks/job_migration.dart';
import 'package:nipaplay/next/settings/migration.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  for (final oldVersion in [0, 1, 2, 3, 4, 5]) {
    test('database v$oldVersion upgrades to the complete shared schema',
        () async {
      final root = await Directory.systemTemp.createTemp('next-migration-');
      addTearDown(() => root.delete(recursive: true));
      const migrations = [
        migrateJobs,
        migrateMediaIdentity,
        migrateDanmaku,
        migrateSettings
      ];
      if (oldVersion > 0 && oldVersion < 5) {
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
      if (oldVersion == 5) {
        await db.close();
        db = await openNextDatabase(root, factory: databaseFactoryFfi);
      }
      addTearDown(() => db.close());
      expect(await db.getVersion(), 5);
      for (final table in [
        'jobs',
        'media_entities',
        'danmaku_bindings',
        'settings_changes',
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
}
