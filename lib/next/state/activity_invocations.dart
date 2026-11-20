import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../capabilities/local_operation_titles.dart';
import '../platform/report_error.dart';

/// Whether a journalled invocation is an entry of 动态 (conflicts always are).
///
/// Of the interface's reads only `ui.capture` is one: the others
/// (`ui.inbox.list`, `ui.library.page`…) are what the viewer polls to draw
/// itself, and keeping each of them grew next.db by hundreds of megabytes
/// (#1114). [effect] is null where it is not known (a stored row, which was
/// only stored because it is shown).
bool activityRecordsInvocation(String action,
        {required bool conflict, Effect? effect}) =>
    conflict ||
    action.startsWith('media.sources.') ||
    (action.startsWith('ui.') &&
        (effect != Effect.read || action == 'ui.capture')) ||
    action.startsWith('discover.') ||
    action.startsWith('accounts.') ||
    localOperationTitles.containsKey(action);

/// The `ui.*` reads earlier versions kept in `activity_invocations`; none of
/// them is shown, so [purgeUnshownActivityInvocations] removes their rows.
const unshownInterfaceReads = [
  'ui.inbox.list',
  'ui.library.sources',
  'ui.library.page',
  'ui.library.items',
  'ui.detail.layout',
];

/// Whether a read's journal line keeps its result: those 动态 shows.
bool activityKeepsResult(InvocationRecord record) =>
    activityRecordsInvocation(record.actionId,
        conflict: record.failureCode == FailureCode.conflict,
        effect: record.effect);

/// journal.jsonl as Next keeps it: every invocation; reads without their
/// result unless 动态 shows them; rotated into archives past 32 MiB.
JsonlJournal nextJournal(File file) => JsonlJournal(file,
    effects: Effect.values.toSet(),
    keepsResult: activityKeepsResult,
    rotateBytes: nextJournalRotateBytes);

const nextJournalRotateBytes = 32 << 20;

/// Retention ceiling for `activity_invocations` (#1114): old rows are pruned
/// so the table cannot grow without bound over months of use.
const activityInvocationsMaxRows = 10000;

/// Maximum serialized size of one `activity_invocations.result` payload.
const activityResultMaxBytes = 64 << 10;

Future<void> migrateActivityInvocations(DatabaseExecutor db) async {
  // The invocations 动态 shows, projected to what it reads of them.
  await db.execute('''CREATE TABLE IF NOT EXISTS activity_invocations (
    invocation_id TEXT PRIMARY KEY, action_id TEXT NOT NULL, origin TEXT,
    status TEXT, failure_code TEXT, started_at TEXT NOT NULL,
    elapsed_ms INTEGER NOT NULL, input TEXT NOT NULL, result TEXT)''');
  // Who made each write, for domain rows that name only their invocation.
  await db.execute('''CREATE TABLE IF NOT EXISTS invocation_origins (
    invocation_id TEXT PRIMARY KEY, origin TEXT NOT NULL)''');
  // One row once the journal written before these tables has been read
  // into them.
  await db
      .execute('CREATE TABLE IF NOT EXISTS activity_backfill (done INTEGER)');
}

/// Removes the rows of [unshownInterfaceReads] that earlier versions kept
/// (#1114: 171,572 `ui.inbox.list` rows, 636 MB, on one library of 29
/// works). The space is given back once the database is open.
Future<void> purgeUnshownActivityInvocations(DatabaseExecutor db) async {
  await db.delete('activity_invocations',
      where: 'action_id IN '
          '(${List.filled(unshownInterfaceReads.length, '?').join(',')})',
      whereArgs: unshownInterfaceReads);
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activity_invocations_started_at '
      'ON activity_invocations(started_at)');
}

/// Keeps at most [maxRows] newest rows in `activity_invocations` (#1114).
/// Returns the number of rows deleted.
Future<int> pruneActivityInvocations(DatabaseExecutor db,
    {int maxRows = activityInvocationsMaxRows}) async {
  if (maxRows <= 0) return db.delete('activity_invocations');
  final count = (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM activity_invocations'))
          .single['n'] as int? ??
      0;
  if (count <= maxRows) return 0;
  return db.rawDelete(
      'DELETE FROM activity_invocations WHERE rowid IN ('
      'SELECT rowid FROM activity_invocations '
      'ORDER BY started_at DESC, rowid DESC LIMIT -1 OFFSET ?)',
      [maxRows]);
}

const _inputKeys = ['provider', 'sourceId', 'entityId', 'next', 'entries'];
const _entryKeys = [
  'entityId',
  'kind',
  'ref',
  'workRef',
  'releaseRef',
  'episodeRefs',
  'reason'
];

/// The input fields 动态 reads; anything else is left out.
Object? _projectInput(Object? input) => input is! Map
    ? input
    : {
        for (final key in _inputKeys)
          if (input.containsKey(key))
            key: key == 'entries' && input[key] is List
                ? [
                    for (final entry in input[key] as List)
                      entry is Map
                          ? {
                              for (final field in _entryKeys)
                                if (entry.containsKey(field))
                                  field: entry[field]
                            }
                          : entry
                  ]
                : input[key],
      };

const _resultSummaryKeys = [
  'path',
  'closed',
  'opened',
  'actual',
  'refreshed',
  'changed',
  'status',
  'ok',
  'count',
  'total',
];

String? _encodeBoundedResult(Object? result) {
  if (result == null) return null;
  final encoded = jsonEncode(result);
  if (encoded.length <= activityResultMaxBytes) return encoded;
  final compact = <String, Object?>{
    if (result is Map)
      for (final key in _resultSummaryKeys)
        if (result.containsKey(key)) key: result[key],
    '_truncated': true,
    '_originalBytes': encoded.length,
  };
  final summary = jsonEncode(compact);
  if (summary.length <= activityResultMaxBytes) return summary;
  return jsonEncode({'_truncated': true, '_originalBytes': encoded.length});
}

/// The `activity_invocations` row of a journalled invocation [record]
/// (shaped as a journal.jsonl line), or null when 动态 does not show it.
Map<String, Object?>? activityInvocationRow(Map record) {
  final id = record['invocationId'], action = record['actionId'];
  final startedAt = record['startedAt'], elapsed = record['elapsedMs'];
  if (id is! String ||
      action is! String ||
      startedAt is! String ||
      DateTime.tryParse(startedAt) == null ||
      elapsed is! int) {
    return null;
  }
  if (!activityRecordsInvocation(action,
      conflict: record['failureCode'] == 'conflict',
      effect: Effect.values.asNameMap()[record['effect']])) {
    return null;
  }
  String? text(Object? value) => value is String ? value : null;
  final result = record['result'];
  return {
    'invocation_id': id,
    'action_id': action,
    'origin': text(record['origin']),
    'status': text(record['status']),
    'failure_code': text(record['failureCode']),
    'started_at': startedAt,
    'elapsed_ms': elapsed,
    'input': jsonEncode(_projectInput(record['input'])),
    'result': _encodeBoundedResult(result),
  };
}

/// An `activity_invocations` row as the journal record 动态 composes from.
Map<String, Object?> activityInvocationRecord(Map row) => {
      'invocationId': row['invocation_id'],
      'actionId': row['action_id'],
      'origin': row['origin'],
      'status': row['status'],
      'failureCode': row['failure_code'],
      'startedAt': row['started_at'],
      'elapsedMs': row['elapsed_ms'],
      'input': jsonDecode(row['input'] as String),
      'result':
          row['result'] == null ? null : jsonDecode(row['result'] as String),
    };

/// What 动态 needs of invocations, kept in next.db as they happen: the
/// invocations it shows ([activityRecordsInvocation]), projected to the
/// fields it reads, and the origin of every write. 动态 never reads
/// journal.jsonl; the journal written before this store existed is read
/// into it once, on a background isolate.
final class ActivityInvocations implements InvocationObserver {
  ActivityInvocations(this.database, this.journal,
      {this.changed, this.maxRows = activityInvocationsMaxRows});

  final Database database;

  /// journal.jsonl, for the one-time backfill and the absence warning.
  final File journal;

  /// Maximum rows kept in `activity_invocations`.
  final int maxRows;

  /// Told after an invocation 动态 shows has been stored.
  void Function()? changed;

  Future<void> _writes = Future.value();
  Future<void>? _backfilling;
  bool _backfilled = false, _closed = false;
  int _storedSincePrune = 0;

  int get _pruneCadence =>
      maxRows <= 0 ? 1 : (maxRows ~/ 4).clamp(1, 200);

  /// Shown invocations are projected on a background isolate. A write
  /// returns once its rows are stored; a read does not wait for them, and
  /// [settled] does before 动态 is read.
  @override
  Future<void>? onInvocation(InvocationRecord record) {
    final shown = activityKeepsResult(record);
    final write = record.effect != Effect.read;
    if (_closed || (!shown && !write)) return null;
    final row = shown ? _rowOffMain(record) : null;
    final previous = _writes;
    final stored = _writes = () async {
      try {
        await previous;
      } catch (_) {
        // That invocation's own failure, already reported.
      }
      if (write) {
        await database.insert('invocation_origins',
            {'invocation_id': record.invocationId, 'origin': record.origin},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (await row case final values?) {
        await database.insert('activity_invocations', values,
            conflictAlgorithm: ConflictAlgorithm.replace);
        _storedSincePrune++;
        if (_storedSincePrune >= _pruneCadence) {
          _storedSincePrune = 0;
          await pruneActivityInvocations(database, maxRows: maxRows);
        }
        changed?.call();
      }
    }();
    unawaited(
        stored.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      if (database.isOpen) {
        reportNextError(error, stack, 'Next activity invocations');
      }
    }));
    return write ? stored : null;
  }

  /// Completes once the old journal has been read in (when it can be) and
  /// every invocation observed so far is stored.
  Future<void> settled() async {
    await backfill();
    try {
      await _writes;
    } catch (_) {
      // Reported where it failed; 动态 shows what was stored.
    }
  }

  /// Reads the journal (and its archives) written before these tables
  /// existed into them, once: in the background, without holding up
  /// startup; rows recorded since are kept. Until a journal exists there is
  /// nothing to read and nothing is written.
  Future<void> backfill() {
    if (_backfilled || _closed) return Future.value();
    return _backfilling ??= _backfill().whenComplete(() => _backfilling = null);
  }

  Future<void> _backfill() async {
    try {
      if ((await database.query('activity_backfill', limit: 1)).isNotEmpty) {
        _backfilled = true;
        return;
      }
      final segments = [
        for (final file in await JournalAppender.segments(journal)) file.path
      ];
      if (segments.isEmpty) return;
      final statements = await _readJournalOffMain(segments);
      for (final (sql, args) in statements) {
        if (_closed) return;
        await database.rawInsert(sql, args);
      }
      await pruneActivityInvocations(database, maxRows: maxRows);
      await database.insert('activity_backfill', {'done': 1});
      _backfilled = true;
    } catch (error, stack) {
      // Tried again at the next start.
      if (!_closed && database.isOpen) {
        reportNextError(error, stack, 'Next activity backfill');
      }
    }
  }

  /// Stops a backfill between batches and waits for stored rows.
  Future<void> close() async {
    _closed = true;
    await _backfilling;
    try {
      await _writes;
    } catch (_) {}
  }
}

// Top-level, so the closures sent to the isolate carry nothing else.
Future<Map<String, Object?>?> _rowOffMain(InvocationRecord record) =>
    Isolate.run(() => activityInvocationRow(record.toJson()));

Future<List<(String, List<Object?>)>> _readJournalOffMain(List<String> paths) =>
    Isolate.run(() => _readJournal(paths));

final _header = RegExp(
    r'^\{"invocationId":"((?:[^"\\]|\\.)*)","actionId":"((?:[^"\\]|\\.)*)",'
    r'"origin":"(?:[^"\\]|\\.)*","effect":"(read|write|destructive)"');

/// On a background isolate: the rows of every shown invocation and the
/// origin of every write in [paths], read in order (a later line with the
/// same invocation ID replaces an earlier one, as 动态 composed them) and
/// packed into bounded multi-row INSERT statements.
Future<List<(String, List<Object?>)>> _readJournal(List<String> paths) async {
  final shown = <String, Map<String, Object?>>{};
  final origins = <String, String>{};
  for (final path in paths) {
    final lines = File(path)
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isEmpty) continue;
      // A read 动态 does not show is passed over without decoding it (most
      // of an old journal is reads with large results).
      if (_header.matchAsPrefix(line) case final header?
          when header[3] == 'read' &&
              !activityRecordsInvocation(header[2]!,
                  conflict: false, effect: Effect.read) &&
              !line.contains('"failureCode":"conflict"')) {
        shown.remove(header[1]);
        continue;
      }
      final Object? record;
      try {
        record = jsonDecode(line);
      } on FormatException {
        // A line cut short (a crash, or a write still in progress).
        continue;
      }
      if (record is! Map) continue;
      final id = record['invocationId'];
      if (id is! String) continue;
      if ((record['effect'] == 'write' || record['effect'] == 'destructive') &&
          record['origin'] is String) {
        origins[id] = record['origin'] as String;
      }
      if (activityInvocationRow(record) case final row?) {
        shown[id] = row;
      } else {
        shown.remove(id);
      }
    }
  }
  final statements = <(String, List<Object?>)>[];
  final originEntries = origins.entries.toList();
  for (var start = 0; start < originEntries.length; start += 250) {
    final chunk = originEntries.sublist(
        start, (start + 250).clamp(0, originEntries.length));
    statements.add((
      'INSERT OR IGNORE INTO invocation_origins (invocation_id, origin) VALUES '
          '${List.filled(chunk.length, '(?,?)').join(',')}',
      [
        for (final entry in chunk) ...[entry.key, entry.value]
      ]
    ));
  }
  final rowList = shown.values.toList();
  var index = 0;
  while (index < rowList.length) {
    final args = <Object?>[];
    var count = 0, bytes = 0;
    while (index < rowList.length && count < 80 && bytes < 256 << 10) {
      final row = rowList[index++];
      count++;
      bytes += (row['input'] as String).length +
          ((row['result'] as String?)?.length ?? 0);
      args.addAll([
        row['invocation_id'],
        row['action_id'],
        row['origin'],
        row['status'],
        row['failure_code'],
        row['started_at'],
        row['elapsed_ms'],
        row['input'],
        row['result']
      ]);
    }
    statements.add((
      'INSERT OR IGNORE INTO activity_invocations '
          '(invocation_id, action_id, origin, status, failure_code, started_at, elapsed_ms, input, result) VALUES '
          '${List.filled(count, '(?,?,?,?,?,?,?,?,?)').join(',')}',
      args
    ));
  }
  return statements;
}
