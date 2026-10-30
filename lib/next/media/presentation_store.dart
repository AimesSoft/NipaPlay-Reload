import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'presentation.dart';

/// The rule every work of this device follows; null when none was set (or
/// the database predates the table).
Future<PresentationRule?> readGlobalPresentation(DatabaseExecutor db) async {
  try {
    final rows = await db.query('media_presentation',
        columns: ['payload'], where: "id='global'");
    return rows.isEmpty
        ? null
        : PresentationRule.tryParse(rows.single['payload']);
  } on DatabaseException {
    return null;
  }
}

/// The global rule with when and by whom it was set, for the agent.
Future<JsonMap?> readGlobalPresentationRow(DatabaseExecutor db) async {
  try {
    final rows = await db.query('media_presentation', where: "id='global'");
    if (rows.isEmpty) return null;
    final row = rows.single;
    return {
      'rule': PresentationRule.tryParse(row['payload'])?.toJson(),
      'updatedAt': row['updated_at'],
      'origin': row['origin'],
      'invocationId': row['invocation_id'],
    };
  } on DatabaseException {
    return null;
  }
}

Future<void> migrateMediaPresentation(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS media_presentation (
    id TEXT PRIMARY KEY CHECK(id = 'global'), payload TEXT NOT NULL,
    updated_at TEXT NOT NULL, origin TEXT NOT NULL, invocation_id TEXT NOT NULL)''');
  for (final (event, _) in const [
    ('INSERT', 'NEW'),
    ('UPDATE', 'NEW'),
    ('DELETE', 'OLD'),
  ]) {
    await db.execute(
        'CREATE TRIGGER IF NOT EXISTS media_presentation_epoch_${event.toLowerCase()} '
        'AFTER $event ON media_presentation BEGIN '
        "INSERT INTO change_epochs VALUES ('catalogue', 1) "
        'ON CONFLICT(name) DO UPDATE SET n = n + 1; END');
  }
}
