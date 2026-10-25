import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/turn_process_store.dart';

import 'support/main_thread_probe.dart';

/// Command output that reads like a build log, without secrets.
String output(Random random, int length) {
  const words = [
    'build', 'ok', 'src/main.dart', 'warning:', '下载', '完成', 'error', //
    '0x1f', 'line', 'value=42'
  ];
  final out = StringBuffer();
  while (out.length < length) {
    out
      ..write(words[random.nextInt(words.length)])
      ..write(random.nextBool() ? ' ' : '\n');
  }
  return out.toString().substring(0, length);
}

/// A turn as the single file of earlier versions kept it.
Map<String, dynamic> savedTurn(Random random, int t, int items, int length) => {
      'threadId': 'one',
      'turnId': 't$t',
      'origin': 'origin',
      'startedAt': '2026-10-23T00:00:00.000Z',
      'status': 'completed',
      'items': [
        {'id': 'u$t', 'type': 'userMessage', 'marker': true},
        for (var i = 0; i < items; i++)
          {
            'id': 'c$t-$i',
            'type': 'commandExecution',
            'status': 'completed',
            'startedAt': '2026-10-23T00:00:00.000Z',
            'endedAt': '2026-10-23T00:00:01.000Z',
            'command': 'cat file$i.txt',
            'exitCode': 0,
            'durationMs': 5,
            'aggregatedOutput': output(random, length),
          },
        {'id': 'a$t', 'type': 'agentMessage', 'marker': true},
      ],
      'endedAt': '2026-10-23T00:00:02.000Z',
      'durationMs': 2000,
    };

/// Codex's own history of [savedTurn]: its messages, under its own ids.
Map<String, dynamic> codexTurn(int t) => {
      'id': 't$t',
      'items': <Map>[
        {
          'id': 'item-u',
          'type': 'userMessage',
          'content': [
            {'type': 'text', 'text': '第 $t 句'}
          ]
        },
        {'id': 'item-a', 'type': 'agentMessage', 'text': '好的'},
      ]
    };

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  // The first isolate a test process starts compiles the machinery for it
  // (about 2 ms here); the app has started its line readers before.
  setUpAll(() => Isolate.run(() => 0));
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('tps-main-'));
  tearDown(() => root.delete(recursive: true));

  final now = DateTime.utc(2026, 10, 23);

  /// Sixty turns, ten 5 KB outputs each: about 3.7 MB in the single file.
  Future<List<Map<String, dynamic>>> legacyFile() async {
    final random = Random(1);
    final turns = [for (var t = 0; t < 60; t++) savedTurn(random, t, 10, 5000)];
    final file = TurnProcessStore.fileFor(root, 'harness');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(turns));
    expect(await file.length(), greaterThan(3 * 1024 * 1024));
    return turns;
  }

  test('opening on a 3 MB single file holds the main isolate under 5 ms, '
      'and moves every kept turn', () async {
    final turns = await legacyFile();
    final legacy = TurnProcessStore.fileFor(root, 'harness');
    final size = await legacy.length();
    await settle();
    final probe = MainThreadProbe.start();
    await settle();
    probe.mark('idle');
    final store = TurnProcessStore.forHarness(root, 'harness');
    await store.flush();
    probe.mark('open and move');
    probe.stop();
    // ignore: avoid_print
    print('open on a $size-byte single file:\n$probe');
    expect(probe.phases.last.$2, lessThan(5));
    expect(await legacy.exists(), isFalse);
    final directory = TurnProcessStore.directoryFor(root, 'harness');
    expect(directory.listSync().whereType<File>(), hasLength(60));
    for (final turn in turns) {
      expect(await store.read('one', turn['turnId'] as String), turn);
    }
    // Moved once: a second opening finds the same turns and no file to move.
    final again = TurnProcessStore.forHarness(root, 'harness');
    expect(await again.read('one', 't0'), turns.first);
    expect(directory.listSync().whereType<File>(), hasLength(60));
  }, retry: Platform.isWindows ? 2 : null);

  test('a 128-item turn of 8 KB outputs: each step under 2 ms, bytes written '
      'in proportion to the items', () async {
    final random = Random(2);
    final store = TurnProcessStore(Directory('${root.path}/facts'));
    await store.flush();
    void event(String method, Map<String, dynamic> params) =>
        store.observeRedacted(
            {'method': method, 'params': {'threadId': 'one', ...params}},
            'origin',
            now);
    Map<String, dynamic> command(int i, {String? out}) => {
          'id': 'c$i',
          'type': 'commandExecution',
          'command': 'cat out$i.txt',
          if (out != null) ...{
            'exitCode': 0,
            'durationMs': 5,
            'aggregatedOutput': out
          }
        };
    // Compiled and warm, as in a running app.
    event('turn/started', {
      'turn': {'id': 'warm'}
    });
    for (var i = 0; i < 8; i++) {
      event('item/completed',
          {'turnId': 'warm', 'item': command(i, out: output(random, 8192))});
    }
    await store.flush();
    final before = store.bytesWritten;
    final outputs = [for (var i = 0; i < 128; i++) output(random, 8192)];
    final steps = <double>[];
    await settle();
    final probe = MainThreadProbe.start();
    void timed(String method, Map<String, dynamic> params) {
      final watch = Stopwatch()..start();
      event(method, params);
      steps.add(watch.elapsedMicroseconds / 1000);
    }

    timed('turn/started', {
      'turn': {'id': 'big'}
    });
    await store.flush();
    for (var i = 0; i < 128; i++) {
      timed('item/started', {'turnId': 'big', 'item': command(i)});
      await store.flush();
      timed('item/completed',
          {'turnId': 'big', 'item': command(i, out: outputs[i])});
      await store.flush();
    }
    probe.mark('128 items');
    timed('turn/completed', {
      'turn': {'id': 'big', 'status': 'completed'}
    });
    await store.flush();
    probe.mark('completed, rewritten');
    probe.stop();
    final written = store.bytesWritten - before;
    final saved = (await store.read('one', 'big'))!;
    final folded = utf8.encode(jsonEncode(saved)).length;
    final sorted = [...steps]..sort();
    // ignore: avoid_print
    print('observe per step: median ${sorted[sorted.length ~/ 2].toStringAsFixed(3)} ms, '
        'max ${sorted.last.toStringAsFixed(3)} ms over ${steps.length} steps; '
        'written $written bytes for a $folded-byte turn\n$probe');
    expect(sorted.last, lessThan(2));
    // What else held it: collections, and starting the rewrite's isolate.
    expect(probe.longestMs, lessThan(16));
    expect(saved['items'], hasLength(128));
    expect(saved['status'], 'completed');
    // Each line once, and the finished turn rewritten once.
    expect(written, lessThan(3 * folded));
  }, retry: Platform.isWindows ? 2 : null);

  test('restoring 60 turns holds the main isolate under 5 ms', () async {
    final turns = await legacyFile();
    final store = TurnProcessStore.forHarness(root, 'harness');
    await store.flush();
    final history = [for (var t = 0; t < 60; t++) codexTurn(t)];
    await settle();
    final probe = MainThreadProbe.start();
    await settle();
    probe.mark('idle');
    await store.restoreAll('one', history);
    probe.mark('restore 60');
    probe.stop();
    // ignore: avoid_print
    print('restore 60 turns:\n$probe');
    expect(probe.phases.last.$2, lessThan(5));
    for (var t = 0; t < 60; t++) {
      final items = history[t]['items'] as List;
      expect(items.map((v) => v['id']), [
        'item-u',
        for (var i = 0; i < 10; i++) 'c$t-$i',
        'item-a',
      ]);
      expect(items[1], (turns[t]['items'] as List)[1]);
    }
  }, retry: Platform.isWindows ? 2 : null);

  test('a torn last line and a move cut short lose and double no turn',
      () async {
    final directory = TurnProcessStore.directoryFor(root, 'harness');
    final store = TurnProcessStore.forHarness(root, 'harness');
    void event(String method, Map<String, dynamic> params) => store.observe(
        {'method': method, 'params': {'threadId': 'one', ...params}},
        'origin',
        now);
    event('turn/started', {
      'turn': {'id': 'live'}
    });
    for (var i = 0; i < 3; i++) {
      event('item/completed', {
        'turnId': 'live',
        'item': {'id': 'c$i', 'type': 'commandExecution', 'command': 'ls $i'}
      });
    }
    await store.flush();
    // The app stopped part way through a line.
    final file = directory.listSync().whereType<File>().single;
    await file.writeAsString('{"item":{"id":"c3","ty', mode: FileMode.append);
    // And an earlier version's file came back, holding a turn already here.
    final legacy = TurnProcessStore.fileFor(root, 'harness');
    final old = savedTurn(Random(3), 9, 1, 100);
    await legacy.writeAsString(jsonEncode([
      old,
      {
        ...old,
        'turnId': 'live',
        'items': const [],
      }
    ]));
    final reopened = TurnProcessStore.forHarness(root, 'harness');
    reopened.observe({
      'method': 'item/completed',
      'params': {
        'threadId': 'one',
        'turnId': 'live',
        'item': {'id': 'c1', 'type': 'commandExecution', 'command': 'ls again'}
      }
    }, 'origin', now);
    await reopened.flush();
    final live = (await reopened.read('one', 'live'))!;
    expect((live['items'] as List).map((v) => v['command']),
        ['ls 0', 'ls again', 'ls 2']);
    expect(live['status'], 'inProgress');
    expect(await reopened.read('one', 't9'), old);
    expect(await legacy.exists(), isFalse);
    expect(directory.listSync().whereType<File>(), hasLength(2));
    expect(
        directory
            .listSync()
            .whereType<File>()
            .map((f) => f.readAsStringSync())
            .join(),
        isNot(contains('"c3"')));
  });

  test('without a store that writes, a saved turn reads the same', () async {
    final turns = await legacyFile();
    expect(await TurnProcessStore.readSaved(root, 'harness', 'one', 't7'),
        turns[7]);
    expect(
        await TurnProcessStore.readSaved(root, 'harness', 'one', 'nope'), isNull);
    final store = TurnProcessStore.forHarness(root, 'harness');
    await store.flush();
    expect(await TurnProcessStore.readSaved(root, 'harness', 'one', 't7'),
        turns[7]);
    expect(await TurnProcessStore.readSaved(root, 'harness', 'two', 't7'),
        isNull);
  });
}
