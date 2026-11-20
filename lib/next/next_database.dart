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
import 'chat/handover.dart';
import 'media/file_identity_merge.dart';
import 'media/work_merge_migration.dart';
import 'media/presentation_store.dart';
import 'subtitles/migration.dart';
import 'player/skip/migration.dart';
import 'db/migration.dart';
import 'db/harmony_migration.dart';
import 'db/epochs.dart';
import 'db/notifications.dart';
import 'state/activity_invocations.dart';
import 'subscriptions/migration.dart';

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
  migrateSubscriptions,
  purgeUnshownActivityInvocations,
  migrateHandover,
];

/// Gives back the space a large deletion left as free pages (the rows
/// [purgeUnshownActivityInvocations] removed): VACUUM once at least a quarter
/// of the file, and 32 MiB, is free. Checked at every open, so a VACUUM cut
/// short is done again next time.
Future<void> _compact(Database db) async {
  Future<int> pragma(String name) async =>
      (await db.rawQuery('PRAGMA $name')).firstOrNull?.values.firstOrNull
          as int? ??
      0;
  final free = await pragma('freelist_count');
  if (free == 0) return;
  final pages = await pragma('page_count');
  if (free * await pragma('page_size') >= 32 << 20 && free * 4 >= pages) {
    await db.execute('VACUUM');
    // In WAL the rebuilt file is written to the log; the checkpoint is what
    // shortens next.db (and empties the log it grew).
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  }
}

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
  var observedPath = databasePath;
  final notifications = NotifyingDatabaseFactory(factory,
      () => CatalogueChanges.committed(observedPath));
  final db = await notifications.factory.openDatabase(databasePath,
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
    await pruneActivityInvocations(db);
    try {
      await _compact(db);
    } on DatabaseException catch (error) {
      // Reclaiming space is a courtesy: a disk too full for VACUUM's copy
      // must not keep the database from opening. Tried again next start.
      stderr.writeln('[NextDatabase] compaction skipped: $error');
    }
    observedPath = db.path;
    await notifications.observe(db);
    return db;
  } catch (_) {
    await db.close();
    rethrow;
  }
}
