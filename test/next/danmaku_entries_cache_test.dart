import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/source.dart';

import 'danmaku_test_support.dart';

DanmakuEntry _entry(int time, String text, {String? id}) => DanmakuEntry(
    sourceId: 'dandanplay',
    videoId: '7101',
    platform: 'dandanplay',
    sourceTimeMs: time,
    text: text,
    mode: 1,
    colorRgb: 0xffffff,
    sourceEntryId: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('entries are read once per content, deduplicated and sorted as before',
      () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final entity = await f.file();
    final store = f.service.store;
    final binding = await store.importEntries(
        entity,
        ddpVideo,
        [
          _entry(900, '晚', id: 'c'),
          _entry(100, '早', id: 'a'),
          _entry(500, '中', id: 'b'),
          _entry(100, '早', id: 'a'),
        ],
        '/fixture/one.xml',
        null,
        Invocation(origin: 'mcp'));
    final key = binding['cache_key'] as String;
    final first = await store.entries(key);
    expect(first.map((e) => e.text), ['早', '中', '晚']);

    // Kept for the same rows: not decoded again, and what a caller does with
    // its list does not reach the next caller.
    final again = await store.entries(key);
    for (var i = 0; i < first.length; i++) {
      expect(identical(again[i], first[i]), isTrue);
    }
    first.clear();
    expect((await store.entries(key)).map((e) => e.text), ['早', '中', '晚']);

    // A content file written since it was checked is read and checked again.
    final row = (await store.db.query('danmaku_cache_chunks',
            where: 'cache_key=?', whereArgs: [key]))
        .single;
    final file = File('${f.root.path}/${row['file_path']}');
    final bytes = await file.readAsBytes();
    await file.writeAsString('[]');
    await expectLater(store.entries(key), throwsA(isA<FormatException>()));
    await file.writeAsBytes(bytes);
    expect((await store.entries(key)).map((e) => e.text), ['早', '中', '晚']);

    // New content under the same binding is read.
    final replaced = await store.importEntries(entity, ddpVideo,
        [_entry(300, '换了', id: 'z')], '/fixture/two.xml', null,
        Invocation(origin: 'mcp'));
    expect((await store.entries(replaced['cache_key'] as String))
        .map((e) => e.text), ['换了']);
  });

  test('content that does not match its name is still refused', () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final entity = await f.file(path: '/fixture/tampered.mkv');
    final store = f.service.store;
    final binding = await store.importEntries(entity, ddpVideo,
        [_entry(42, '原文', id: 'only-this-test')], '/fixture/t.xml', null,
        Invocation(origin: 'mcp'));
    final key = binding['cache_key'] as String;
    final row = (await store.db.query('danmaku_cache_chunks',
            where: 'cache_key=?', whereArgs: [key]))
        .single;
    await File('${f.root.path}/${row['file_path']}')
        .writeAsString('[{"tampered":true}]');
    await expectLater(store.entries(key), throwsA(isA<FormatException>()));
    await expectLater(store.files.read(row), throwsA(isA<FormatException>()));
  });
}
