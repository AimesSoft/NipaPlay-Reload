import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Invocation;
import 'package:nipaplay/next/memory/capability_changes.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/memory/recent.dart';

ActionSpec spec(String id,
        {String description = 'd', Map<String, Schema> input = const {}}) =>
    ActionSpec(
        id: id,
        title: id,
        description: description,
        effect: Effect.read,
        input: ObjectSchema(input),
        output: const ObjectSchema({}));

void main() {
  late Directory dir;
  late DateTime clock;
  late CapabilityCatalogChanges changes;
  var notified = 0;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('catalog_changes');
    clock = DateTime.utc(2026, 10, 22, 8);
    notified = 0;
    changes = CapabilityCatalogChanges(File('${dir.path}/c.json'),
        now: () => clock)
      ..onRecorded = () => notified++;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('first launch only stores; unchanged launch reports nothing', () async {
    final catalog = [spec('download.add'), spec('media.list')];
    expect(await changes.observe(catalog, appVersion: '1.0'), isNull);
    expect(await changes.observe(catalog, appVersion: '1.0'), isNull);
    expect(await changes.recent(), isEmpty);
    expect(notified, 0);
  });

  test('added, removed and re-described actions are recorded per family',
      () async {
    await changes.observe([
      spec('download.add'),
      spec('download.old'),
      spec('media.list'),
      spec('media.get', input: {'a': const StringSchema()}),
    ]);
    final record = await changes.observe([
      spec('download.add', description: 'now with http'),
      spec('download.preview'),
      spec('media.list'),
      spec('media.get', input: {'a': const StringSchema(), 'b': const StringSchema()}),
      spec('window.open'),
    ], appVersion: '1.2.3', build: '45');
    expect(record, isNotNull);
    final families = record!['families'] as Map;
    expect(families.keys.toSet(), {'download', 'media', 'window'});
    expect(families['download'], {
      'added': ['download.preview'],
      'removed': ['download.old'],
      'changed': ['download.add'],
      'descriptionChanged': false,
    });
    expect((families['media'] as Map)['changed'], ['media.get']);
    expect((families['window'] as Map)['familyAdded'], true);
    expect(record['appVersion'], '1.2.3');
    expect(notified, 1);
    // Same catalogue again: nothing more.
    expect(
        await changes.observe([
          spec('download.add', description: 'now with http'),
          spec('download.preview'),
          spec('media.list'),
          spec('media.get', input: {'a': const StringSchema(), 'b': const StringSchema()}),
          spec('window.open'),
        ]),
        isNull);
    expect(notified, 1);
    final line = CapabilityCatalogChanges.describe(record);
    expect(line, contains('2026-10-22 NipaPlay 1.2.3+45'));
    expect(line, contains('download 族：'));
    expect(line, contains('新增动作 download.preview'));
    expect(line, contains('移除动作 download.old'));
  });

  test('records expire after a week and only the newest two show', () async {
    var catalog = [spec('a.one')];
    await changes.observe(catalog);
    for (final id in ['a.two', 'a.three', 'a.four']) {
      clock = clock.add(const Duration(days: 1));
      catalog = [...catalog, spec(id)];
      await changes.observe(catalog);
    }
    final shown = await changes.recent();
    expect(shown, hasLength(2));
    expect(((shown.first['families'] as Map)['a'] as Map)['added'], ['a.four']);
    clock = clock.add(const Duration(days: 7));
    expect(await changes.recent(), isEmpty);
  });

  test('a damaged file is treated like a first launch', () async {
    await File('${dir.path}/c.json').writeAsString('{nope');
    expect(await changes.observe([spec('a.one')]), isNull);
    expect(await changes.observe([spec('a.one'), spec('a.two')]), isNotNull);
  });

  test('a large catalogue snapshot leaves the main isolate responsive',
      () async {
    final catalog = [
      for (var i = 0; i < 2000; i++)
        spec('family${i % 20}.action$i', input: {
          'value': StringSchema(description: 'field $i'),
          'count': IntegerSchema(minimum: 0, maximum: i + 1),
        })
    ];
    final ticks = <int>[];
    final clock = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
      ticks.add(clock.elapsedMilliseconds);
    });
    await changes.observe(catalog);
    timer.cancel();
    var longest = 0;
    for (var i = 1; i < ticks.length; i++) {
      final gap = ticks[i] - ticks[i - 1];
      if (gap > longest) longest = gap;
    }
    // ignore: avoid_print
    print('2000 catalogue actions in ${clock.elapsedMilliseconds} ms; '
        'longest main-isolate gap $longest ms');
    expect(ticks, isNotEmpty);
    expect(longest, lessThan(250));
  });

  test('the memory block lists them with a length limit', () async {
    final host = _NoSessions();
    final long = {
      'at': '2026-10-22T08:00:00.000Z',
      'appVersion': '1.0',
      'families': {
        'download': {
          'added': [for (var i = 0; i < 200; i++) 'download.action_number_$i'],
          'removed': <String>[],
          'changed': <String>[],
          'descriptionChanged': true,
        }
      }
    };
    final recent = await recentMemoryFacts(host, [], [], [], null,
        capabilityChanges: [long, long]);
    final text = recent['text'] as String;
    expect(text, contains('NipaPlay 更新：'));
    expect(text, contains('download 族：新增动作'));
    expect(text, contains('等 200 个'));
    expect(text, contains('族说明有改动'));
    expect(recent['truncated'], true);
    expect((recent['omitted'] as List).join(), contains('NipaPlay 更新'));
    final without = await recentMemoryFacts(host, [], [], [], null);
    expect(without['text'], isNot(contains('NipaPlay 更新')));
  });
}

/// A host with no conversations: only what recentMemoryFacts reads.
final class _NoSessions implements ConversationHistory {
  @override
  String? get mainThreadId => null;
  @override
  Map<String, String> get threadOrigins => {};
  @override
  Future<Map<String, dynamic>> listThreads(
          {String? cursor,
          int limit = 30,
          List<String>? sourceKinds,
          String? sortKey}) async =>
      {'data': [], 'nextCursor': null};
  @override
  Future<Map<String, dynamic>> readThread(String id,
          {bool withProcess = true}) async =>
      throw UnimplementedError();
}
