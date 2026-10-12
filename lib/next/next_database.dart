import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'danmaku/migration.dart';
import 'media/media_migration.dart';
import 'media/primitives_migration.dart';
import 'media/metadata_edit_migration.dart';
import 'media/classic_match_migration.dart';
import 'tasks/job_migration.dart';
import 'settings/migration.dart';
import 'state/change_history.dart';
import 'followups/migration.dart';
import 'ui_data/migration.dart';
import 'chat/session_store.dart';
import 'media/file_identity_merge.dart';
import 'subtitles/migration.dart';

// Each position is a released database version. Append new domain migrations.
const _migrations = [
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
  migrateSessions,
  migrateFileAliases,
  migrateDanmakuSidecars,
  migrateSubtitles,
];

Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
  for (var version = oldVersion; version < newVersion; version++) {
    await _migrations[version](db);
  }
}

Future<Database> openNextDatabase(Directory root,
    {DatabaseFactory? factory}) async {
  await root.create(recursive: true);
  if (factory == null) {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = databaseFactory;
    }
  }
  return factory.openDatabase('${root.path}/next.db',
      options: OpenDatabaseOptions(
        version: _migrations.length,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ));
}
