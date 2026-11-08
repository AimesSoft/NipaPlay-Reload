import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../db/epochs.dart';

Future<void> migrateSubscriptions(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE subscriptions (
    id TEXT PRIMARY KEY, title TEXT NOT NULL,
    kind TEXT NOT NULL CHECK(kind IN ('series','movie')), work_id TEXT,
    state TEXT NOT NULL CHECK(state IN ('active','paused','ended')),
    note TEXT NOT NULL, program TEXT NOT NULL, facts TEXT NOT NULL,
    created_by TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    latest_downloads TEXT NOT NULL DEFAULT '[]')''');
  await db.execute('''CREATE TABLE subscription_reports (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    subscription_id TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    report_id TEXT NOT NULL, checked_at TEXT NOT NULL, payload TEXT NOT NULL,
    UNIQUE(subscription_id, report_id))''');
  await db.execute(
      'CREATE INDEX subscription_reports_recent ON subscription_reports(subscription_id, sequence DESC)');
  // Names and authorization only. Values belong exclusively to CredentialVault.
  await db.execute('''CREATE TABLE harness_secret_names (
    name TEXT PRIMARY KEY, user_authorization TEXT NOT NULL, updated_at TEXT NOT NULL)''');
  await migrateChangeEpochs(db);
}
