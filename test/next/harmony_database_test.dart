import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/db/harmony_migration.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('harmony-next-');
  });
  tearDown(() => root.delete(recursive: true));

  test('legacy RDB location matches the OHOS plugin mapping', () {
    expect(harmonyLegacyDatabasePath(
        '/data/storage/el2/base/files/flutter/nipaplay/next/next.db',
        '/data/storage/el2/database/rdb'),
        '/data/storage/el2/database/rdb/flutter/nipaplay/next/next.db');
  });

  test('migration preserves committed WAL data, version and the legacy database', () async {
    final legacyPath = '${root.path}/legacy.db';
    final target = '${root.path}/next.db';
    final writer = await databaseFactoryFfi.openDatabase(legacyPath,
        options: OpenDatabaseOptions(singleInstance: false));
    addTearDown(writer.close);
    await writer.rawQuery('PRAGMA journal_mode = WAL');
    await writer.execute('PRAGMA wal_autocheckpoint = 0');
    await writer.execute('CREATE TABLE preferences (value TEXT)');
    await writer.execute("INSERT INTO preferences VALUES ('saved')");
    await writer.setVersion(26);
    expect(await File('$legacyPath-wal').length(), greaterThan(0));
    // Recover from an earlier interrupted migration.
    await File('$target.migrating').writeAsString('partial copy');
    await migrateHarmonyNextDatabase(databasePath: target,
        legacyPath: legacyPath, factory: databaseFactoryFfi);
    final copy = await databaseFactoryFfi.openDatabase(target,
        options: OpenDatabaseOptions(singleInstance: false));
    try {
      expect(await copy.rawQuery('SELECT value FROM preferences'), [{'value': 'saved'}]);
      expect(await copy.getVersion(), 26);
      expect(await copy.rawQuery('PRAGMA quick_check'), [{'quick_check': 'ok'}]);
    } finally {
      await copy.close();
    }
    await writer.execute("UPDATE preferences SET value = 'later'");
    await migrateHarmonyNextDatabase(databasePath: target,
        legacyPath: legacyPath, factory: databaseFactoryFfi);
    final unchanged = await databaseFactoryFfi.openDatabase(target);
    try {
      expect(await unchanged.rawQuery('SELECT value FROM preferences'), [{'value': 'saved'}]);
    } finally {
      await unchanged.close();
    }
    expect(await File(legacyPath).exists(), isTrue);
    expect(await File('$target.migrating').exists(), isFalse);
  });

  test('a fresh installation has no legacy database to migrate', () async {
    final target = '${root.path}/next.db';
    await migrateHarmonyNextDatabase(databasePath: target,
        legacyPath: '${root.path}/absent.db', factory: databaseFactoryFfi);
    expect(await File(target).exists(), isFalse);
  });
}
