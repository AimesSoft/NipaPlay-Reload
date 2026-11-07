import 'dart:async';

// sqflite's factory adapter keeps SQL on its existing database executor. These
// implementation exports are isolated here; no database objects cross isolates.
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/mixin/import_mixin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'epochs.dart';

/// Process-local committed catalogue notifications, keyed by database path.
/// Other isolates explicitly forward their notifications through a SendPort.
abstract final class CatalogueChanges {
  static final _changes = StreamController<String>.broadcast();
  static Stream<void> forPath(String path) =>
      _changes.stream.where((p) => p == path).map((_) {});
  static void committed(String path) => _changes.add(path);
}

abstract final class InboxChanges {
  static final _changes = StreamController<String>.broadcast();
  static Stream<void> forPath(String path) =>
      _changes.stream.where((p) => p == path).map((_) {});
  static void committed(String path) => _changes.add(path);
}

/// Reads the trigger-maintained epoch only after a write/commit, never on a
/// clock. Transaction rollbacks and writes to derived mesh rows do not notify.
final class NotifyingDatabaseFactory {
  NotifyingDatabaseFactory(DatabaseFactory delegate, this.onChange)
      : _delegate = delegate as SqfliteInvokeHandler {
    factory = buildDatabaseFactory(invokeMethod: _invoke);
  }
  final SqfliteInvokeHandler _delegate;
  final void Function() onChange;
  late final DatabaseFactory factory;
  int? _id;
  int _epoch = 0;
  bool _transaction = false, _dirty = false;

  Future<void> observe(Database db) async {
    _epoch = (await db.rawQuery(_epochSql)).single['n'] as int;
    _id = (db as SqfliteDatabaseMixin).id;
  }

  static const _epochSql =
      "SELECT COALESCE((SELECT n FROM change_epochs WHERE name='catalogue'),0) AS n";
  static final _catalogueTable =
      RegExp('\\b(${catalogueTables.join('|')})\\b', caseSensitive: false);

  bool _writesCatalogue(String method, Map arguments) {
    if (method == 'query') return false;
    if (method == 'batch') {
      return (arguments['operations'] as List)
          .any((op) => _writesCatalogue((op as Map)['method'] as String, op));
    }
    return const {'insert', 'update', 'execute'}.contains(method) &&
        _catalogueTable.hasMatch(arguments['sql'] as String? ?? '');
  }

  Future<Object?> _invoke(String method, [Object? arguments]) async {
    final result = await _delegate.invokeMethod<Object?>(method, arguments);
    if (_id == null || arguments is! Map || arguments['id'] != _id) {
      return result;
    }
    final sql = (arguments['sql'] as String? ?? '').trimLeft().toUpperCase();
    if (arguments['inTransaction'] == true) _transaction = true;
    if (_writesCatalogue(method, arguments)) {
      _dirty = true;
    }
    if (arguments['inTransaction'] == false) {
      _transaction = false;
      if (sql.startsWith('ROLLBACK')) _dirty = false;
    }
    if (!_transaction && _dirty) {
      _dirty = false;
      // Invoke below the adapter so this read cannot recurse or take the
      // database's Dart lock while the write still owns it.
      final epoch = await _delegate.invokeMethod<Object?>(
          'query', {'id': _id, 'sql': _epochSql, 'arguments': <Object?>[]});
      final int next;
      if (epoch is Map) {
        next = ((epoch['rows'] as List).single as List).single as int;
      } else {
        next = ((epoch as List).single as Map)['n'] as int;
      }
      if (next != _epoch) {
        _epoch = next;
        onChange();
      }
    }
    return result;
  }
}
