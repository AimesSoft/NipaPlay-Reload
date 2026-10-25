import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/danmaku/sidecar.dart';
import 'package:nipaplay/next/ui_data/heat.dart';
import 'package:nipaplay/utils/local_danmaku_match.dart';
import 'danmaku_test_support.dart';
import 'package:path/path.dart' as ppath;

void main() {
  late DanmakuFixture f;
  setUp(() async {
    f = DanmakuFixture();
    await f.open();
  });
  tearDown(() => f.close());

  test(
      'sidecar references refresh without copied content and retain controls when missing',
      () async {
    final path = ppath.join(f.root.path, 'episode.mkv');
    final id = await f.file(path: path);
    final xml = File(ppath.join(f.root.path, 'episode.xml'));
    Future<void> write(String text, int seconds) => xml
        .writeAsString(
            '<i><chatserver>youku</chatserver><chatid>opaque-youku-id</chatid>'
            '<d p="$seconds,1,25,16777215,1,0,sender,123">$text</d></i>')
        .then((_) {});
    await write('SIDE-CAR-TEXT-ONE', 1);
    final indexer = SidecarIndexer(f.service.store, () async {});
    expect(await indexer.inspect(id, path), isTrue);
    var b = (await f.service.store.bindings(id)).single;
    final key = b['cache_key'] as String;
    expect((b['local_file'] as Map)['platform'], 'youku');
    expect((b['local_file'] as Map)['platformVideoId'], 'opaque-youku-id');
    expect((b['local_file'] as Map)['count'], 1);
    expect(await f.service.store.db.query('danmaku_cache_chunks'), isEmpty);
    expect(jsonEncode(await f.service.store.db.query('danmaku_bindings')),
        isNot(contains('SIDE-CAR-TEXT')));
    expect(
        (await f.service.store.entries(key)).single.text, 'SIDE-CAR-TEXT-ONE');
    await f.service.refreshCurrent();
    final installs = f.player.installCount;
    await f.service.refreshCurrent();
    expect(f.player.installCount, installs);
    expect(f.player.managedTracks, {b['id']});
    final revision = b['revision'];
    await indexer.inspect(id, path);
    expect((await f.service.store.bindings(id)).single['revision'], revision);
    await f.call('danmaku.offset',
        {'bindingId': b['id'], 'revision': revision, 'offsetMs': 2000});
    await write('SIDE-CAR-TEXT-TWO-LONGER', 2);
    await indexer.inspect(id, path);
    b = (await f.service.store.bindings(id)).single;
    expect(b['id'], key.substring(8));
    expect(b['offset_ms'], 2000);
    expect((await f.service.store.entries(key)).single.text,
        'SIDE-CAR-TEXT-TWO-LONGER');
    await xml.delete();
    expect(await indexer.inspect(id, path), isFalse);
    b = (await f.service.store.bindings(id)).single;
    expect((b['local_file'] as Map)['available'], false);
    expect((b['local_file'] as Map)['readAt'], isNotNull);
    expect(b['cache_key'], isNull);
    await f.service.refreshCurrent();
    expect(f.player.managedTracks, isEmpty);
    await write('RETURNED', 3);
    await indexer.inspect(id, path);
    expect((await f.service.store.bindings(id)).single['id'], b['id']);
    expect((await f.service.store.bindings(id)).single['offset_ms'], 2000);
  });

  test(
      'explicit import of a discovered path replaces the pointer pool without a duplicate',
      () async {
    final path = ppath.join(f.root.path, 'episode.mkv');
    final id = await f.file(path: path);
    final xml = File(ppath.join(f.root.path, 'episode.xml'));
    await xml.writeAsString('<i><d p="1,1,25,16777215,1,0,s,1">before</d></i>');
    final indexer = SidecarIndexer(f.service.store, () async {});
    await indexer.inspect(id, path);
    final initial = (await f.service.store.bindings(id)).single;
    final result = await f.call('danmaku.import', {
      'entityId': id,
      'filePath': xml.path,
      'platform': 'local',
      'platformVideoId': xml.path
    });
    expect(result['bindingId'], initial['id']);
    await indexer.inspect(id, path);
    final binding = (await f.service.store.bindings(id)).single;
    expect(binding['local_file'], isNull);
    expect(
        (await f.service.store.entries(binding['cache_key'] as String))
            .single
            .text,
        'before');
    expect(await f.service.store.bindings(id), hasLength(1));
  });

  test('shared Classic ranking and parse fallback stay identical', () async {
    final path = ppath.join(f.root.path, 'episode.mkv');
    final id = await f.file(path: path);
    await File(ppath.join(f.root.path, 'episode.xml')).writeAsString('invalid');
    await File(ppath.join(f.root.path, 'episode.json')).writeAsString(
        '[{"time":1,"content":"valid","type":"scroll","color":16777215}]');
    await File(ppath.join(f.root.path, 'episode-comment.xml'))
        .writeAsString('invalid-too');
    final candidates = await localDanmakuCandidates(path);
    expect(candidates.map((p) => ppath.basename(p)),
        ['episode-comment.xml', 'episode.xml', 'episode.json']);
    final indexer = SidecarIndexer(f.service.store, () async {});
    await indexer.inspect(id, path);
    expect(
        ((await f.service.store.bindings(id)).single['local_file']
            as Map)['path'],
        ppath.join(f.root.path, 'episode.json'));
  });

  test(
      'episode heat uses saved timing facts after source removal without inventing text',
      () async {
    final path = ppath.join(f.root.path, 'episode.mkv');
    final id = await f.file(path: path);
    final xml = File(ppath.join(f.root.path, 'episode.xml'));
    await xml.writeAsString('<i><d p="1,1,25,16777215,1,0,s,1">text</d></i>');
    final indexer = SidecarIndexer(f.service.store, () async {});
    await indexer.inspect(id, path);
    // The entity itself also supports the same track projection as linked episodes.
    await xml.delete();
    expect(await EpisodeHeat(f.service.store).load(id, 60000), isNotNull);
    await indexer.inspect(id, path);
    expect(await EpisodeHeat(f.service.store).load(id, 60000), isNull);
  });
}
