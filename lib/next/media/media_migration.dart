import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateMediaIdentity(DatabaseExecutor db) async {
  for (final sql in _tables) {
    await db.execute(sql);
  }
}

const _tables = [
  '''CREATE TABLE media_entities (
    id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('work','release','episode','file')),
    parent_id TEXT REFERENCES media_entities(id), revision INTEGER NOT NULL DEFAULT 0,
    attributes TEXT NOT NULL)''',
  '''CREATE TABLE media_locations (
    id TEXT PRIMARY KEY, file_id TEXT NOT NULL REFERENCES media_entities(id),
    source TEXT NOT NULL, owner_device_id TEXT NOT NULL, locator TEXT NOT NULL,
    available INTEGER NOT NULL, UNIQUE(source, owner_device_id, locator))''',
  '''CREATE TABLE media_file_episodes (
    file_id TEXT NOT NULL REFERENCES media_entities(id), episode_id TEXT NOT NULL REFERENCES media_entities(id),
    relation TEXT NOT NULL, ordinal INTEGER NOT NULL, start_ms INTEGER, end_ms INTEGER,
    PRIMARY KEY(file_id, episode_id))''',
  '''CREATE TABLE media_external_objects (
    id TEXT PRIMARY KEY, provider TEXT NOT NULL, object_type TEXT NOT NULL,
    external_id TEXT NOT NULL, scope TEXT NOT NULL,
    UNIQUE(provider, object_type, external_id, scope))''',
  '''CREATE TABLE media_bindings (
    id TEXT PRIMARY KEY, entity_id TEXT NOT NULL REFERENCES media_entities(id),
    object_id TEXT NOT NULL REFERENCES media_external_objects(id), relation TEXT NOT NULL,
    scope TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('proposed','accepted','rejected','revoked')),
    source TEXT NOT NULL, bound_by TEXT CHECK(bound_by IN ('automatic','agent','user')),
    revision INTEGER NOT NULL, supersedes TEXT REFERENCES media_bindings(id),
    invocation_id TEXT, job_id TEXT, created_at TEXT NOT NULL)''',
  '''CREATE INDEX media_bindings_entity ON media_bindings(entity_id, status)''',
  '''CREATE TABLE media_evidence (
    id TEXT PRIMARY KEY, binding_id TEXT REFERENCES media_bindings(id),
    job_id TEXT, source TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL)''',
  '''CREATE TABLE media_snapshots (
    id TEXT PRIMARY KEY, object_id TEXT NOT NULL REFERENCES media_external_objects(id),
    language TEXT NOT NULL, fetched_at TEXT NOT NULL, fields TEXT NOT NULL)''',
  '''CREATE TABLE media_overrides (
    entity_id TEXT NOT NULL REFERENCES media_entities(id), field TEXT NOT NULL,
    value TEXT NOT NULL, invocation_id TEXT NOT NULL, PRIMARY KEY(entity_id, field))''',
  '''CREATE TABLE media_candidates (
    id TEXT PRIMARY KEY, job_id TEXT NOT NULL, file_id TEXT NOT NULL REFERENCES media_entities(id),
    file_revision INTEGER NOT NULL, binding_revision INTEGER NOT NULL,
    payload TEXT NOT NULL, source TEXT NOT NULL, state TEXT NOT NULL,
    UNIQUE(job_id, id))''',
  '''CREATE TABLE media_identifications (
    job_id TEXT PRIMARY KEY, file_id TEXT NOT NULL REFERENCES media_entities(id),
    file_revision INTEGER NOT NULL, binding_revision INTEGER NOT NULL,
    state TEXT NOT NULL, context TEXT NOT NULL)''',
  '''CREATE TABLE media_projection_outbox (
    id TEXT PRIMARY KEY, file_id TEXT NOT NULL REFERENCES media_entities(id),
    file_revision INTEGER NOT NULL, binding_revision INTEGER NOT NULL,
    payload TEXT NOT NULL, state TEXT NOT NULL)''',
  '''CREATE TABLE media_legacy_history (
    location_id TEXT PRIMARY KEY REFERENCES media_locations(id), fingerprint TEXT NOT NULL,
    payload TEXT NOT NULL)''',
  '''CREATE TABLE media_scan_items (
    job_id TEXT NOT NULL, file_id TEXT NOT NULL REFERENCES media_entities(id),
    file_revision INTEGER NOT NULL, identification_job_id TEXT,
    PRIMARY KEY(job_id, file_id))''',
];
