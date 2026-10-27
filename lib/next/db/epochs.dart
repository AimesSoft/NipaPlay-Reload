import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tells whether what the library and the interface are made from has
/// changed, by one integer instead of by reading it all.
///
/// `change_epochs` holds a counter named `catalogue` (no row until the first write). Triggers on every
/// table in [catalogueTables] add one to it for each row inserted, updated
/// or deleted, whoever writes the row and however (a capability, the
/// scanner, `db.write`, another connection). A write that rolls back takes
/// its count with it. A reader remembers the counter it built from and
/// builds again when it has moved; nothing else moves it.
///
/// Every table of the schema is in exactly one of the two lists below; a
/// test fails for a table that is in neither, so a new table has to say
/// whether the library is built from it.
const catalogueTables = [
  // The library: works, releases, episodes, files and what they are known as.
  'media_entities',
  'media_locations',
  'media_file_episodes',
  'media_file_aliases',
  'media_entity_aliases',
  'media_external_objects',
  'media_bindings',
  'media_snapshots',
  'media_overrides',
  // Tracks of danmaku and subtitles shown on an episode.
  'danmaku_bindings',
  'danmaku_cache_chunks',
  'file_subtitles',
  // What the interface lays out and caches (artwork, heat, layouts, sources),
  // except the library's own output (`mesh:` rows).
  'ui_shelves',
  'ui_presentations',
  'ui_cache',
];

/// Tables the library and the interface are not built from, and why.
const notCatalogueTables = [
  // Tasks, followups and hooks: their own changes are pushed (the task
  // engine's stream) or only read on demand.
  'jobs',
  'job_events',
  'task_origins',
  'followups',
  'followup_events',
  'followup_objects',
  'followup_hook_events',
  // Audit and history, read on demand.
  'activity_invocations',
  'invocation_origins',
  'activity_backfill',
  'harness_sessions',
  'harness_discoveries',
  'body_changes',
  'db_commits',
  'db_operations',
  'settings_changes',
  'media_metadata_edits',
  'media_evidence',
  'danmaku_binding_events',
  'media_binding_operations',
  'media_work_merges',
  // Bookkeeping of how Classic and the scanner were last read.
  'media_classic_observations',
  'media_classic_current',
  'media_legacy_history',
  'media_projection_outbox',
  'media_scan_items',
  'danmaku_alignment_candidates',
  'danmaku_storage_state',
  // Read when a file opens, not part of the library's layout.
  'file_skip_segments',
  // Derived from the catalogue; writing it is what building does.
  'next_library_index',
  // The counter itself, and SQLite's own.
  'change_epochs',
  'sqlite_sequence',
];

Future<void> migrateChangeEpochs(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS change_epochs (
    name TEXT PRIMARY KEY, n INTEGER NOT NULL)''');
  for (final table in catalogueTables) {
    // Later migrations create their tables and install their epoch triggers.
    // This migration also runs while upgrading databases predating those tables.
    if ((await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [table])).isEmpty) continue;
    // Rows of the library's own output are not a change of what it is made of.
    final own = table == 'ui_cache';
    String when(String row) => own ? "WHEN $row.id NOT LIKE 'mesh:%' " : '';
    for (final (event, row) in [
      ('INSERT', 'NEW'),
      ('UPDATE', 'NEW'),
      ('DELETE', 'OLD'),
    ]) {
      await db.execute(
          'CREATE TRIGGER IF NOT EXISTS ${table}_epoch_${event.toLowerCase()} '
          'AFTER $event ON $table ${when(row)}BEGIN '
          "INSERT INTO change_epochs VALUES ('catalogue', 1) "
          "ON CONFLICT(name) DO UPDATE SET n = n + 1; END");
    }
  }
}
