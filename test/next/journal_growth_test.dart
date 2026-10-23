import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/state/activity_invocations.dart';

import 'support/main_thread_probe.dart';

/// The runtime's journal as Next configures it.
JsonlJournal _journal(File file) => nextJournal(file);

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Sized extends Action<_Json, _Json> {
  _Sized(String id, Effect effect, int items)
      : spec = ActionSpec(
            id: id,
            title: id,
            description: 'Fixture.',
            effect: effect,
            input: const ObjectSchema({}, additionalProperties: true),
            output: const ObjectSchema({}, additionalProperties: true)),
        _result = _Json({
          'items': [
            for (var i = 0; i < items; i++)
              {
                'id': '$id-$i',
                'title': '作品 $id $i',
                'year': 2000 + i % 26,
                'tags': ['tag-${i % 5}', 'tag-${i % 3}'],
                'poster': {'width': 300, 'height': 450, 'cached': i.isEven},
              }
          ]
        });
  @override
  final ActionSpec spec;
  final _Json _result;
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async =>
      Completed(_result);
}

final class _Fixture implements Capability {
  _Fixture(this.actions);
  @override
  final List<Action> actions;
}

void main() {
  test('what a session of reads and writes adds to journal.jsonl', () async {
    final root = await Directory.systemTemp.createTemp('journal-growth-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/journal.jsonl');
    // Result sizes and mix as in an old lab journal: the playback hook's
    // playback.state every two seconds, the UI's player_log, Nipa's
    // state.query/task.list/app.capabilities, a few writes.
    final workload = <(String, Effect, int, int)>[
      ('playback.state', Effect.read, 6, 400),
      ('diagnostics.player_log', Effect.read, 50, 300),
      ('state.query', Effect.read, 300, 100),
      ('app.capabilities', Effect.read, 900, 25),
      ('task.list', Effect.read, 1200, 10),
      ('media.library.works', Effect.read, 700, 5),
      ('ui.capture', Effect.read, 1, 10),
      ('media.identity.bind_batch', Effect.write, 4, 150),
    ];
    final actions = {
      for (final (id, effect, items, _) in workload) id: _Sized(id, effect, items)
    };
    final journal = _journal(file);
    final harness = Harness([_Fixture(actions.values.toList())],
        observers: [journal]);
    final order = [
      for (final (id, _, _, count) in workload)
        for (var i = 0; i < count; i++) id
    ];
    // Interleave deterministically.
    final calls = [
      for (var i = 0; i < order.length; i++) order[(i * 389) % order.length]
    ];
    final readWaits = <int>[], writeWaits = <int>[];
    final probe = MainThreadProbe.start();
    final clock = Stopwatch()..start();
    for (final id in calls) {
      final call = Stopwatch()..start();
      await harness.invokeJson(id, {'limit': 50, 'note': '弹幕'},
          Invocation(origin: 'harness_cli:chat:bench'));
      (actions[id]!.spec.effect == Effect.read ? readWaits : writeWaits)
          .add(call.elapsedMicroseconds);
    }
    clock.stop();
    probe.stop();
    await journal.drain();
    final bytes = file.lengthSync();
    double p50(List<int> values) =>
        (values..sort())[values.length ~/ 2] / 1000;
    // ignore: avoid_print
    print('${calls.length} invocations: journal ${(bytes / 1048576).toStringAsFixed(2)} MB '
        '(${(bytes / calls.length).toStringAsFixed(0)} B/invocation), '
        'wall ${clock.elapsedMilliseconds} ms, '
        'read p50 ${p50(readWaits).toStringAsFixed(2)} ms, '
        'write p50 ${p50(writeWaits).toStringAsFixed(2)} ms\n$probe');
    // Reads leave their results out (ui.capture, shown in 动态, keeps its own).
    expect(bytes, lessThan(calls.length * 1024));
    final lines = file.readAsLinesSync();
    expect(lines, hasLength(calls.length));
    expect(lines.where((line) => line.contains('"result"')), hasLength(160));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
