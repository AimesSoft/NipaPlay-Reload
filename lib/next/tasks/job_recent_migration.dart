import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Recent-job pages order by the snapshot's update time. Keeping that value in
/// an expression index avoids parsing every stored task snapshot whenever the
/// home page asks for its first page.
Future<void> migrateJobRecentIndex(DatabaseExecutor db) async {
  await db.execute(r"CREATE INDEX IF NOT EXISTS jobs_state_updated ON jobs("
      r"state, json_extract(snapshot, '$.updatedAt') DESC, job_id DESC)");
}
