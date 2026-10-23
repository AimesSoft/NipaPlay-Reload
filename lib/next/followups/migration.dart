import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateFollowups(Database db) async {
  await db.execute('''CREATE TABLE followups (
    id TEXT PRIMARY KEY,
    state TEXT NOT NULL CHECK(state IN ('waiting','ready','dispatching','started','completed','execution_failed','cancelled')),
    snapshot TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE followup_events (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    followup_id TEXT NOT NULL REFERENCES followups(id),
    at TEXT NOT NULL,
    type TEXT NOT NULL,
    origin TEXT NOT NULL,
    invocation_id TEXT,
    facts TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE followup_hook_events (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    event TEXT NOT NULL,
    object_id TEXT NOT NULL,
    payload TEXT NOT NULL
  )''');
}

/// What a sweep finds followups by, so that it reads the rows still in play
/// and the few a task or an occurrence names, never every row it ever had.
///
/// `followup_objects` lists what each automatic return has reported: a
/// download return's objects (files, stalls, the task's end), a library
/// batch's paths and file ids, and the library file ids in the facts of
/// either. Triggers write it with every snapshot, whoever writes the row;
/// the lists in a snapshot only grow, so neither does it shrink.
Future<void> migrateFollowupLookups(DatabaseExecutor db) async {
  for (final sql in [
    'CREATE INDEX followups_state ON followups(state)',
    "CREATE INDEX followups_job ON followups(json_extract(snapshot, '\$.condition.jobId'))",
    "CREATE INDEX followups_download_job ON followups(json_extract(snapshot, '\$.condition.downloadJobId'))",
    "CREATE INDEX followups_trigger_object ON followups(json_extract(snapshot, '\$.trigger.objectId'))",
    'CREATE INDEX followup_hook_events_object ON followup_hook_events(event, object_id)',
    'CREATE INDEX followup_hook_events_cursor ON followup_hook_events(event, sequence)',
    '''CREATE TABLE followup_objects (
      kind TEXT NOT NULL CHECK(kind IN ('download','library','fileId')),
      object TEXT NOT NULL,
      followup_id TEXT NOT NULL REFERENCES followups(id),
      PRIMARY KEY (kind, object, followup_id)
    )''',
    for (final event in ['INSERT', 'UPDATE OF snapshot'])
      'CREATE TRIGGER followup_objects_${event == 'INSERT' ? 'inserted' : 'updated'} '
          'AFTER $event ON followups BEGIN '
          '${_objects('', 'NEW.snapshot', 'NEW.id').map((s) => '$s;').join(' ')} END',
    ..._objects('followups f, ', 'f.snapshot', 'f.id'),
  ]) {
    await db.execute(sql);
  }
}

/// The statements that record a row's reported objects; [from] names the
/// rows when they are not the trigger's own.
List<String> _objects(String from, String snapshot, String id) {
  String insert(String kind, String value, String list, String automatic,
          String where) =>
      "INSERT OR IGNORE INTO followup_objects (kind, object, followup_id) "
      "SELECT '$kind', $value, $id FROM ${from}json_each($snapshot, '$list') o "
      "WHERE json_extract($snapshot, '\$.automatic') = '$automatic' AND $where";
  return [
    insert('download', 'o.value', r'$.downloadObjects', 'download',
        "o.type = 'text'"),
    insert('library', 'o.value', r'$.libraryObjects', 'library',
        "o.type = 'text'"),
    insert('fileId', r"json_extract(o.value, '$.data.file.media.fileId')",
        r'$.trigger.facts', 'download',
        r"o.type = 'object' AND json_type(o.value, '$.data.file.media.fileId') = 'text'"),
    insert('fileId', r"json_extract(o.value, '$.data.fileId')",
        r'$.trigger.facts', 'library',
        r"o.type = 'object' AND json_type(o.value, '$.data.fileId') = 'text'"),
  ];
}
