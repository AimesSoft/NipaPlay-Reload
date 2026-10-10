import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateDanmaku(DatabaseExecutor db) async {
  for (final sql in _tables) {
    await db.execute(sql);
  }
}

Future<void> migrateDanmakuImports(DatabaseExecutor db) =>
    db.execute('ALTER TABLE danmaku_bindings ADD COLUMN provenance TEXT');

const _tables = [
  '''CREATE TABLE danmaku_bindings (
    id TEXT PRIMARY KEY, entity_id TEXT NOT NULL REFERENCES media_entities(id),
    entity_revision INTEGER NOT NULL, object_id TEXT NOT NULL REFERENCES media_external_objects(id),
    video TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('accepted','revoked')),
    enabled INTEGER NOT NULL, deduplicate INTEGER NOT NULL DEFAULT 1, offset_ms INTEGER NOT NULL, alignment TEXT NOT NULL,
    evidence TEXT NOT NULL, bound_by TEXT NOT NULL CHECK(bound_by IN ('user','agent','automatic')),
    invocation_id TEXT NOT NULL, revision INTEGER NOT NULL, cache_key TEXT,
    cache_revision INTEGER NOT NULL DEFAULT 0, cache_job_id TEXT,
    created_at TEXT NOT NULL)''',
  'CREATE INDEX danmaku_bindings_entity ON danmaku_bindings(entity_id,status)',
  '''CREATE TABLE danmaku_cache_chunks (
    cache_key TEXT NOT NULL, chunk_index INTEGER NOT NULL, start_ms INTEGER NOT NULL,
    end_ms INTEGER NOT NULL, payload TEXT NOT NULL, coverage TEXT NOT NULL,
    fetched_at TEXT NOT NULL, PRIMARY KEY(cache_key,chunk_index))''',
  '''CREATE TABLE danmaku_alignment_candidates (
    job_id TEXT PRIMARY KEY REFERENCES jobs(job_id), binding_id TEXT NOT NULL REFERENCES danmaku_bindings(id),
    binding_revision INTEGER NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL)''',
  '''CREATE TABLE danmaku_binding_events (
    id TEXT PRIMARY KEY, binding_id TEXT NOT NULL REFERENCES danmaku_bindings(id),
    revision INTEGER NOT NULL, invocation_id TEXT NOT NULL, payload TEXT NOT NULL,
    created_at TEXT NOT NULL)'''
];
