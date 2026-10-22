import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/turn_process_store.dart';
import 'package:nipaplay/next/harness_redaction.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('tps-cost-'));
  tearDown(() => root.delete(recursive: true));

  final now = DateTime.utc(2026, 10, 23);
  void turn(TurnProcessStore store, String id, List<Map> items) {
    store.observe({
      'method': 'turn/started',
      'params': {
        'threadId': 'one',
        'turn': {'id': id}
      }
    }, 'origin', now);
    for (final item in items) {
      for (final method in ['item/started', 'item/completed']) {
        store.observe({
          'method': method,
          'params': {'threadId': 'one', 'turnId': id, 'item': item}
        }, 'origin', now);
      }
    }
    store.observe({
      'method': 'turn/completed',
      'params': {
        'threadId': 'one',
        'turn': {'id': id, 'status': 'completed'}
      }
    }, 'origin', now);
  }

  Map command(String id, String output) => {
        'id': id,
        'type': 'commandExecution',
        'command': 'cat out.txt',
        'exitCode': 0,
        'durationMs': 5,
        'aggregatedOutput': output
      };

  test('the file is the JSON of the kept turns, oldest dropped past the size',
      () async {
    final file = File('${root.path}/facts.json');
    final store = TurnProcessStore(file, maxBytes: 6000);
    for (var t = 0; t < 8; t++) {
      turn(store, 't$t', [command('c$t', '输出 $t ' * (40 + t * 10))]);
    }
    await store.flush();
    final text = file.readAsStringSync();
    final turns = jsonDecode(text) as List;
    // The same bytes jsonEncode wrote before, within the byte limit, newest
    // kept, and each kept turn as it was observed.
    expect(text, jsonEncode(turns));
    expect(utf8.encode(text).length, lessThanOrEqualTo(6000));
    expect(turns.last['turnId'], 't7');
    for (final kept in turns) {
      expect(store.read('one', kept['turnId'] as String), kept);
    }
    // One more turn would not fit beside the oldest kept one.
    final dropped = turns.first['turnId'] as String;
    final older = 't${int.parse(dropped.substring(1)) - 1}';
    expect(store.read('one', older), isNull);
    expect(TurnProcessStore(file).read('one', 't7'), store.read('one', 't7'));
  });

  test('a long output keeps the same redacted start, at a bounded cost',
      () async {
    const secret = 'AKIAREALKEYSHAPE0123456789abcdef';
    final cases = <String>[
      // A secret inside what is kept, one across the limit, one far past it.
      '${'x' * 4000} api_key: "$secret" ${'y' * 3000}token=$secret${'z' * 2000000}',
      '${'行' * 8180} password=$secret ${'尾' * 500000}',
      '${'a' * 8190}Bearer abcdefghijklmnop123456 ${'b' * 300000}',
      'short token=$secret',
    ];
    final file = File('${root.path}/facts.json');
    final store = TurnProcessStore(file);
    for (var i = 0; i < cases.length; i++) {
      final watch = Stopwatch()..start();
      turn(store, 'long$i', [command('c', cases[i])]);
      // ignore: avoid_print
      print('observe ${cases[i].length} chars: ${watch.elapsedMilliseconds} ms');
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      final kept = (store.read('one', 'long$i')!['items'] as List)
          .single['aggregatedOutput'] as String;
      final whole = redactHarnessText(cases[i]);
      final expected = whole.runes.length <= 8192
          ? whole
          : '${String.fromCharCodes(whole.runes.take(8192))}…';
      expect(kept, expected);
      expect(kept, isNot(contains(secret)));
      expect(kept, isNot(contains('abcdefghijklmnop123456')));
    }
    await store.flush();
    expect(file.readAsStringSync(), isNot(contains(secret)));
  });

  test('many changes in a row end with the latest state on disk', () async {
    final file = File('${root.path}/facts.json');
    final store = TurnProcessStore(file);
    turn(store, 'busy', [
      for (var i = 0; i < 100; i++) command('c$i', 'line $i\n' * 50)
    ]);
    await store.flush();
    final saved = TurnProcessStore(file).read('one', 'busy')!;
    expect(saved, store.read('one', 'busy'));
    expect((saved['items'] as List), hasLength(100));
    expect(saved['status'], 'completed');
  });
}
