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

  int sizeOf(Directory directory) => directory
      .listSync()
      .whereType<File>()
      .fold(0, (total, file) => total + file.lengthSync());

  test('the files are the kept turns, oldest dropped past the size', () async {
    final directory = Directory('${root.path}/facts');
    final store = TurnProcessStore(directory, maxBytes: 6000);
    for (var t = 0; t < 8; t++) {
      turn(store, 't$t', [command('c$t', '输出 $t ' * (40 + t * 10))]);
    }
    await store.flush();
    // One file per kept turn, within the byte limit, newest kept, and each
    // kept turn read back as it was observed.
    final files = directory.listSync().whereType<File>().toList();
    expect(files.every((f) => f.path.endsWith('.jsonl')), isTrue);
    expect(sizeOf(directory), lessThanOrEqualTo(6000));
    final kept = [
      for (var t = 0; t < 8; t++)
        if (await store.read('one', 't$t') case final turn?) turn
    ];
    expect(kept, hasLength(files.length));
    expect(kept.last['turnId'], 't7');
    expect(kept.last['status'], 'completed');
    expect((kept.last['items'] as List).single['aggregatedOutput'],
        '输出 7 ' * 110);
    // The oldest went first: what is kept is the newest run of turns.
    final first = int.parse((kept.first['turnId'] as String).substring(1));
    expect([for (final turn in kept) turn['turnId']],
        [for (var t = first; t < 8; t++) 't$t']);
    expect(first, greaterThan(0));
    final reopened = TurnProcessStore(directory, maxBytes: 6000);
    for (final turn in kept) {
      expect(await reopened.read('one', turn['turnId'] as String), turn);
    }
    expect(await reopened.read('one', 't${first - 1}'), isNull);
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
    final directory = Directory('${root.path}/facts');
    final store = TurnProcessStore(directory);
    // Opened, so that what is measured is the observing itself.
    await store.flush();
    for (var i = 0; i < cases.length; i++) {
      final watch = Stopwatch()..start();
      turn(store, 'long$i', [command('c', cases[i])]);
      // ignore: avoid_print
      print('observe ${cases[i].length} chars: ${watch.elapsedMilliseconds} ms');
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      final kept = ((await store.read('one', 'long$i'))!['items'] as List)
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
    for (final file in directory.listSync().whereType<File>()) {
      expect(file.readAsStringSync(), isNot(contains(secret)));
    }
  });

  test('the live reader path and a direct caller both keep secrets out',
      () async {
    const secret = 'AKIAREALKEYSHAPE0123456789abcdef';
    final directory = Directory('${root.path}/facts');
    final store = TurnProcessStore(directory);
    await store.flush();
    Map<String, dynamic> event(String turn, String output) => {
          'method': 'item/completed',
          'params': {
            'threadId': 'one',
            'turnId': turn,
            'item': {
              'id': 'c',
              'type': 'commandExecution',
              'command': 'echo token=$secret',
              'aggregatedOutput': 'api_key: $secret',
            }
          }
        };
    for (final turn in ['live', 'safe']) {
      store.observe({
        'method': 'turn/started',
        'params': {
          'threadId': 'one',
          'turn': {'id': turn}
        }
      }, 'origin', now);
    }
    // The host publishes ChatLineReader's already-redacted map here.
    store.observeRedacted(
        Map<String, dynamic>.from(redactHarnessJson(event('live', '')) as Map),
        'origin',
        now);
    // Other callers still get the defensive redaction in observe.
    store.observe(event('safe', ''), 'origin', now);
    await store.flush();
    for (final turn in ['live', 'safe']) {
      final saved = jsonEncode(await store.read('one', turn));
      expect(saved, isNot(contains(secret)), reason: turn);
    }
  });

  test('many changes in a row end with the latest state on disk', () async {
    final directory = Directory('${root.path}/facts');
    final store = TurnProcessStore(directory);
    turn(store, 'busy', [
      for (var i = 0; i < 100; i++) command('c$i', 'line $i\n' * 50)
    ]);
    await store.flush();
    final saved = (await TurnProcessStore(directory).read('one', 'busy'))!;
    expect(saved, await store.read('one', 'busy'));
    expect((saved['items'] as List), hasLength(100));
    expect(saved['status'], 'completed');
  });
}
