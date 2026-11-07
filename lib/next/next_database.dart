import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_library.dart';
import 'danmaku/migration.dart';
import 'danmaku/files.dart';
import 'media/media_migration.dart';
import 'media/external_sources_migration.dart';
import 'media/primitives_migration.dart';
import 'media/metadata_edit_migration.dart';
import 'media/classic_match_migration.dart';
import 'tasks/job_migration.dart';
import 'tasks/job_recent_migration.dart';
import 'settings/migration.dart';
import 'state/change_history.dart';
import 'followups/migration.dart';
import 'ui_data/migration.dart';
import 'ui_data/library_index.dart';
import 'chat/session_store.dart';
import 'media/file_identity_merge.dart';
import 'media/work_merge_migration.dart';
import 'media/presentation_store.dart';
import 'subtitles/migration.dart';
import 'player/skip/migration.dart';
import 'db/migration.dart';
import 'db/harmony_migration.dart';
import 'db/epochs.dart';
import 'state/activity_invocations.dart';

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
  migrateDanmakuFiles,
  migrateSubtitles,
  migrateLibraryIndex,
  migrateDbCommits,
  migrateFollowupLookups,
  migrateActivityInvocations,
  migrateChangeEpochs,
  migrateSkipSegments,
  migrateJobRecentIndex,
  migrateDbOperations,
  migrateWorkMerges,
  migrateMediaPresentation,
  migrateExternalSources,
];

Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
  for (var version = oldVersion; version < newVersion; version++) {
    await _migrations[version](db);
  }
}

final DatabaseFactory _customSqliteFactory =
    createDatabaseFactoryFfi(ffiInit: ensureSqliteLibrary);

Future<Database> openNextDatabase(Directory root,
    {DatabaseFactory? factory}) async {
  await root.create(recursive: true);
  final databasePath = '${root.path}/next.db';
  if (factory == null) {
    if (Platform.operatingSystem == 'ohos' &&
        !await File(databasePath).exists()) {
      final legacyDirectory = await databaseFactory.getDatabasesPath();
      await migrateHarmonyNextDatabase(
          databasePath: databasePath,
          legacyPath: harmonyLegacyDatabasePath(databasePath, legacyDirectory),
          factory: _customSqliteFactory);
    }
    if (Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS ||
        Platform.operatingSystem == 'ohos') {
      sqfliteFfiInit();
      // Each factory isolate must register the Linux runtime library name or
      // the bundled HarmonyOS library before sqlite3 first opens a connection.
      factory = Platform.isLinux || Platform.operatingSystem == 'ohos'
          ? _customSqliteFactory
          : databaseFactoryFfi;
    } else {
      factory = databaseFactory;
    }
  }
  final db = await factory.openDatabase(databasePath,
      options: OpenDatabaseOptions(
        version: _migrations.length,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          // Other processes read this file too (a shell, a backup, Spotlight).
          // In WAL a reader never makes a commit fail, and a busy moment is
          // waited out: a failed COMMIT left the connection inside its
          // transaction and every later write locked out (E2E-35).
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.rawQuery('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ));
  try {
    await finishExternalSourcesMigration(root, db);
    final files = DanmakuFiles(db);
    await files.migrate();
    return db;
  } catch (_) {
    await db.close();
    rethrow;
  }
}
