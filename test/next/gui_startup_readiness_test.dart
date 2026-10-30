import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Invocation;
import 'package:nipa_harness/nipa_harness.dart' as h show Invocation;
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/data/search.dart';

void main() {
  test('startup inbox calls wait for publication instead of reporting failure', () async {
    final ready = Completer<Harness>();
    final action = _Read('ui.inbox.list', {'items': <Object?>[]});
    final reading = GuiCalls(() => ready.future).call('ui.inbox.list', {});
    await Future<void>.delayed(Duration.zero);
    expect(action.calls, 0);
    ready.complete(Harness([_Capability(action)]));
    expect((await reading)['items'], isEmpty);
    expect(action.calls, 1);
    expect(action.lastOrigin, 'gui');
  });

  test('search accepts a catalogue still being initialized', () async {
    final ready = Completer<Harness>();
    final action = _Read('media.library.search_merged', {});
    final reading = CoreSearch(() => ready.future).library('test');
    await Future<void>.delayed(Duration.zero);
    expect(action.calls, 0);
    ready.complete(Harness([_Capability(action)]));
    expect((await reading).works, isEmpty);
    expect(action.calls, 1);
  });

  test('search still accepts an already published catalogue', () async {
    final action = _Read('media.library.search_merged', {});
    final harness = Harness([_Capability(action)]);
    expect((await CoreSearch(() => harness).library('test')).works, isEmpty);
    expect(action.calls, 1);
  });

  test('startup failures retain the original failure for the viewer', () async {
    final ready = Completer<Harness>();
    const failure = Failure(FailureCode.unavailable, 'catalogue startup failed');
    final checked = expectLater(
        GuiCalls(() => ready.future).call('ui.inbox.list', {}),
        throwsA(same(failure)));
    ready.completeError(failure, StackTrace.current);
    await checked;
  });
}

final class _Capability implements Capability {
  _Capability(this.action);
  final _Read action;
  @override
  List<Action> get actions => [action];
}

final class _Json implements JsonEncodable {
  _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Read extends Action<_Json, _Json> {
  _Read(this.id, this.answer);
  final String id;
  final JsonMap answer;
  int calls = 0;
  String? lastOrigin;
  @override
  ActionSpec get spec => ActionSpec(
      id: id,
      title: id,
      description: 'Read through the published startup catalogue.',
      effect: Effect.read,
      input: const ObjectSchema({}, additionalProperties: true),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap input) => _Json(input);
  @override
  Future<Outcome<_Json>> run(_Json input, h.Invocation invocation) async {
    calls++;
    lastOrigin = invocation.origin;
    return Completed(_Json(answer));
  }
}
