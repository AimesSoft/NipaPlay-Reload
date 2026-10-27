import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/classic_action.dart';
import 'package:nipaplay/next/state/change_history.dart';
import 'package:nipaplay/next/system/operation_observations.dart';

class _Capability implements Capability {
  _Capability(this.actions);
  @override
  final List<Action> actions;
}

void main() {
  test('process observations expire, page and bound records and stage history',
      () {
    var now = DateTime.utc(2026, 10, 28);
    final observed = OperationObservations(capacity: 2, clock: () => now);
    for (var i = 0; i < 3; i++) {
      observed.record('$i', 'routing', {'invocationId': '$i'});
    }
    var page = observed.read({'limit': 1});
    expect((page['records'] as List).single['invocationId'], '1');
    expect(page['truncated'], true);
    page = observed.read({'after': page['next']});
    expect((page['records'] as List).single['invocationId'], '2');
    for (var i = 0; i < 20; i++) {
      observed.record('2', 'step', {});
    }
    expect(
        ((observed.read({'invocationId': '2'})['records'] as List)
            .single['stages'] as List),
        hasLength(12));
    now = now.add(const Duration(minutes: 31));
    expect(observed.read({})['records'], isEmpty);
    expect(observed.read({})['absenceMeans'], 'unknown');
  });

  test(
      'a running action and returned failure remain correlated without secret parameters',
      () async {
    final entered = Completer<void>(), released = Completer<void>();
    final harness = Harness([
      InvocationScopeCapability(_Capability([
        ClassicAction(
            const ActionSpec(
                id: 'test.observe',
                title: 'test',
                description: 'test',
                effect: Effect.write,
                input: ObjectSchema({}, additionalProperties: true),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async {
          entered.complete();
          await released.future;
          throw const Failure(FailureCode.conflict, 'changed',
                details: {'reason': 'file_changed', 'invocationId': 'remote-request'});
        })
      ]))
    ]);
    final invocation = Invocation(origin: 'test');
    final pending = harness.invokeJson(
        'test.observe', {'secret': 'NEVER_RECORD_ME'}, invocation);
    await entered.future;
    JsonMap read() =>
        OperationObservations.current.read({'invocationId': invocation.id});
    expect((read()['records'] as List).single['stage'], 'action_started');
    released.complete();
    expect(await pending, isA<Failed>());
    final record = (read()['records'] as List).single;
    expect(record['stage'], 'action_failed');
    expect(record['reason'], 'file_changed');
    expect(record['invocationId'], invocation.id);
    expect(record['failureInvocationId'], 'remote-request');
    expect(record.containsKey('committed'), false);
    expect(jsonEncode(read()), isNot(contains('NEVER_RECORD_ME')));
  });

  test(
      'cursor loss and process changes are explicit, domain keys can be queried',
      () {
    final observed = OperationObservations(capacity: 2);
    observed.record('first', 'action_started', {'requestId': 'old'});
    final cursor = observed.read({});
    observed.record('second', 'action_started', {'previewId': 'preview-2'});
    observed.record('third', 'action_completed',
        {'commitId': 'commit-3', 'jobId': 'job-3'});
    observed.record('fourth', 'action_completed', {'requestKey': 'request-4'});
    final page =
        observed.read({'after': cursor['next'], 'session': cursor['session']});
    expect(page['historyGap'], true);
    expect(page['sessionChanged'], false);
    expect(
        (observed.read({'commitId': 'commit-3', 'jobId': 'job-3'})['records']
            as List),
        hasLength(1));
    expect((observed.read({'requestKey': 'request-4'})['records'] as List),
        hasLength(1));
    final reset =
        observed.read({'after': 10000, 'session': 'previous-process'});
    expect(reset['sessionChanged'], true);
    expect(reset['records'], hasLength(2));
    final empty = observed.read({'action': 'nothing'});
    expect(empty['next'], page['next']);
  });

  test('diagnostic polling never observes itself or consumes the cursor',
      () async {
    final harness = Harness(
        [InvocationScopeCapability(const OperationObservationsCapability())]);
    Future<JsonMap> read() async {
      final value = await harness.invokeJson(
          'diagnostics.operations', {}, Invocation(origin: 'test'));
      return (value as Completed).value.toJson();
    }

    final before = await read();
    for (var i = 0; i < 5; i++) {
      final after = await read();
      expect(after['next'], before['next']);
      expect(
          (after['records'] as List)
              .any((r) => r['action'] == 'diagnostics.operations'),
          false);
    }
  });
}
