import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/db/service.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('existing database upgrades and receipts survive closing every connection', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('db-receipt-restart-');
    Database? database;
    try {
      database = await openNextDatabase(root, factory: databaseFactoryFfi);
      await database.insert('media_entities', {
        'id': 'work', 'kind': 'work', 'revision': 0,
        'attributes': '{"title":"Temporary work","localOnly":true}'
      });
      // Model the immediately preceding released schema, including real data.
      final version = await database.getVersion();
      await database.execute('DROP TABLE db_operations');
      await database.execute('DROP TABLE media_entity_aliases');
      await database.execute('DROP TABLE media_work_merges');
      await database.setVersion(23);
      await database.close();
      database = await openNextDatabase(root, factory: databaseFactoryFfi);
      expect(await database.getVersion(), version);
      const origin = 'mesh:temporary-caller';
      var service = DbService(database);
      final preview = await service.write({'statements': [
        {'sql': "UPDATE media_entities SET revision=revision+1 WHERE id='work'"}
      ]}, Invocation(origin: origin));
      final input = <String, Object?>{'previewId': preview['previewId']};
      final committed = await service.write(input, Invocation(origin: origin));
      await database.close();
      database = await openNextDatabase(root, factory: databaseFactoryFfi);
      service = DbService(database);
      final recovered = await service.receipt({'kind': 'write', 'requestKey': preview['previewId']}, Invocation(origin: origin));
      expect(recovered['state'], 'committed');
      expect(recovered['result'], committed);
      expect(await service.write(input, Invocation(origin: origin)), committed);
      final undo = <String, Object?>{'commitId': committed['commitId'], 'requestId': 'undo-once'};
      final undone = await service.undo(undo, Invocation(origin: origin));
      await database.close();
      database = await openNextDatabase(root, factory: databaseFactoryFfi);
      service = DbService(database);
      expect(await service.undo(undo, Invocation(origin: origin)), undone);
      expect(await database.query('db_commits'), hasLength(2));
      expect(await database.query('db_operations'), hasLength(2));
      expect((await database.query('media_entities')).single['revision'], 0);
    } finally {
      if (database?.isOpen == true) await database!.close();
      await root.delete(recursive: true);
    }
  });
}
