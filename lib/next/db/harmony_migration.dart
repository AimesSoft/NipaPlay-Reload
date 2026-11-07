import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The old OHOS sqflite plugin strips the first six slash-separated path
/// components and places that suffix under Context.databaseDir/rdb instead
/// of opening the requested absolute path (DB_PATH_PARSING_BEGIN_INDEX=6).
String harmonyLegacyDatabasePath(String requestedPath, String databasesPath) =>
    '$databasesPath/${requestedPath.split('/').skip(6).join('/')}';

/// Take a consistent snapshot, including committed WAL pages, before moving
/// Next to its requested path. Keep the original RDB database for recovery.
/// Publishing with rename makes a failed/interrupted copy retryable.
Future<void> migrateHarmonyNextDatabase({
  required String databasePath,
  required String legacyPath,
  required DatabaseFactory factory,
}) async {
  if (databasePath == legacyPath ||
      await File(databasePath).exists() ||
      !await File(legacyPath).exists()) {
    return;
  }
  final pending = File('$databasePath.migrating');
  if (await pending.exists()) await pending.delete();
  final legacy = await factory.openDatabase(legacyPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
  try {
    await legacy.execute('VACUUM INTO ?', [pending.path]);
  } finally {
    await legacy.close();
  }
  await pending.rename(databasePath);
}
