import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The skip segments Nipa set for a file (`playback.set_skip_segment`). One
/// row per file and kind: setting again replaces, clearing deletes.
///
/// Keyed by the file, not the episode: a segment is a position in one
/// particular cut of the video, and two files of an episode need not share it.
Future<void> migrateSkipSegments(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS file_skip_segments (
    file_id TEXT NOT NULL REFERENCES media_entities(id),
    kind TEXT NOT NULL CHECK(kind IN ('opening','ending')),
    start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL CHECK(end_ms > start_ms),
    set_at TEXT NOT NULL, invocation_id TEXT,
    PRIMARY KEY(file_id, kind))''');
}
