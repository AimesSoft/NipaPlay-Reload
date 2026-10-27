import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../events/signals.dart';
import '../media/identity_store.dart' show newMediaId, stableMediaId;
import '../media/metadata_provider.dart' show ExternalRef;
import '../ui_data/service.dart' show validateViewerText;
import 'table_docs.dart';
import 'values.dart';

typedef Row = Map<String, Object?>;
typedef DbSerialize = Future<T> Function<T>(Future<T> Function() operation);

/// What a commit changed, for whoever refreshes caches and views.
final class DbCommitSummary {
  const DbCommitSummary(this.commitId, this.tables, this.entities);
  final String commitId;
  final Set<String> tables;

  /// Entity IDs by kind of change: metadata, artwork, danmaku, identity.
  final Map<String, Set<String>> entities;
}

const dbQueryLimits = (
  defaultRows: 100,
  maxRows: 1000,
  defaultBytes: 65536,
  maxBytes: 1048576,
  cellChars: 2000,
);

const _maxStatements = 100;
const _maxSqlChars = 20000;
const _maxChangedRows = 2000;
const _maxImageBytes = 4 * 1024 * 1024;
const _previewTtl = Duration(minutes: 10);
const _maxPreviews = 16;
const _eventsPerKind = 50;

final class _TableInfo {
  const _TableInfo(this.name, this.sql, this.columns, this.pk);
  final String name;
  final String? sql;
  final List<String> columns;
  final List<String> pk;

  DbTableDoc? get doc => dbTableDocs[name];
  bool get writable =>
      doc != null &&
      doc!.access == DbAccess.write &&
      pk.isNotEmpty &&
      !name.startsWith('sqlite_');
  String get readOnlyReason =>
      doc == null ? '没有登记在 db.describe 里的表默认只读' : doc!.reason ?? '该表只读';
}

final class _Statement {
  const _Statement(this.sql, this.params);
  final String sql;
  final List<Object?> params;
  JsonMap toJson() => {
        'sql': sql,
        if (params.isNotEmpty) 'params': [for (final p in params) jsonSafe(p)]
      };
}

final class _Change {
  _Change(this.table, this.before, this.after);
  final _TableInfo table;
  Row? before;
  Row? after;
  String get op => before == null
      ? 'insert'
      : after == null
          ? 'delete'
          : 'update';
  Row get row => (after ?? before)!;
  Row get key => {for (final c in table.pk) c: row[c]};
  String get keyText => jsonEncode(safeRow(key));
  bool get isNoop =>
      before != null && after != null && _same(table, before!, after!);
}

bool _same(_TableInfo t, Row a, Row b) =>
    jsonEncode([for (final c in t.columns) jsonSafe(a[c])]) ==
    jsonEncode([for (final c in t.columns) jsonSafe(b[c])]);

final class _Applied {
  const _Applied(this.changes, this.affected, this.problems, this.tables);
  final List<_Change> changes;
  final List<int> affected;
  final List<JsonMap> problems;
  final List<String> tables;
}

final class _Preview {
  _Preview(this.id, this.statementsHash, this.digest, this.at, this.statements,
      this.reason, this.origin);
  final String id, statementsHash, digest, origin;
  final String? reason;
  final DateTime at;
  final List<_Statement> statements;
}

final class _Rollback<T> implements Exception {
  const _Rollback(this.value);
  final T value;
}

String _q(String id) => '"${id.replaceAll('"', '""')}"';
String _lit(String text) => "'${text.replaceAll("'", "''")}'";

Never _fail(FailureCode code, String message, [JsonMap details = const {}]) =>
    throw Failure(code, message, details: details);

/// The end of a quoted name, string, bracketed name or comment that starts at
/// [i], or -1 when [i] starts none. These are the only constructs inside which
/// `;` and `?` are plain text, which is all the scanning below needs to know.
int _skipQuoted(String sql, int i) {
  final c = sql[i], end = sql.length;
  if (c == "'" || c == '"' || c == '`') {
    var j = i + 1;
    while (j < end) {
      if (sql[j] == c) {
        if (j + 1 < end && sql[j + 1] == c) {
          j += 2;
          continue;
        }
        return j + 1;
      }
      j++;
    }
    return end;
  }
  if (c == '[') {
    final close = sql.indexOf(']', i);
    return close < 0 ? end : close + 1;
  }
  if (c == '-' && i + 1 < end && sql[i + 1] == '-') {
    final newline = sql.indexOf('\n', i);
    return newline < 0 ? end : newline + 1;
  }
  if (c == '/' && i + 1 < end && sql[i + 1] == '*') {
    final close = sql.indexOf('*/', i + 2);
    return close < 0 ? end : close + 2;
  }
  return -1;
}

bool _isComment(String sql, int i) =>
    sql[i] == '-' && i + 1 < sql.length && sql[i + 1] == '-' ||
    sql[i] == '/' && i + 1 < sql.length && sql[i + 1] == '*';

/// One SQLite statement as text: drops a single trailing `;`, refuses a
/// second statement. Only quoting and comments are tracked, so a mistake here
/// can reject or admit odd text but never widens what SQLite itself enforces
/// (the parser gate, the read-only triggers and the query_only pragma).
String singleStatement(String sql) {
  final end = sql.length;
  var semi = -1, i = 0;
  while (i < end) {
    final skipped = _skipQuoted(sql, i);
    if (skipped >= 0) {
      if (semi >= 0 && !_isComment(sql, i)) {
        _fail(FailureCode.invalidInput, _multi);
      }
      i = skipped;
    } else if (sql[i] == ';') {
      if (semi >= 0) _fail(FailureCode.invalidInput, _multi);
      semi = i;
      i++;
    } else {
      if (semi >= 0 && sql[i].trim().isNotEmpty) {
        _fail(FailureCode.invalidInput, _multi);
      }
      i++;
    }
  }
  final text = semi >= 0 ? sql.substring(0, semi) : sql;
  if (text.trim().isEmpty) {
    _fail(FailureCode.invalidInput, 'The SQL is empty.');
  }
  return text;
}

/// The statement as SQLite's trigger parser can read it: a trigger body takes
/// no variables, so each `?` or `?NNN` outside quotes and comments becomes
/// NULL. Nothing else changes, so the parser sees the same kind of statement
/// that will run with the real parameters.
String probeText(String sql) {
  final out = StringBuffer();
  var i = 0;
  while (i < sql.length) {
    final skipped = _skipQuoted(sql, i);
    if (skipped >= 0) {
      out.write(sql.substring(i, skipped));
      i = skipped;
    } else if (sql[i] == '?') {
      i++;
      while (i < sql.length && '0123456789'.contains(sql[i])) {
        i++;
      }
      out.write('NULL');
    } else {
      out.write(sql[i]);
      i++;
    }
  }
  return out.toString();
}

const _multi =
    'One statement per item: send each INSERT/UPDATE/DELETE as its own entry in statements.';

Object? _param(Object? value, String path) {
  if (value == null || value is int || value is String) return value;
  if (value is double) {
    if (value.isFinite) return value;
  } else if (value is num) {
    return value;
  } else if (value is bool) {
    return value ? 1 : 0;
  } else if (value is Map && value.length == 1 && value[r'$blob'] is String) {
    try {
      return fromJsonSafe(value);
    } catch (_) {}
  }
  _fail(FailureCode.invalidInput,
      '$path must be null, a number, a string, a boolean (bound as 1/0) or {"\$blob": base64}. JSON objects and arrays go in as their JSON text.');
}

List<_Statement> _statements(Object? raw, {int max = _maxStatements}) {
  if (raw is! List || raw.isEmpty) {
    _fail(FailureCode.invalidInput,
        'statements must be a non-empty array of {sql, params?}.');
  }
  if (raw.length > max) {
    _fail(FailureCode.invalidInput,
        'At most $max statements per db.write; split the batch.');
  }
  final result = <_Statement>[];
  var chars = 0;
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! Map) {
      _fail(FailureCode.invalidInput, 'statements/$i must be an object.');
    }
    final unknown = item.keys.where((k) => k != 'sql' && k != 'params');
    if (unknown.isNotEmpty) {
      _fail(FailureCode.invalidInput,
          'statements/$i has unknown fields: ${unknown.join(', ')}.');
    }
    final sql = item['sql'];
    if (sql is! String) {
      _fail(FailureCode.invalidInput, 'statements/$i/sql must be a string.');
    }
    if (sql.length > _maxSqlChars) {
      _fail(FailureCode.invalidInput,
          'statements/$i/sql is longer than $_maxSqlChars characters.');
    }
    chars += sql.length;
    final params = item['params'];
    if (params != null && params is! List) {
      _fail(FailureCode.invalidInput, 'statements/$i/params must be an array.');
    }
    final values = (params as List?) ?? const [];
    result.add(_Statement(singleStatement(sql), [
      for (var p = 0; p < values.length; p++)
        _param(values[p], 'statements/$i/params/$p')
    ]));
  }
  if (chars > 10 * _maxSqlChars) {
    _fail(FailureCode.invalidInput, 'The batch SQL is too long; split it.');
  }
  return result;
}

String _statementsHash(List<_Statement> statements) => sha256
    .convert(utf8.encode(jsonEncode([for (final s in statements) s.toJson()])))
    .toString();

String _digest(List<_Change> changes) {
  final sorted = [...changes]..sort((a, b) {
      final t = a.table.name.compareTo(b.table.name);
      return t != 0 ? t : a.keyText.compareTo(b.keyText);
    });
  return sha256
      .convert(utf8.encode(jsonEncode([
        for (final c in sorted)
          [
            c.table.name,
            c.keyText,
            c.before == null
                ? null
                : [for (final col in c.table.columns) jsonSafe(c.before![col])],
            c.after == null
                ? null
                : [for (final col in c.table.columns) jsonSafe(c.after![col])],
          ]
      ])))
      .toString();
}

String _token() {
  final random = Random.secure();
  return [for (var i = 0; i < 4; i++) random.nextInt(0xffff).toRadixString(16)]
      .join();
}

String _actor(String origin) => origin == 'gui'
    ? 'user'
    : origin.startsWith('hook:')
        ? 'hook'
        : 'agent';

final _sqliteMessage =
    RegExp(r'while [a-z ]+, (.*?), [^,]*? \(code (\d+)\)', dotAll: true);

Never _sqliteFailure(Object error, int index, {bool probe = false}) {
  if (error is Failure) throw error;
  final text = error.toString();
  final match = _sqliteMessage.firstMatch(text);
  final message = match?.group(1) ?? text.split('\n').first;
  final code = int.tryParse(match?.group(2) ?? '');
  final readonly =
      RegExp(r'nipa_db_readonly\|([^|]+)\|(.*)').firstMatch(message);
  if (readonly != null) {
    _fail(
        FailureCode.invalidInput,
        'Statement ${index + 1}: table ${readonly.group(1)} is read-only for db.write. ${readonly.group(2)}',
        {'statementIndex': index, 'table': readonly.group(1)});
  }
  if (probe) {
    _fail(
        FailureCode.invalidInput,
        'Statement ${index + 1} is not a single INSERT, UPDATE or DELETE that SQLite accepts here ($message). DDL, PRAGMA, ATTACH, transaction control, RETURNING, schema-qualified table names and a leading WITH are refused; see db.describe semantics.sql_dialect.',
        {'statementIndex': index});
  }
  final constraint = code != null && (code & 0xff) == 19;
  _fail(
      constraint ? FailureCode.conflict : FailureCode.invalidInput,
      'Statement ${index + 1} was rejected by SQLite: $message',
      {'statementIndex': index, if (code != null) 'sqliteCode': code});
}

/// Direct access to `next.db`: documented tables, read-only SQL, previewed
/// writes with an audit and an undo. Everything that must not happen is
/// refused by SQLite itself (parser, triggers, pragmas, constraints); this
/// class only arranges for SQLite to do so and reports what it did.
final class DbService {
  DbService(this.database, {DbSerialize? serialize, this.afterCommit})
      : _serialize = serialize ?? (<T>(Future<T> Function() op) => op());
  final Database database;
  final DbSerialize _serialize;

  /// Refreshes views and caches after a commit; returns what it refreshed.
  Future<List<String>> Function(DbCommitSummary)? afterCommit;
  final _previews = <String, _Preview>{};

  // ── schema ─────────────────────────────────────────────────────────────

  Future<List<_TableInfo>> _tables(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name");
    final result = <_TableInfo>[];
    for (final row in rows) {
      final name = row['name'] as String;
      final info = await db.rawQuery('PRAGMA table_info(${_q(name)})');
      final pk = info.where((c) => (c['pk'] as int) > 0).toList()
        ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
      result.add(_TableInfo(
          name,
          row['sql'] as String?,
          [for (final c in info) c['name'] as String],
          [for (final c in pk) c['name'] as String]));
    }
    return result;
  }

  Future<JsonMap> describe(JsonMap input) async {
    final wanted = (input['tables'] as List?)?.cast<String>().toSet();
    final tables = await _tables(database);
    if (wanted != null) {
      final unknown = wanted.difference({for (final t in tables) t.name});
      if (unknown.isNotEmpty) {
        _fail(FailureCode.notFound, 'Unknown table: ${unknown.join(', ')}.');
      }
    }
    final result = <JsonMap>[];
    for (final t in tables) {
      if (wanted != null && !wanted.contains(t.name)) continue;
      final columns =
          await database.rawQuery('PRAGMA table_info(${_q(t.name)})');
      final fks = <int, JsonMap>{};
      for (final r in await database
          .rawQuery('PRAGMA foreign_key_list(${_q(t.name)})')) {
        final entry = fks.putIfAbsent(
            r['id'] as int,
            () => {
                  'columns': <String>[],
                  'references': {'table': r['table'], 'columns': <String?>[]},
                  'onUpdate': r['on_update'],
                  'onDelete': r['on_delete'],
                });
        (entry['columns'] as List).add(r['from']);
        ((entry['references'] as Map)['columns'] as List).add(r['to']);
      }
      final indexes = <JsonMap>[];
      for (final r
          in await database.rawQuery('PRAGMA index_list(${_q(t.name)})')) {
        final name = r['name'] as String;
        indexes.add({
          'name': name,
          'unique': r['unique'] == 1,
          'origin': switch (r['origin']) {
            'c' => 'create_index',
            'u' => 'unique_constraint',
            'pk' => 'primary_key',
            final other => other
          },
          'columns': [
            for (final c
                in await database.rawQuery('PRAGMA index_info(${_q(name)})'))
              c['name']
          ],
        });
      }
      final doc = t.doc;
      result.add({
        'name': t.name,
        'access': t.writable ? 'write' : 'read',
        'documented': doc != null,
        'summary': doc?.summary ?? '没有登记说明的表；默认只读。',
        if (!t.writable) 'readOnlyReason': t.readOnlyReason,
        if (doc != null && doc.notes.isNotEmpty) 'notes': doc.notes,
        if (t.writable && doc!.json.isNotEmpty)
          'jsonColumns': {
            for (final e in doc.json.entries) e.key: e.value.name
          },
        'columns': [
          for (final c in columns)
            {
              'name': c['name'],
              'type': c['type'],
              'notNull': c['notnull'] == 1,
              'default': c['dflt_value'],
              'primaryKeyPosition': c['pk'],
            }
        ],
        'primaryKey': t.pk,
        'foreignKeys': fks.values.toList(),
        'indexes': indexes,
        if (t.sql != null) 'sql': t.sql,
      });
    }
    return {
      'database': 'next.db',
      'tables': result,
      if (wanted == null) 'semantics': dbSemantics,
      'actions': {
        'db.query':
            'One SELECT (WITH … SELECT, VALUES) with ? parameters; read-only by SQLite. limit (default ${dbQueryLimits.defaultRows}, max ${dbQueryLimits.maxRows}) and maxBytes (default ${dbQueryLimits.defaultBytes}) bound the result; when cut, truncated is true and nextOffset says where to continue.',
        'db.write':
            'A batch of INSERT/UPDATE/DELETE in one transaction. Without previewId it is only previewed (rolled back) and returns row-level before/after images and a previewId; with previewId it commits exactly what was previewed. Reuse that previewId from the same origin to recover its durable receipt after response loss or restart; supplied statements and commit reason must match.',
        'db.undo':
            'Restores the before-images of a commit when every row is still as that commit left it; otherwise refuses and lists the conflicting rows. Remote commits require a stable requestId; the same origin retries with identical commitId and reason to recover the durable result.',
      },
      'limits': {
        'statementsPerWrite': _maxStatements,
        'sqlCharsPerStatement': _maxSqlChars,
        'changedRowsPerCommit': _maxChangedRows,
        'previewTtlMinutes': _previewTtl.inMinutes,
        'queryRows': dbQueryLimits.maxRows,
        'queryBytes': dbQueryLimits.maxBytes,
      },
    };
  }

  // ── read ───────────────────────────────────────────────────────────────

  Future<JsonMap> query(JsonMap input) async {
    const known = {'sql', 'params', 'limit', 'offset', 'maxBytes'};
    final unknown = input.keys.where((k) => !known.contains(k));
    if (unknown.isNotEmpty) {
      _fail(FailureCode.invalidInput, 'Unknown fields: ${unknown.join(', ')}.');
    }
    final sql = singleStatement(input['sql'] as String);
    final rawParams = input['params'];
    if (rawParams != null && rawParams is! List) {
      _fail(FailureCode.invalidInput, 'params must be an array.');
    }
    final given = (rawParams as List?) ?? const [];
    final params = [
      for (var i = 0; i < given.length; i++) _param(given[i], 'params/$i')
    ];
    final limit =
        (input['limit'] as num?)?.toInt() ?? dbQueryLimits.defaultRows;
    final offset = (input['offset'] as num?)?.toInt() ?? 0;
    final maxBytes =
        (input['maxBytes'] as num?)?.toInt() ?? dbQueryLimits.defaultBytes;
    if (limit < 1 || limit > dbQueryLimits.maxRows) {
      _fail(FailureCode.invalidInput,
          'limit must be 1–${dbQueryLimits.maxRows}.');
    }
    if (offset < 0) _fail(FailureCode.invalidInput, 'offset must be ≥ 0.');
    if (maxBytes < 1024 || maxBytes > dbQueryLimits.maxBytes) {
      _fail(FailureCode.invalidInput,
          'maxBytes must be 1024–${dbQueryLimits.maxBytes}.');
    }
    // SQLite's grammar only lets a select statement stand inside parentheses:
    // INSERT, WITH … DELETE, PRAGMA, ATTACH, DDL are syntax errors here.
    final wrapped =
        'SELECT * FROM (\n$sql\n) LIMIT ${limit + 1} OFFSET $offset';
    List<Row> rows;
    try {
      rows = await database.transaction((tx) async {
        final before = await tx.rawQuery('PRAGMA query_only');
        final was = before.first.values.first == 1;
        await tx.execute('PRAGMA query_only=ON');
        try {
          return await tx.rawQuery(wrapped, params);
        } finally {
          await tx.execute('PRAGMA query_only=${was ? 'ON' : 'OFF'}');
        }
      });
    } on Failure {
      rethrow;
    } catch (error) {
      final text = error.toString();
      final match = _sqliteMessage.firstMatch(text);
      final message = match?.group(1) ?? text.split('\n').first;
      _fail(FailureCode.invalidInput,
          'SQLite rejected the query ($message). db.query takes exactly one SELECT (or WITH … SELECT / VALUES); use db.write to change data.');
    }
    final view = CellView(dbQueryLimits.cellChars);
    final out = <JsonMap>[];
    var bytes = 2;
    var truncatedBy = rows.length > limit ? 'rows' : null;
    for (final row in rows.take(limit)) {
      final cells = view.row(row);
      final size = utf8.encode(jsonEncode(cells)).length + 1;
      if (out.isNotEmpty && bytes + size > maxBytes) {
        truncatedBy = 'bytes';
        break;
      }
      bytes += size;
      out.add(cells);
    }
    final more = truncatedBy != null;
    return redactedOutput({
      'columns': rows.isEmpty ? <String>[] : rows.first.keys.toList(),
      'rows': out,
      'rowCount': out.length,
      'offset': offset,
      'limit': limit,
      'truncated': more,
      if (more) 'truncatedBy': truncatedBy,
      'nextOffset': more ? offset + out.length : null,
      if (view.cut > 0) 'truncatedCells': view.cut,
      if (more || view.cut > 0)
        'hint':
            'Rows beyond the cap were not returned. Repeat with offset=nextOffset (give the query an ORDER BY so pages are stable), or narrow it with WHERE, LIMIT or fewer columns.${view.cut > 0 ? ' Cells longer than ${dbQueryLimits.cellChars} characters were cut; select substr(col, start, length) to read the rest.' : ''}',
    });
  }

  // ── write ──────────────────────────────────────────────────────────────

  Future<JsonMap> write(JsonMap input, Invocation invocation) async {
    const known = {'statements', 'previewId', 'reason'};
    final unknown = input.keys.where((k) => !known.contains(k));
    if (unknown.isNotEmpty) {
      _fail(FailureCode.invalidInput, 'Unknown fields: ${unknown.join(', ')}.');
    }
    final reason = input['reason'] as String?;
    final previewId = input['previewId'] as String?;
    if (previewId == null) {
      return _preview(
          _statements(input['statements']), reason, invocation.origin);
    }
    return _commit(previewId, input, invocation, reason);
  }

  void _expire() {
    final cutoff = DateTime.now().subtract(_previewTtl);
    _previews.removeWhere((_, p) => p.at.isBefore(cutoff));
  }

  Future<JsonMap> receipt(JsonMap input, Invocation invocation) async {
    final kind = input['kind'] as String;
    final key = input['requestKey'] as String;
    final row = await _receipt(database, kind, key, invocation.origin);
    if (row != null)
      return {
        'state': 'committed',
        'durable': true,
        'kind': kind,
        'requestKey': key,
        'commitId': row['commit_id'],
        'result': _receiptResult(row),
        'retry': 'same_request_returns_receipt',
      };
    _expire();
    final preview = kind == 'write' ? _previews[key] : null;
    return {
      'state': preview?.origin == invocation.origin
          ? 'preview_available'
          : 'unknown',
      'durable': false,
      'kind': kind,
      'requestKey': key,
      'absenceMeans':
          'No committed receipt observed for this origin and key; this is not proof that an in-flight request cannot commit later.',
      'retry': 'keep_original_request_key'
    };
  }

  Future<JsonMap> _preview(
      List<_Statement> statements, String? reason, String origin) async {
    _Applied? previewed;
    try {
      await database.transaction((tx) async {
        throw _Rollback(await _apply(tx, statements));
      });
    } on _Rollback<_Applied> catch (rolled) {
      previewed = rolled.value;
    }
    final applied = previewed;
    final problems = applied.problems;
    String? id;
    if (problems.isEmpty) {
      _expire();
      while (_previews.length >= _maxPreviews) {
        _previews.remove(_previews.keys.first);
      }
      id = 'dbp-${_token()}${_token()}';
      _previews[id] = _Preview(id, _statementsHash(statements),
          _digest(applied.changes), DateTime.now(), statements, reason, origin);
    }
    return redactedOutput({
      'status': 'preview',
      'committed': false,
      if (id != null) 'previewId': id,
      if (id != null)
        'expiresAt': DateTime.now().add(_previewTtl).toUtc().toIso8601String(),
      'committable': problems.isEmpty,
      if (problems.isNotEmpty) 'problems': problems,
      'statements': [
        for (var i = 0; i < statements.length; i++)
          {'index': i, 'rowsAffected': applied.affected[i]}
      ],
      ..._display(applied.changes),
      if (id != null)
        'next':
            'Commit exactly this with db.write {previewId:"$id"}; nothing has been written yet.',
    });
  }

  // Receipts are written in the same transaction as the data and audit. The
  // authenticated origin scopes the key; neither another device nor a new RPC
  // invocation ID can consume a preview or cause a committed batch to run twice.
  Future<Row?> _receipt(
      DatabaseExecutor tx, String kind, String key, String origin) async {
    final rows = await tx.query('db_operations',
        where: 'kind=? AND origin=? AND request_key=?',
        whereArgs: [kind, origin, key]);
    return rows.firstOrNull;
  }

  JsonMap _receiptResult(Row row) => redactedOutput(
      (jsonDecode(row['result'] as String) as Map).cast<String, Object?>());

  Future<void> _saveReceipt(Transaction tx, String kind, String key,
      Invocation invocation, JsonMap request, JsonMap result) async {
    await tx.insert('db_operations', {
      'kind': kind,
      'origin': invocation.origin,
      'request_key': key,
      'request': jsonEncode(request),
      'commit_id': result['commitId'],
      'result': jsonEncode(result),
    });
  }

  Future<JsonMap> _finishReceipt(String kind, String key, Invocation invocation,
      String commitId, _Applied applied, Map<String, Set<String>> entities,
      {String? undoes}) async {
    final result = {
      ...await _afterCommit(commitId, kind == 'write' ? 'committed' : 'undone',
          applied.changes, applied.affected, entities, invocation,
          undoes: undoes),
      if (kind == 'write') 'previewId': key else 'requestId': key,
    };
    await database.update('db_operations', {'result': jsonEncode(result)},
        where: 'kind=? AND origin=? AND request_key=?',
        whereArgs: [kind, invocation.origin, key]);
    return result;
  }

  Future<JsonMap> _commit(String previewId, JsonMap input,
      Invocation invocation, String? reason) async {
    final suppliedHash = input['statements'] == null
        ? null
        : _statementsHash(_statements(input['statements']));
    final done = await _serialize(() async {
      _Applied? applied;
      String? commitId;
      JsonMap? recovered;
      var entities = <String, Set<String>>{};
      await database.transaction((tx) async {
        final receipt =
            await _receipt(tx, 'write', previewId, invocation.origin);
        if (receipt != null) {
          final request = jsonDecode(receipt['request'] as String) as Map;
          if ((suppliedHash != null &&
                  suppliedHash != request['statementsHash']) ||
              reason != request['reason']) {
            _fail(FailureCode.conflict,
                'This previewId was committed with different statements or reason.');
          }
          recovered = _receiptResult(receipt);
          return;
        }
        _expire();
        final preview = _previews[previewId];
        if (preview == null || preview.origin != invocation.origin) {
          _fail(FailureCode.notFound,
              'No uncommitted preview for this origin (it expired or the app restarted). Preview again.');
        }
        if (suppliedHash != null && suppliedHash != preview.statementsHash) {
          _fail(FailureCode.invalidInput,
              'statements differ from the ones previewed under this previewId.');
        }
        applied = await _apply(tx, preview.statements);
        if (_digest(applied!.changes) != preview.digest) {
          _fail(FailureCode.conflict,
              'The rows this batch touches changed since the preview, so the commit was refused and nothing was written. Preview again.');
        }
        _requireClean(applied!);
        entities = await _entities(tx, applied!.changes);
        commitId = await _audit(
            tx,
            'write',
            invocation,
            reason ?? preview.reason,
            preview.statements,
            applied!.changes,
            null,
            entities);
        await _saveReceipt(tx, 'write', previewId, invocation, {
          'statementsHash': preview.statementsHash,
          'reason': reason
        }, {
          ..._commitResult(commitId!, 'committed', applied!.changes,
              applied!.affected, const [], const []),
          'previewId': previewId,
          'postCommitPending': true,
        });
      });
      if (commitId != null) _previews.remove(previewId);
      return (commitId, applied, entities, recovered);
    });
    if (done.$4 != null) return done.$4!;
    // Refreshes may themselves enter the domain writers' queue. Run them after
    // releasing it; a crash here still leaves a truthful, committed receipt.
    return _finishReceipt(
        'write', previewId, invocation, done.$1!, done.$2!, done.$3);
  }

  void _requireClean(_Applied applied) {
    if (applied.problems.isNotEmpty) {
      throw Failure(FailureCode.conflict,
          'The batch broke an integrity rule, so it was rolled back and nothing was written.',
          details: {'problems': applied.problems});
    }
  }

  // ── undo ───────────────────────────────────────────────────────────────

  Future<JsonMap> undo(JsonMap input, Invocation invocation) async {
    const known = {'commitId', 'dryRun', 'reason', 'requestId'};
    final unknown = input.keys.where((k) => !known.contains(k));
    if (unknown.isNotEmpty) {
      _fail(FailureCode.invalidInput, 'Unknown fields: ${unknown.join(', ')}.');
    }
    final commitId = input['commitId'] as String;
    final dryRun = input['dryRun'] == true;
    final reason = input['reason'] as String?;
    final suppliedKey = input['requestId'];
    if (suppliedKey != null &&
        (suppliedKey is! String ||
            suppliedKey.isEmpty ||
            suppliedKey.length > 256)) {
      _fail(FailureCode.invalidInput,
          'requestId must contain 1..256 characters.');
    }
    if (!dryRun &&
        invocation.origin.startsWith('mesh:') &&
        suppliedKey == null) {
      _fail(FailureCode.invalidInput,
          'Remote db.undo requires a stable requestId; reuse it when retrying.');
    }
    final key = suppliedKey as String? ?? 'dbu-${_token()}${_token()}';
    final request = <String, Object?>{'commitId': commitId, 'reason': reason};
    final done = await _serialize(() async {
      _Applied? applied;
      JsonMap? recovered;
      List<JsonMap>? conflicts;
      String? undoId;
      List<_Change>? original;
      var entities = <String, Set<String>>{};
      try {
        await database.transaction((tx) async {
          if (!dryRun) {
            final receipt = await _receipt(tx, 'undo', key, invocation.origin);
            if (receipt != null) {
              if (receipt['request'] != jsonEncode(request)) {
                _fail(FailureCode.conflict,
                    'This requestId was used for a different undo or reason.');
              }
              recovered = _receiptResult(receipt);
              return;
            }
          }
          final rows = await tx
              .query('db_commits', where: 'id=?', whereArgs: [commitId]);
          if (rows.isEmpty) {
            _fail(FailureCode.notFound, 'No such commit: $commitId.');
          }
          final tables = await _tables(tx);
          final byName = {for (final t in tables) t.name: t};
          original = _decodeChanges(rows.single['changes'] as String, byName);
          final found = await _conflicts(tx, original!);
          if (found.isNotEmpty) {
            conflicts = found;
            throw const _Rollback(null);
          }
          final inverse = [
            for (final c in original!) _Change(c.table, c.after, c.before)
          ];
          final statements = _inverseStatements(original!);
          applied = await _apply(tx, statements);
          _requireClean(applied!);
          if (_digest(applied!.changes) != _digest(inverse)) {
            _fail(FailureCode.internal,
                'The undo did not reproduce the recorded before-images, so it was rolled back.');
          }
          if (dryRun) throw const _Rollback(null);
          entities = await _entities(tx, applied!.changes);
          undoId = await _audit(tx, 'undo', invocation, reason, statements,
              applied!.changes, commitId, entities);
          await _saveReceipt(tx, 'undo', key, invocation, request, {
            ..._commitResult(undoId!, 'undone', applied!.changes,
                applied!.affected, const [], const [],
                undoes: commitId),
            'requestId': key,
            'postCommitPending': true,
          });
        });
      } on _Rollback<Null> {
        if (conflicts == null && !dryRun) rethrow;
      }
      if (conflicts != null) {
        throw Failure(FailureCode.conflict,
            'Some rows are no longer as commit $commitId left them, so nothing was undone.',
            details: {
              'commitId': commitId,
              'conflictCount': conflicts!.length,
              'conflicts': conflicts!.take(50).toList(),
            });
      }
      return (undoId, applied, entities, recovered);
    });
    if (done.$4 != null) return done.$4!;
    if (done.$1 == null) {
      return redactedOutput({
        'status': 'dry_run',
        'committed': false,
        'commitId': commitId,
        'wouldRestore': _display(done.$2!.changes),
      });
    }
    return _finishReceipt('undo', key, invocation, done.$1!, done.$2!, done.$3,
        undoes: commitId);
  }

  List<_Change> _decodeChanges(String text, Map<String, _TableInfo> byName) {
    final result = <_Change>[];
    for (final item in (jsonDecode(text) as List).cast<Map>()) {
      final table = byName[item['table'] as String];
      if (table == null) {
        _fail(FailureCode.conflict,
            'Table ${item['table']} no longer exists; this commit cannot be undone.');
      }
      result.add(_Change(
          table,
          item['before'] == null ? null : unsafeRow(item['before'] as Map),
          item['after'] == null ? null : unsafeRow(item['after'] as Map)));
    }
    return result;
  }

  Future<Row?> _current(DatabaseExecutor tx, _Change change, Row key) async {
    final rows = await tx.query(change.table.name,
        where: change.table.pk.map((c) => '${_q(c)}=?').join(' AND '),
        whereArgs: [for (final c in change.table.pk) key[c]]);
    return rows.isEmpty ? null : Row.of(rows.single);
  }

  Future<List<JsonMap>> _conflicts(
      DatabaseExecutor tx, List<_Change> changes) async {
    final result = <JsonMap>[];
    final view = CellView(300);
    for (final c in changes) {
      JsonMap? conflict;
      if (c.after != null) {
        final now = await _current(tx, c, c.after!);
        if (now == null) {
          conflict = {'problem': 'row_missing', 'expected': c.after};
        } else if (!_same(c.table, now, c.after!)) {
          conflict = {
            'problem': 'row_changed',
            'expected': c.after,
            'actual': now
          };
        }
      }
      if (conflict == null &&
          c.before != null &&
          (c.after == null ||
              c.table.pk.any((k) => c.before![k] != c.after![k]))) {
        final occupied = await _current(tx, c, c.before!);
        if (occupied != null) {
          conflict = {
            'problem': 'row_occupied',
            'restoring': c.before,
            'actual': occupied
          };
        }
      }
      if (conflict != null) {
        result.add({
          'table': c.table.name,
          'key': safeRow(c.key),
          for (final e in conflict.entries)
            e.key: e.value is Map
                ? view.row((e.value as Map).cast<String, Object?>())
                : e.value,
        });
      }
    }
    return result;
  }

  /// Statements that take each recorded change back: delete what it inserted,
  /// put back what it updated, insert what it deleted.
  List<_Statement> _inverseStatements(List<_Change> recorded) {
    final deletes = <_Statement>[],
        updates = <_Statement>[],
        inserts = <_Statement>[];
    for (final c in recorded) {
      final t = c.table;
      if (c.after == null) {
        inserts.add(_Statement(
            'INSERT INTO ${_q(t.name)} (${t.columns.map(_q).join(',')}) VALUES (${List.filled(t.columns.length, '?').join(',')})',
            [for (final col in t.columns) c.before![col]]));
      } else if (c.before == null) {
        deletes.add(_Statement(
            'DELETE FROM ${_q(t.name)} WHERE ${t.pk.map((k) => '${_q(k)}=?').join(' AND ')}',
            [for (final k in t.pk) c.after![k]]));
      } else {
        updates.add(_Statement(
            'UPDATE ${_q(t.name)} SET ${t.columns.map((col) => '${_q(col)}=?').join(',')} WHERE ${t.pk.map((k) => '${_q(k)}=?').join(' AND ')}',
            [
              for (final col in t.columns) c.before![col],
              for (final k in t.pk) c.after![k]
            ]));
      }
    }
    return [...deletes, ...updates, ...inserts];
  }

  // ── the transaction body shared by preview, commit and undo ───────────

  Future<_Applied> _apply(Transaction tx, List<_Statement> statements) async {
    final tables = await _tables(tx);
    final byName = {for (final t in tables) t.name: t};
    final log = 'nipa_log_${_token()}';
    final names = <String>[];
    final recursive =
        (await tx.rawQuery('PRAGMA recursive_triggers')).first.values.first ==
            1;
    final sequenceBefore = await _sequences(tx);
    final violationsBefore = await _violations(tx);
    var changes = <_Change>[];
    final affected = <int>[];
    try {
      // REPLACE conflict deletes only reach triggers when this is on; the
      // foreign key check waits for the end of the batch.
      await tx.execute('PRAGMA recursive_triggers=ON');
      await tx.execute('PRAGMA defer_foreign_keys=ON');
      await _arm(tx, tables, log, names);
      for (var i = 0; i < statements.length; i++) {
        // SQLite's parser accepts only DML as a trigger body: DDL, PRAGMA,
        // ATTACH, BEGIN/COMMIT/SAVEPOINT are syntax errors there.
        final probe = 'nipa_probe_${log.substring(9)}';
        try {
          await tx.rawQuery(
              'CREATE TEMP TRIGGER $probe AFTER INSERT ON ${_q(log)} BEGIN\n${probeText(statements[i].sql)}\n;\nEND');
          await tx.execute('DROP TRIGGER temp.$probe');
        } catch (error) {
          _sqliteFailure(error, i, probe: true);
        }
      }
      for (var i = 0; i < statements.length; i++) {
        try {
          affected
              .add(await tx.rawUpdate(statements[i].sql, statements[i].params));
        } catch (error) {
          _sqliteFailure(error, i);
        }
      }
      changes = await _collect(tx, log, byName);
    } finally {
      try {
        await _disarm(tx, log, names);
        await tx
            .execute('PRAGMA recursive_triggers=${recursive ? 'ON' : 'OFF'}');
      } catch (_) {}
    }
    // sqlite_sequence cannot carry a trigger; compare it instead.
    final sequenceAfter = await _sequences(tx);
    for (final name in {...sequenceBefore.keys, ...sequenceAfter.keys}) {
      if (sequenceBefore[name] != sequenceAfter[name] &&
          !(byName[name]?.writable ?? false)) {
        _fail(FailureCode.invalidInput,
            'sqlite_sequence for read-only table $name was changed; that is not allowed.');
      }
    }
    if (changes.length > _maxChangedRows) {
      _fail(FailureCode.invalidInput,
          'This batch changes ${changes.length} rows (limit $_maxChangedRows per commit); narrow the WHERE or split the batch.');
    }
    var imageBytes = 0;
    for (final c in changes) {
      imageBytes += utf8
          .encode(jsonEncode([
            if (c.before != null) safeRow(c.before!),
            if (c.after != null) safeRow(c.after!)
          ]))
          .length;
    }
    if (imageBytes > _maxImageBytes) {
      _fail(FailureCode.invalidInput,
          'The changed rows hold ${imageBytes ~/ 1024} KiB (limit ${_maxImageBytes ~/ 1024} KiB per commit); split the batch.');
    }

    final problems = <JsonMap>[];
    final violationsAfter = await _violations(tx);
    for (final v in violationsAfter.entries) {
      if (!violationsBefore.containsKey(v.key)) problems.add(v.value);
    }
    for (final c in changes) {
      if (c.after == null) continue;
      for (final text in await _rowProblems(tx, c)) {
        problems.add({
          'kind': 'row',
          'table': c.table.name,
          'key': safeRow(c.key),
          'problem': text
        });
      }
    }
    for (final name in {for (final c in changes) c.table.name}) {
      final check = await tx.rawQuery('PRAGMA quick_check(${_q(name)})');
      final bad = [
        for (final r in check)
          if (r.values.first != 'ok') r.values.first
      ];
      if (bad.isNotEmpty) {
        problems.add({
          'kind': 'integrity',
          'table': name,
          'problem': bad.take(5).join('; ')
        });
      }
    }
    return _Applied(
        changes,
        affected,
        problems,
        [
          for (final t in {for (final c in changes) c.table.name}) t
        ]..sort());
  }

  Future<Map<String, int?>> _sequences(DatabaseExecutor tx) async => {
        for (final r
            in await tx.rawQuery('SELECT name, seq FROM sqlite_sequence'))
          r['name'] as String: r['seq'] as int?
      };

  Future<Map<String, JsonMap>> _violations(DatabaseExecutor tx) async {
    final result = <String, JsonMap>{};
    for (final r in await tx.rawQuery('PRAGMA foreign_key_check')) {
      final key = '${r['table']}|${r['rowid']}|${r['parent']}|${r['fkid']}';
      result[key] = {
        'kind': 'foreign_key',
        'table': r['table'],
        'rowid': r['rowid'],
        'references': r['parent'],
        'problem':
            'row refers to a missing row in ${r['parent']} (or a row still referred to was deleted)'
      };
    }
    return result;
  }

  Future<void> _arm(Transaction tx, List<_TableInfo> tables, String log,
      List<String> names) async {
    final width = tables
        .where((t) => t.writable)
        .fold<int>(1, (m, t) => max(m, t.columns.length));
    final batch = tx.batch();
    batch.execute(
        'CREATE TEMP TABLE ${_q(log)} (seq INTEGER PRIMARY KEY, tbl, op, ${[
      for (var i = 0; i < width; i++) 'o$i',
      for (var i = 0; i < width; i++) 'n$i'
    ].join(', ')})');
    for (final op in ['UPDATE', 'DELETE']) {
      final name = '${log}_g${op[0].toLowerCase()}';
      names.add(name);
      batch.execute(
          'CREATE TEMP TRIGGER $name BEFORE $op ON ${_q(log)} BEGIN SELECT RAISE(ABORT, \'nipa_db_internal\'); END');
    }
    for (var index = 0; index < tables.length; index++) {
      final t = tables[index];
      // The change counter is moved by triggers of the tables it counts.
      if (t.name.startsWith('sqlite_') || t.name == 'change_epochs') continue;
      final base = '${log}_t$index';
      if (!t.writable) {
        final message = _lit('nipa_db_readonly|${t.name}|${t.readOnlyReason}');
        for (final op in ['INSERT', 'UPDATE', 'DELETE']) {
          final name = '${base}_${op[0].toLowerCase()}';
          names.add(name);
          batch.execute(
              'CREATE TEMP TRIGGER $name BEFORE $op ON main.${_q(t.name)} BEGIN SELECT RAISE(ABORT, $message); END');
        }
        continue;
      }
      String cols(String prefix) =>
          [for (var i = 0; i < t.columns.length; i++) '$prefix$i'].join(',');
      String values(String record) =>
          [for (final c in t.columns) '$record.${_q(c)}'].join(',');
      final tbl = _lit(t.name);
      final specs = {
        'i': (
          'INSERT',
          "INSERT INTO ${_q(log)}(tbl,op,${cols('n')}) VALUES($tbl,'I',${values('NEW')})"
        ),
        'u': (
          'UPDATE',
          "INSERT INTO ${_q(log)}(tbl,op,${cols('o')},${cols('n')}) VALUES($tbl,'U',${values('OLD')},${values('NEW')})"
        ),
        'd': (
          'DELETE',
          "INSERT INTO ${_q(log)}(tbl,op,${cols('o')}) VALUES($tbl,'D',${values('OLD')})"
        ),
      };
      for (final e in specs.entries) {
        final name = '${base}_${e.key}';
        names.add(name);
        batch.execute(
            'CREATE TEMP TRIGGER $name AFTER ${e.value.$1} ON main.${_q(t.name)} BEGIN ${e.value.$2}; END');
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _disarm(Transaction tx, String log, List<String> names) async {
    final batch = tx.batch();
    for (final name in names) {
      batch.execute('DROP TRIGGER IF EXISTS temp.$name');
    }
    batch.execute('DROP TABLE IF EXISTS temp.${_q(log)}');
    await batch.commit(noResult: true);
    names.clear();
  }

  Future<List<_Change>> _collect(
      DatabaseExecutor tx, String log, Map<String, _TableInfo> byName) async {
    final nets = <String, _Change>{};
    String id(_Change c) => '${c.table.name}\u0000${c.keyText}';
    Row image(_TableInfo t, JsonMap row, String prefix) => {
          for (var i = 0; i < t.columns.length; i++)
            t.columns[i]: row['$prefix$i']
        };
    for (final row
        in await tx.rawQuery('SELECT * FROM ${_q(log)} ORDER BY seq')) {
      final t = byName[row['tbl'] as String]!;
      switch (row['op']) {
        case 'I':
          final fresh = _Change(t, null, image(t, row, 'n'));
          final existing = nets[id(fresh)];
          if (existing != null && existing.after == null) {
            existing.after = fresh.after;
          } else {
            nets[id(fresh)] = fresh;
          }
        case 'D':
          final old = _Change(t, image(t, row, 'o'), null);
          final existing = nets[id(old)];
          if (existing == null) {
            nets[id(old)] = old;
          } else if (existing.before == null) {
            nets.remove(id(old));
          } else {
            existing.after = null;
          }
        default:
          final from = _Change(t, image(t, row, 'o'), null);
          final to = image(t, row, 'n');
          final moved = nets.remove(id(from)) ?? from;
          moved.after = to;
          final target = id(moved);
          if (nets.containsKey(target)) {
            _fail(FailureCode.invalidInput,
                'The batch rewrites primary keys of ${t.name} in a way that cannot be tracked row by row; do it in separate commits.');
          }
          nets[target] = moved;
      }
    }
    return [
      for (final c in nets.values)
        if (!c.isNoop) c
    ]..sort((a, b) {
        final t = a.table.name.compareTo(b.table.name);
        return t != 0 ? t : a.keyText.compareTo(b.keyText);
      });
  }

  Future<List<String>> _rowProblems(DatabaseExecutor tx, _Change c) async {
    final problems = <String>[];
    final doc = c.table.doc!;
    final after = c.after!;
    for (final e in doc.json.entries) {
      final value = after[e.key];
      if (value == null) continue;
      if (value is! String) {
        problems.add('${e.key} must be JSON text');
        continue;
      }
      try {
        final parsed = jsonDecode(value);
        if (e.value == DbJson.object && parsed is! Map) {
          problems.add('${e.key} must be a JSON object');
        }
        if (e.value == DbJson.array && parsed is! List) {
          problems.add('${e.key} must be a JSON array');
        }
      } on FormatException catch (error) {
        problems.add('${e.key} is not valid JSON (${error.message})');
      }
    }
    if (problems.isNotEmpty) return problems;
    switch (c.table.name) {
      case 'media_external_objects':
        final expected = stableMediaId(
            'object',
            ExternalRef(
                    after['provider'] as String,
                    after['object_type'] as String,
                    after['external_id'] as String,
                    scope: after['scope'] as String)
                .toJson());
        if (after['id'] != expected) {
          problems.add(
              'id must be $expected, the stable hash of provider, object_type, external_id and scope');
        }
      case 'ui_shelves':
        final payload = jsonDecode(after['payload'] as String) as Map;
        for (final key in ['title', 'note']) {
          final value = payload[key];
          if (value == null) continue;
          if (value is! String) {
            problems.add('$key must be text');
            continue;
          }
          try {
            validateViewerText(value);
          } on Failure catch (error) {
            problems.add('$key: ${error.message}');
          }
        }
        final items = payload['items'];
        if (items is! List) {
          problems.add('items must be an array');
          break;
        }
        if (payload['placement'] == 'hero' && items.length > 1) {
          problems.add('a hero holds at most one item');
        }
        for (final item in items) {
          if (item is! Map || item['workId'] is! String) {
            problems.add('each item needs a workId');
            continue;
          }
          final note = item['note'];
          if (note is String) {
            try {
              validateViewerText(note);
            } on Failure catch (error) {
              problems.add('item note: ${error.message}');
            }
          }
          final found = await tx.rawQuery(
              "SELECT 1 FROM media_entities WHERE id=? AND kind='work'",
              [item['workId']]);
          if (found.isEmpty) {
            problems.add('item ${item['workId']} is not a library work');
          }
        }
    }
    return problems;
  }

  // ── audit and notification ────────────────────────────────────────────

  Future<String> _audit(
      Transaction tx,
      String kind,
      Invocation invocation,
      String? reason,
      List<_Statement> statements,
      List<_Change> changes,
      String? undoes,
      Map<String, Set<String>> entities) async {
    final id = newMediaId('dbcommit');
    final at = DateTime.now().toUtc().toIso8601String();
    final next = (await tx.rawQuery(
            'SELECT COALESCE(MAX(sequence),0)+1 AS next FROM db_commits'))
        .first['next'] as int;
    final counts = _counts(changes);
    await tx.insert('db_commits', {
      'id': id,
      'sequence': next,
      'kind': kind,
      'at': at,
      'actor': _actor(invocation.origin),
      'origin': invocation.origin,
      'invocation_id': invocation.id,
      'reason': reason,
      'statements': jsonEncode([for (final s in statements) s.toJson()]),
      'counts': jsonEncode(counts),
      'changes': jsonEncode([
        for (final c in changes)
          {
            'table': c.table.name,
            'key': safeRow(c.key),
            'before': c.before == null ? null : safeRow(c.before!),
            'after': c.after == null ? null : safeRow(c.after!),
          }
      ]),
      'undoes': undoes,
    });
    final total = changes.length;
    await tx.insert('body_changes', {
      'at': at,
      'type': kind == 'undo' ? 'db.undo' : 'db.write',
      'subject_id': id,
      'actor': _actor(invocation.origin),
      'origin': invocation.origin,
      'invocation_id': invocation.id,
      'facts': jsonEncode({
        'title': kind == 'undo' ? '撤回了一次数据库写入' : '直接修改了数据库（$total 行）',
        'commitId': id,
        'sequence': next,
        if (undoes != null) 'undoes': undoes,
        if (reason != null) 'reason': reason,
        'counts': counts,
        'entityIds': ({for (final ids in entities.values) ...ids}.toList()
              ..sort())
            .take(50)
            .toList(),
      }),
    });
    return id;
  }

  JsonMap _counts(List<_Change> changes) {
    final result = <String, Map<String, int>>{};
    for (final c in changes) {
      final entry = result.putIfAbsent(
          c.table.name, () => {'insert': 0, 'update': 0, 'delete': 0});
      entry[c.op] = entry[c.op]! + 1;
    }
    return result;
  }

  JsonMap _display(List<_Change> changes) {
    const perTable = 20, total = 100, byteCap = 48000;
    final tables = <String, JsonMap>{};
    var shown = 0, bytes = 0;
    final view = CellView(500);
    final counts = _counts(changes);
    for (final c in changes) {
      final entry = tables.putIfAbsent(
          c.table.name,
          () => {
                ...(counts[c.table.name] as Map).cast<String, Object?>(),
                'rows': <JsonMap>[]
              });
      final rows = entry['rows'] as List<JsonMap>;
      if (rows.length >= perTable || shown >= total || bytes >= byteCap) {
        entry['truncated'] = true;
        continue;
      }
      final JsonMap item = switch (c.op) {
        'insert' => {
            'op': 'insert',
            'key': safeRow(c.key),
            'after': view.row(c.after!)
          },
        'delete' => {
            'op': 'delete',
            'key': safeRow(c.key),
            'before': view.row(c.before!)
          },
        _ => {
            'op': 'update',
            'key': safeRow(c.key),
            'changed': {
              for (final col in c.table.columns)
                if (jsonEncode(jsonSafe(c.before![col])) !=
                    jsonEncode(jsonSafe(c.after![col])))
                  col: {
                    'before': view.cell(c.before![col]),
                    'after': view.cell(c.after![col])
                  }
            }
          },
      };
      bytes += utf8.encode(jsonEncode(item)).length;
      shown++;
      rows.add(item);
    }
    return {
      'changedRows': changes.length,
      'tables': tables,
      if (changes.length > shown) 'shownRows': shown,
      if (changes.length > shown)
        'note':
            'Only a sample of rows is shown; counts are complete and the commit records every row for db.undo.',
    };
  }

  /// Events and refreshes after the data is durable. A failure here never
  /// undoes the commit; it is reported in `refreshed`.
  Future<JsonMap> _afterCommit(
      String commitId,
      String status,
      List<_Change> changes,
      List<int> affected,
      Map<String, Set<String>> entities,
      Invocation invocation,
      {String? undoes}) async {
    final tables = {for (final c in changes) c.table.name};
    final events = <JsonMap>[];
    for (final e in entities.entries) {
      for (final id in e.value.take(_eventsPerKind)) {
        BodySignals.changed('media.assets.changed', id, {
          'kind': e.key,
          'changedFields': tables.toList()..sort(),
          'source': undoes == null ? 'db.write' : 'db.undo',
          'commitId': commitId,
          'origin': invocation.origin,
        });
      }
      events.add({
        'event': 'media.assets.changed',
        'kind': e.key,
        'entities': e.value.length,
        if (e.value.length > _eventsPerKind) 'sent': _eventsPerKind,
      });
    }
    var refreshed = <String>[];
    try {
      refreshed = await afterCommit
              ?.call(DbCommitSummary(commitId, tables, entities)) ??
          [];
    } catch (error) {
      refreshed = ['failed: $error'];
    }
    return _commitResult(commitId, status, changes, affected, events, refreshed,
        undoes: undoes);
  }

  JsonMap _commitResult(String commitId, String status, List<_Change> changes,
      List<int> affected, List<JsonMap> events, List<String> refreshed,
      {String? undoes}) {
    return redactedOutput({
      'status': status,
      'committed': true,
      'commitId': commitId,
      if (undoes != null) 'undoes': undoes,
      'statements': [
        for (var i = 0; i < affected.length; i++)
          {'index': i, 'rowsAffected': affected[i]}
      ],
      ..._display(changes),
      'notified': events,
      'refreshed': refreshed,
      'undo': 'db.undo {"commitId":"$commitId","requestId":"undo:$commitId"}',
    });
  }

  Future<Map<String, Set<String>>> _entities(
      DatabaseExecutor db, List<_Change> changes) async {
    final result = <String, Set<String>>{
      'metadata': {},
      'artwork': {},
      'danmaku': {},
      'identity': {},
    };
    Future<void> viaObject(Object? objectId, Set<String> into) async {
      for (final r in await db.rawQuery(
          'SELECT DISTINCT entity_id FROM media_bindings WHERE object_id=?',
          [objectId])) {
        into.add(r['entity_id'] as String);
      }
    }

    Future<void> viaLocation(Object? locationId, Set<String> into) async {
      for (final r in await db.rawQuery(
          'SELECT file_id FROM media_locations WHERE id=?', [locationId])) {
        into.add(r['file_id'] as String);
      }
    }

    for (final c in changes) {
      final row = c.row;
      switch (c.table.name) {
        case 'media_overrides':
          final field = row['field'] as String;
          result[field.startsWith('artwork.') ||
                      field == 'imageUrl' ||
                      field == 'artworkUrls'
                  ? 'artwork'
                  : 'metadata']!
              .add(row['entity_id'] as String);
        case 'media_snapshots':
          await viaObject(row['object_id'], result['metadata']!);
          final text = '${c.before?['fields']}${c.after?['fields']}';
          if (text.contains('artworkUrls') || text.contains('imageUrl')) {
            await viaObject(row['object_id'], result['artwork']!);
          }
        case 'media_entities':
          result['identity']!.add(row['id'] as String);
        case 'media_bindings':
          result['identity']!.add(row['entity_id'] as String);
          result['metadata']!.add(row['entity_id'] as String);
        case 'media_evidence':
          for (final r in await db.rawQuery(
              'SELECT entity_id FROM media_bindings WHERE id=?',
              [row['binding_id']])) {
            result['identity']!.add(r['entity_id'] as String);
          }
        case 'media_file_episodes':
          result['identity']!
              .addAll([row['file_id'] as String, row['episode_id'] as String]);
        case 'media_locations' || 'media_file_aliases':
          result['identity']!.add(row['file_id'] as String);
        case 'media_classic_observations':
          await viaLocation(row['location_id'], result['identity']!);
        case 'media_classic_current':
          await viaLocation(row['location_id'], result['identity']!);
        case 'danmaku_bindings':
          result['danmaku']!.add(row['entity_id'] as String);
      }
    }
    result.removeWhere((_, ids) => ids.isEmpty);
    return result;
  }
}
