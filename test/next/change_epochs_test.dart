import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/db/epochs.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The change epoch is what tells the library and the interface that what
/// they are made of changed, so it must move for every write to a table
/// they read and for no other.
void main() {
  late Directory root;
  late Database db;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('epochs-');
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    await db.execute('PRAGMA foreign_keys = OFF');
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<int> epoch() async => (await db.rawQuery(
          "SELECT COALESCE((SELECT n FROM change_epochs WHERE name='catalogue'),0) AS n"))
      .single['n'] as int;

  // Values for columns whose type or CHECK a generic row cannot guess.
  const given = <String, Map<String, Object?>>{
    'followup_objects': {'kind': 'download'},
    'followups': {'snapshot': '{}'},
    'media_bindings': {'scope': '{}'},
    'media_snapshots': {'fields': '{}'},
    'media_entities': {'attributes': '{}', 'kind': 'work'},
  };

  /// A row of [table] with every required column filled.
  Future<Map<String, Object?>> row(String table) async {
    final values = <String, Object?>{};
    for (final column in await db.rawQuery('PRAGMA table_info($table)')) {
      final name = column['name'] as String;
      final type = (column['type'] as String).toUpperCase();
      if (column['notnull'] == 1 && column['dflt_value'] == null ||
          column['pk'] != 0) {
        values[name] = type.contains('INT') ? 1 : 'x';
      }
    }
    // A column checked against a list of words takes the first of them.
    final sql = (await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE name=?", [table]))
        .single['sql'] as String;
    for (final check in RegExp(r"(\w+)\s+IN\s*\(\s*'([^']+)'").allMatches(sql)) {
      if (values.containsKey(check[1])) values[check[1]!] = check[2];
    }
    return {...values, ...?given[table]};
  }

  Future<List<String>> tables() async => [
        for (final t in await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"))
          t['name'] as String
      ];

  test('every table of the schema says whether the library is built from it',
      () async {
    final all = {...await tables()};
    final named = [...catalogueTables, ...notCatalogueTables];
    expect(named.toSet().length, named.length, reason: 'a table is in both lists');
    expect(
        all.difference(named.toSet()).where((t) => t != 'sqlite_sequence'),
        isEmpty,
        reason: 'put each new table in catalogueTables or notCatalogueTables');
    expect(named.toSet().difference({...all, 'sqlite_sequence'}), isEmpty,
        reason: 'a listed table does not exist');
  });

  test('inserting, updating and deleting a row of a catalogue table moves the '
      'epoch, and of any other table does not', () async {
    for (final table in [...catalogueTables, ...notCatalogueTables]) {
      if (table == 'change_epochs' || table == 'sqlite_sequence') continue;
      final values = await row(table);
      final moves = catalogueTables.contains(table);
      Future<void> step(String what, Future<Object?> Function() run) async {
        final before = await epoch();
        await run();
        expect(await epoch() > before, moves,
            reason: '$what $table ${moves ? 'must' : 'must not'} move the epoch');
      }

      late int rowid;
      await step('inserting into', () async => rowid = await db.insert(table, values,
          nullColumnHack: (await db.rawQuery('PRAGMA table_info($table)')).first['name'] as String));
      // An update that writes the same value is still an update.
      final other = (await db.rawQuery('PRAGMA table_info($table)'))
          .where((c) => values.containsKey(c['name']))
          .map((c) => c['name'] as String)
          .firstOrNull;
      if (other != null) {
        await step(
            'updating',
            () => db.update(table, {other: values[other]},
                where: 'rowid=?', whereArgs: [rowid]));
      }
      await step('deleting from',
          () => db.delete(table, where: 'rowid=?', whereArgs: [rowid]));
    }
  });

  test('the library\'s own rows in ui_cache do not move it, the others do',
      () async {
    final before = await epoch();
    await db.insert('ui_cache',
        {'id': 'mesh:progress', 'fingerprint': 'a', 'payload': '{}'});
    await db.update('ui_cache', {'payload': '[]'}, where: "id='mesh:progress'");
    await db.delete('ui_cache', where: "id='mesh:progress'");
    expect(await epoch(), before);
    await db.insert('ui_cache',
        {'id': 'artwork:w', 'fingerprint': 'a', 'payload': '{}'});
    expect(await epoch(), greaterThan(before));
  });

  test('a write that rolls back leaves the epoch where it was', () async {
    final before = await epoch();
    final shelf = await row('ui_shelves');
    await expectLater(
        db.transaction((tx) async {
          await tx.insert('ui_shelves', shelf);
          throw StateError('rolled back');
        }),
        throwsStateError);
    expect(await epoch(), before);
  });

  test('a database from before the epochs gets them, and its rows are counted '
      'from there', () async {
    await db.close();
    final path = '${root.path}/next.db';
    final old = await databaseFactoryFfi.openDatabase(path);
    for (final table in catalogueTables) {
      for (final event in ['insert', 'update', 'delete']) {
        await old.execute('DROP TRIGGER IF EXISTS ${table}_epoch_$event');
      }
    }
    await old.execute('DROP TABLE change_epochs');
    await old.setVersion(20);
    await old.close();
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    expect(await epoch(), 0);
    await db.insert('ui_shelves', await row('ui_shelves'));
    expect(await epoch(), 1);
  });
}
