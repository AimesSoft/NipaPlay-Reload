import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/file_identity_merge.dart';
import 'package:nipaplay/next/capabilities/watched_history.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaFixture f;
  setUp(() async {
    f = MediaFixture();
    await f.open();
  });
  tearDown(() => f.close());

  test('HTTP history reuses source identity in either arrival order', () async {
    const url = 'http://localhost:1234/video/one';
    final first = await f.identities.ensureFile(url);
    final remote = await f.identities
        .ensureRemoteFile(url, 'shared', {'type': 'nipaplay'});
    expect(remote, first);
    await f.identities.importLegacy([
      {'filePath': url, 'animeName': ''}
    ]);
    expect(await f.identities.ensureFile(url), first);
    expect(await f.jobs.database.query('media_entities', where: "kind='file'"),
        hasLength(1));
    const secondUrl = 'http://localhost:1234/video/two';
    final second = await f.identities
        .ensureRemoteFile(secondUrl, 'shared', {'type': 'nipaplay'});
    await f.identities.importLegacy([
      {'filePath': secondUrl, 'animeName': ''}
    ]);
    expect(await f.identities.ensureFile(secondUrl), second);
  });

  test(
      'released duplicates merge atomically, retain observations, edits and old IDs; repeat does nothing',
      () async {
    const url = 'http://localhost:1234/video/duplicate';
    final old = await f.identities.ensureFile(url);
    await f.identities.importLegacy([
      {'filePath': url, 'animeName': ''}
    ]);
    final db = f.jobs.database;
    await db.update('media_entities', {'attributes': jsonEncode({'probe': {}, 'bindingRevision': 7})}, where:'id=?', whereArgs:[old]);
    await db.insert('media_projection_outbox', {'id':'old-projection','file_id':old,'file_revision':0,'binding_revision':7,'payload':'{"receipt":"keep"}','state':'delivered'});
    await db.insert('media_entities', {
      'id': 'source-file',
      'kind': 'file',
      'attributes': jsonEncode({
        'probe': {},
        'bindingRevision': 0,
        'remoteSource': {'type': 'nipaplay'}
      })
    });
    await db.insert('media_locations', {
      'id': 'source-location',
      'file_id': 'source-file',
      'source': 'shared',
      'owner_device_id': 'fixture-device',
      'locator': url,
      'available': 1
    });
    await db.insert('media_overrides', {
      'entity_id': old,
      'field': 'title',
      'value': '"我的片名"',
      'invocation_id': 'old-edit'
    });
    final observations = await db.query('media_classic_observations');
    final evidence = await db.query('media_legacy_history');
    await db
        .transaction((tx) => mergeLegacyRemoteFile(tx, 'fixture-device', url));
    expect(await f.identities.ensureFile(url), 'source-file');
    expect((await f.identities.entity(old))['id'], 'source-file');
    expect(((await f.identities.entity(old))['attributes'] as Map)['bindingRevision'], 7);
    expect((await db.query('media_projection_outbox')).single['payload'], '{"receipt":"keep"}');
    expect((await db.query('media_projection_outbox')).single['file_id'], 'source-file');
    expect(await db.query('media_classic_observations'), observations);
    expect(await db.query('media_legacy_history'), evidence);
    expect(
        (await db.query('media_overrides')).single['entity_id'], 'source-file');
    final aliases = await db.query('media_file_aliases');
    expect(
        (jsonDecode(aliases.single['archived'] as String) as Map)['entity']
            ['id'],
        old);
    final before = await db.rawQuery('SELECT total_changes() AS n');
    await db
        .transaction((tx) => mergeLegacyRemoteFile(tx, 'fixture-device', url));
    expect(await db.rawQuery('SELECT total_changes() AS n'), before);
    expect(await db.query('media_file_aliases'), aliases);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
      'different server scopes remain separate; legacy is not arbitrarily merged',
      () async {
    const url = 'http://localhost:1234/video/reused';
    await f.identities.ensureRemoteFile(url, 'jellyfin', {'serverId': 'one'});
    await f.identities.ensureRemoteFile(url, 'jellyfin', {'serverId': 'two'});
    await expectLater(f.identities.ensureFile(url), throwsA(isA<Failure>()));
  });

  test(
      'watched batch rolls back invalid files and preserves matching, extras and idempotence',
      () async {
    final db =
        await databaseFactoryFfi.openDatabase('${f.root.path}/classic-test.db');
    try {
      await db.execute(
          'CREATE TABLE watch_history(id INTEGER PRIMARY KEY,file_path TEXT,watch_progress REAL,last_position INTEGER,duration INTEGER,last_watch_time TEXT,anime_id INTEGER,thumbnail_path TEXT)');
      final id = await f.identities.ensureFile('${f.media.path}/one.mkv');
      final missing =
          await f.identities.ensureFile('${f.media.path}/missing.mkv');
      await db.insert('watch_history', {
        'id': 1,
        'file_path': '${f.media.path}/one.mkv',
        'watch_progress': .5,
        'last_position': 500,
        'duration': 1000,
        'last_watch_time': 'old',
        'anime_id': 12,
        'thumbnail_path': 'keep.png'
      });
      var notifications = 0;
      final service = WatchedHistory(() => f.service, () async => db, () async {
        notifications++;
      });
      final before = await db.query('watch_history');
      await expectLater(
          service.set([
            {'fileId': id, 'watched': true},
            {'fileId': missing, 'watched': false}
          ], Invocation(origin: 'gui')),
          throwsA(isA<Failure>()));
      expect(await db.query('watch_history'), before);
      await service.set([
        {'fileId': id, 'watched': true}
      ], Invocation(origin: 'gui'));
      final marked = (await db.query('watch_history')).single;
      expect(marked['watch_progress'], 1.0);
      expect(marked['last_position'], 1000);
      expect(marked['anime_id'], 12);
      expect(marked['thumbnail_path'], 'keep.png');
      expect(
          (await service.set([
            {'fileId': id, 'watched': true}
          ], Invocation(origin: 'harness_cli')))['changed'],
          0);
      expect(notifications, 1);
      await service.set([
        {'fileId': id, 'watched': false}
      ], Invocation(origin: 'harness_cli'));
      expect((await db.query('watch_history')).single['last_position'], 0);
    } finally {
      await db.close();
    }
  });
}
