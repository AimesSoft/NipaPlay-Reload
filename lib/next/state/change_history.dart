import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../settings/registry.dart';
import 'query.dart';

Future<void> migrateChangeHistory(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE body_changes (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT NOT NULL,
    type TEXT NOT NULL, subject_id TEXT NOT NULL, actor TEXT NOT NULL,
    origin TEXT NOT NULL, invocation_id TEXT, facts TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE task_origins (
    job_id TEXT PRIMARY KEY REFERENCES jobs(job_id), origin TEXT NOT NULL,
    invocation_id TEXT)''');
  await db.execute('ALTER TABLE job_events ADD COLUMN origin TEXT');
  await db.execute('ALTER TABLE job_events ADD COLUMN invocation_id TEXT');
}

/// Receives public facts only, after Classic has persisted its own state.
abstract final class BodyChanges {
  static ChangeHistory? _attached;
  static final _latest = <String, List<JsonMap>>{};
  static ChangeHistory? get attached => _attached;
  static set attached(ChangeHistory? history) {
    _attached = history;
    if (history != null) {
      for (final entry in _latest.entries) {
        history.seed(entry.key, entry.value);
      }
    }
  }

  static final invocationKey = Object();
  static List<JsonMap> _publicRows(List<JsonMap> rows) => [
        for (final row in rows)
          publicValue(SecretRedactor.json(row),
              const ObjectSchema({}, additionalProperties: true)) as JsonMap
      ];
  static Invocation? get invocation =>
      Zone.current[invocationKey] as Invocation? ??
      Zone.current[SettingsAccess.invocationKey] as Invocation?;
  static void seed(String collection, List<JsonMap> rows) {
    final public = _publicRows(rows);
    _latest[collection] = public;
    attached?.seed(collection, public);
  }

  static Future<T> fromUser<T>(Future<T> Function() operation) =>
      runZoned(operation,
          zoneValues: {invocationKey: invocation ?? Invocation(origin: 'gui')});
  static void observe(String collection, List<JsonMap> rows) {
    final public = _publicRows(rows);
    _latest[collection] = public;
    attached?.observe(collection, public, invocation);
  }
}

final class ChangeHistory {
  ChangeHistory(this.database);
  final Database database;
  final _previous = <String, Map<String, JsonMap>>{};
  Future<void> _writes = Future.value();

  void seed(String collection, List<JsonMap> rows) {
    _previous[collection] = {for (final row in rows) row['id'] as String: row};
  }

  void observe(String collection, List<JsonMap> rows, Invocation? invocation) {
    final next = {for (final row in rows) row['id'] as String: row};
    final before = _previous[collection];
    _previous[collection] = next;
    if (before == null) return;
    final at = DateTime.now().toUtc().toIso8601String();
    for (final id in {...before.keys, ...next.keys}) {
      final old = before[id], value = next[id];
      if (jsonEncode(old) == jsonEncode(value)) continue;
      final operation = old == null
          ? 'added'
          : value == null
              ? 'removed'
              : collection.split(':').first == 'account' &&
                      old['loggedIn'] != value['loggedIn']
                  ? value['loggedIn'] == true
                      ? 'logged_in'
                      : 'logged_out'
                  : 'changed';
      final origin = invocation?.origin ?? 'gui';
      final record = <String, Object?>{
        'at': at,
        'type': '${collection.split(':').first}.$operation',
        'subject_id': id,
        'actor': origin == 'gui'
            ? 'user'
            : origin.startsWith('hook:')
                ? 'hook'
                : 'agent',
        'origin': origin,
        'invocation_id': invocation?.id,
        'facts': jsonEncode({'before': old, 'after': value}),
      };
      _writes = _writes.then((_) async {
        await database.insert('body_changes', record);
      });
      // Report storage failures without changing Classic's successful write.
      unawaited(
          _writes.then<void>((_) {}, onError: (Object error, StackTrace stack) {
        FlutterError.reportError(FlutterErrorDetails(
            exception: error, stack: stack, library: 'Next change history'));
      }));
    }
  }

  Future<void> drain() => _writes;
}

final class InvocationScopeCapability implements Capability {
  InvocationScopeCapability(Capability capability)
      : actions = [
          for (final action in capability.actions) _ScopedAction(action)
        ];
  @override
  final List<Action> actions;
}

final class _ScopedAction extends Action<JsonEncodable, JsonEncodable> {
  const _ScopedAction(this.action);
  final Action action;
  @override
  ActionSpec get spec => action.spec;
  @override
  JsonEncodable decodeInput(JsonMap input) => action.decodeInput(input);
  @override
  Future<Outcome<JsonEncodable>> run(
          JsonEncodable input, Invocation invocation) =>
      runZoned(() async => await action.run(input, invocation),
          zoneValues: {BodyChanges.invocationKey: invocation});
}

final class OriginExecutor implements JobExecutor {
  const OriginExecutor(this.executor, this.database);
  final JobExecutor executor;
  final Database database;
  @override
  String get type => executor.type;
  Future<void> _run(JobContext context, bool recover) async {
    final rows = await database.query('task_origins',
        where: 'job_id=?', whereArgs: [context.job.jobId]);
    final origin = rows.firstOrNull;
    await runZoned(
        () => recover ? executor.recover(context) : executor.execute(context),
        zoneValues: {
          BodyChanges.invocationKey: origin == null
              ? null
              : Invocation(
                  origin: origin['origin'] as String,
                  id: origin['invocation_id'] as String?)
        });
  }

  @override
  Future<void> execute(JobContext context) => _run(context, false);
  @override
  Future<void> recover(JobContext context) => _run(context, true);
}
