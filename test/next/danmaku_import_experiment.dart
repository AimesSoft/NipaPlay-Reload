import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/utils/danmaku_parser.dart';
import 'package:nipaplay/utils/danmaku_xml_utils.dart';
import 'package:nipaplay/utils/local_danmaku_file.dart';
import 'package:xml/xml.dart';

import 'danmaku_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('X7 read-only XML import compared with Classic local loading', () async {
    final path = Platform.environment['NIPAPLAY_X7_XML_COPY'];
    expect(path, isNotNull,
        reason: 'Set NIPAPLAY_X7_XML_COPY to a read-only copy.');
    final file = File(path!);
    final before = sha256.convert(await file.readAsBytes()).toString();
    final data = await readLocalDanmakuFile(XFile(path));
    final classic = parseDanmakuListInBackground(data['comments'] as List);
    final xml = XmlDocument.parse(await file.readAsString());
    final argb = xml.findAllElements('d').where((element) =>
        int.parse(element.getAttribute('p')!.split(',')[3]) > 0xffffff);
    expect(argb.length, 135);
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final entityId = await f.file();
    final outcome = await f.harness.invokeJson(
        'danmaku.import',
        {
          'filePath': path,
          'platform': 'youku',
          'platformVideoId': 'X7-experiment',
          'entityId': entityId,
        },
        Invocation(origin: 'mcp'));
    // ignore: avoid_print
    print('X7 Classic local parser: count=${classic.length}; sha256=$before');
    if (outcome is Failed) {
      // ignore: avoid_print
      print('X7 danmaku.import: ${outcome.failure.code.name}; '
          '${outcome.failure.message}');
    }
    expect(outcome, isA<Completed>());
    final result = (outcome as Completed).value.toJson();
    final id = result['bindingId'] as String;
    final binding = await f.service.store.binding(id);
    final saved = await f.service.store.entries(binding['cache_key'] as String);
    final chunk = (await f.jobs.database.query('danmaku_cache_chunks',
            where: 'cache_key = ?', whereArgs: [binding['cache_key']]))
        .single;
    final raw = [
      for (final row in await f.service.store.files.read(chunk))
        DanmakuEntry.fromJson(Map<String, Object?>.from(row as Map))
    ];
    expect(result['count'], classic.length);
    expect(result['loaded'], true);
    expect(saved, hasLength(classic.length));
    expect(raw, hasLength(classic.length));
    for (var i = 0; i < classic.length; i++) {
      final row = classic[i];
      expect(raw[i].sourceTimeMs, ((row['time'] as num) * 1000).round());
      expect(raw[i].text, row['content']);
      expect(raw[i].toPlayer()['type'], row['type']);
      expect(raw[i].colorRgb, parseDanmakuColorToInt(row['color']));
      expect(raw[i].platformId, row['platformDanmakuId']);
      expect(raw[i].sender, row['senderId']);
      expect(raw[i].fontSize, row['fontSize']);
      expect(raw[i].sentAt, row['timestamp']?.toString());
    }
    expect(f.player.data[id]!.length, classic.length);
    await f.reopen();
    await f.service.refreshCurrent();
    expect(f.player.data[id]!.map((e) => e.toJson()),
        saved.map((e) => e.toJson()));
    final unchanged =
        sha256.convert(await file.readAsBytes()).toString() == before;
    expect(unchanged, true);
    // ignore: avoid_print
    print(
        'X7 danmaku.import: count=${result['count']}; loaded=${result['loaded']}; '
        'cached=${saved.length}; all rows match Classic time/text/type/RGB/id/sender; '
        'restored=${f.player.data[id]!.length}; input unchanged=$unchanged; '
        'network requests=${f.host.requests.length}');
    // ignore: avoid_print
    print('X7 ARGB: input rows=${argb.length}; all 135 RGB values preserved');

    final malformed = File('${f.root.path}/malformed.xml');
    await malformed.writeAsString('<i><d');
    final beforeBinding = await f.service.store.binding(id);
    final beforeChunks = await f.jobs.database.query('danmaku_cache_chunks');
    final mounted = f.player.data[id];
    final rejected = await f.harness.invokeJson(
        'danmaku.import',
        {
          'filePath': malformed.path,
          'platform': 'youku',
          'platformVideoId': 'X7-experiment',
          'entityId': entityId,
        },
        Invocation(origin: 'mcp'));
    expect(rejected, isA<Failed>());
    final failure = (rejected as Failed).failure;
    expect(failure.code, FailureCode.invalidInput);
    expect(await f.service.store.binding(id), beforeBinding);
    expect(await f.jobs.database.query('danmaku_cache_chunks'), beforeChunks);
    expect(f.player.data[id], same(mounted));
    // ignore: avoid_print
    print('X7 malformed XML: ${failure.code.name}; ${failure.message}; '
        'previous binding/cache/mounted pool unchanged=true');
  });
}
