import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateClassicMatches(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS media_classic_observations (
    id TEXT PRIMARY KEY, location_id TEXT NOT NULL REFERENCES media_locations(id),
    fingerprint TEXT NOT NULL, payload TEXT NOT NULL, binding_id TEXT REFERENCES media_bindings(id),
    observed_at TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS media_classic_current (
    location_id TEXT PRIMARY KEY REFERENCES media_locations(id),
    observation_id TEXT NOT NULL REFERENCES media_classic_observations(id))''');
}
