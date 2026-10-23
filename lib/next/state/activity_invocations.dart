import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../capabilities/local_operation_titles.dart';
import '../platform/report_error.dart';

/// Whether a journalled invocation is an entry of 动态 (conflicts always are).
bool activityRecordsInvocation(String action, {required bool conflict}) =>
    conflict ||
    action.startsWith('media.sources.') ||
    action.startsWith('ui.') ||
    action.startsWith('discover.') ||
    action.startsWith('accounts.') ||
    localOperationTitles.containsKey(action);

/// Whether a read's journal line keeps its result: those 动态 shows.
bool activityKeepsResult(InvocationRecord record) => activityRecordsInvocation(
    record.actionId,
    conflict: record.failureCode == FailureCode.conflict);

/// journal.jsonl as Next keeps it: every invocation; reads without their
/// result unless 动态 shows them; rotated into archives past 32 MiB.
JsonlJournal nextJournal(File file) => JsonlJournal(file,
    effects: Effect.values.toSet(),
    keepsResult: activityKeepsResult,
    rotateBytes: nextJournalRotateBytes);

const nextJournalRotateBytes = 32 << 20;

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
  await db.execute('CREATE TABLE IF NOT EXISTS activity_backfill (done INTEGER)');
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
      conflict: record['failureCode'] == 'conflict')) {
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
    'result': result == null ? null : jsonEncode(result),
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
      'result': row['result'] == null ? null : jsonDecode(row['result'] as String),
    };

/// What 动态 needs of invocations, kept in next.db as they happen: the
/// invocations it shows ([activityRecordsInvocation]), projected to the
/// fields it reads, and the origin of every write. 动态 never reads
/// journal.jsonl; the journal written before this store existed is read
/// into it once, on a background isolate.
final class ActivityInvocations implements InvocationObserver {
  ActivityInvocations(this.database, this.journal, {this.changed});

  final Database database;

  /// journal.jsonl, for the one-time backfill and the absence warning.
  final File journal;

  /// Told after an invocation 动态 shows has been stored.
  void Function()? changed;

  Future<void> _writes = Future.value();
  Future<void>? _backfilling;
  bool _backfilled = false, _closed = false;

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
        changed?.call();
      }
    }();
    unawaited(stored.then<void>((_) {}, onError: (Object error, StackTrace stack) {
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
      final (rows, origins) = await _readJournalOffMain(segments);
      // Sent to the database in small batches, so no single message is large.
      Future<bool> insert(String table, List<Map<String, Object?>> values,
          int Function(Map<String, Object?> row) size) async {
        var batch = database.batch(), bytes = 0, count = 0;
        for (final row in values) {
          batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.ignore);
          bytes += size(row);
          if (++count >= 500 || bytes >= 256 << 10) {
            if (_closed) return false;
            await batch.commit(noResult: true);
            batch = database.batch();
            bytes = count = 0;
          }
        }
        if (_closed) return false;
        if (count > 0) await batch.commit(noResult: true);
        return true;
      }

      if (!await insert('invocation_origins', origins, (_) => 64)) return;
      if (!await insert(
          'activity_invocations',
          rows,
          (row) =>
              (row['input'] as String).length +
              ((row['result'] as String?)?.length ?? 0))) {
        return;
      }
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

Future<(List<Map<String, Object?>>, List<Map<String, Object?>>)>
    _readJournalOffMain(List<String> paths) =>
        Isolate.run(() => _readJournal(paths));

final _header = RegExp(
    r'^\{"invocationId":"((?:[^"\\]|\\.)*)","actionId":"((?:[^"\\]|\\.)*)",'
    r'"origin":"(?:[^"\\]|\\.)*","effect":"(read|write|destructive)"');

/// On a background isolate: the rows of every shown invocation and the
/// origin of every write in [paths], read in order (a later line with the
/// same invocation ID replaces an earlier one, as 动态 composed them).
Future<(List<Map<String, Object?>>, List<Map<String, Object?>>)> _readJournal(
    List<String> paths) async {
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
              !activityRecordsInvocation(header[2]!, conflict: false) &&
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
  return (
    shown.values.toList(),
    [
      for (final MapEntry(:key, :value) in origins.entries)
        {'invocation_id': key, 'origin': value}
    ]
  );
}
