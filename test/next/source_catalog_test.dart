import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media_sources/metadata.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/work_more.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('source refresh retains rich facts, edits and one file association', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('source-catalog-');
    final jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final store = IdentityStore(jobs.database, 'device');
    addTearDown(() async {
      await store.closeEvents();
      await jobs.database.close();
      await root.delete(recursive: true);
    });
    const source = 'jellyfin:home';
    final work = <String, Object?>{
      'id': 'show', 'kind': 'Series', 'name': '服务器标题', 'serverId': 'server',
      'metadata': {'Overview': '简介', 'Genres': ['动画'], 'People': [
        {'Name': '演员', 'Type': 'Actor', 'Role': '角色'},
      ], 'ProviderIds': {'Tmdb': '123'}},
    };
    final file = await store.ensureRemoteFile('jellyfin://episode', source,
        {'serverId': 'server', 'itemId': 'episode'});
    final episode = <String, Object?>{
      'id': 'episode', 'kind': 'Episode', 'name': '第一集', 'fileId': file,
      'serverId': 'server', 'metadata': {'SeriesId': 'show', 'SeriesName': '服务器标题',
        'SeasonId': 'season', 'IndexNumber': 1, 'ParentIndexNumber': 1},
    };
    final records = [...sourceCatalogRecords(source, work), ...sourceCatalogRecords(source, episode)];
    await store.observeSourceCatalog(records);
    final id = sourceCatalogId('work', source, 'show', serverId: 'server');
    final first = await store.mergedMetadata(id);
    expect((first['fields'] as Map)['overview'], '简介');
    expect((buildWorkMore(first)['cast'] as List).single['role'], '角色');
    expect((await store.identity(id))['entity'], isNotNull);
    final count = (await jobs.database.query('media_snapshots')).length;
    await store.observeSourceCatalog(records);
    expect((await jobs.database.query('media_snapshots')).length, count);
    await store.overrideField(id, 'title', '用户标题', Invocation(origin: 'gui'));
    await store.observeSourceCatalog(sourceCatalogRecords(source, {...work, 'name': '来源新标题'}));
    expect(((await store.mergedMetadata(id))['fields'] as Map)['title'], '用户标题');
    await store.observeSourceCatalog(sourceCatalogRecords(source, {...episode, 'id': 'alternative'}));
    expect((await jobs.database.query('media_file_episodes', where: 'file_id=?', whereArgs: [file])).length, 1);
    expect((await jobs.database.rawQuery("SELECT * FROM media_external_objects WHERE provider='tmdb'")), isEmpty);
    expect(sourceCatalogId('work', source, 'show', serverId: 'other'), isNot(id));
  });
}
