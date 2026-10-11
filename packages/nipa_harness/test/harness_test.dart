import 'package:nipa_harness/nipa_harness.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('registration', () {
    test('rejects duplicate action ids across capabilities', () {
      expect(
          () => Harness([
                FixtureCapability([FixtureAction()]),
                FixtureCapability([FixtureAction()]),
              ]),
          throwsArgumentError);
    });

    test('rejects invalid action ids', () {
      for (final id in [
        'single',
        '.open',
        'playback.',
        'Playback.open',
        'playback.Open',
        '1playback.open',
        'playback.1open',
        'playback..open',
        'playback.open-name',
        'playback.open\n'
      ]) {
        expect(
            () => Harness([
                  FixtureCapability([FixtureAction(id: id)])
                ]),
            throwsArgumentError,
            reason: id);
      }
    });

    test('catalog sorts ids and lookup returns registered action identity', () {
      final actions = [
        FixtureAction(id: 'z.last'),
        FixtureAction(id: 'a.middle_name.deep2'),
        FixtureAction(id: 'a.first'),
      ];
      final harness = Harness([FixtureCapability(actions)]);
      expect(harness.catalog.map((spec) => spec.id), [
        'a.first',
        'a.middle_name.deep2',
        'z.last',
      ]);
      expect(harness.lookup('z.last'), same(actions.first));
      expect(harness.lookup('missing.action'), isNull);
    });
  });

  group('invocation context', () {
    test('generated ids have the required shape and never repeat', () {
      final ids = List.generate(1000, (_) => Invocation(origin: 'gui').id);
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(id, matches(r'^inv-\d+-\d+$'));
      }
    });

    test('explicit id and origin are preserved', () {
      final invocation = Invocation(origin: 'mesh:device', id: 'custom');
      expect(invocation.id, 'custom');
      expect(invocation.origin, 'mesh:device');
    });
  });

  group('execution', () {
    test('unknown action fails before validation and does not notify observers',
        () async {
      final observer = RecordingObserver();
      final harness = Harness([], observers: [observer]);
      final outcome = await harness.invokeJson(
          'missing.action', ['invalid'], Invocation(origin: 'mcp'));
      expect((outcome as Failed).failure.code, FailureCode.notFound);
      expect(outcome.toEnvelope()['status'], 'failed');
      expect(observer.records, isEmpty);
    });

    test('null input executes as empty map while recording the original null',
        () async {
      final observer = RecordingObserver();
      JsonMap? decoded;
      final action = FixtureAction(onDecode: (json) {
        decoded = json;
        return FixtureJson(json);
      });
      final harness = Harness([
        FixtureCapability([action])
      ], observers: [
        observer
      ]);
      final result = await harness.invokeJson(
          action.spec.id, null, Invocation(origin: 'mcp'));
      expect(result, isA<Completed<JsonEncodable>>());
      expect(decoded, isEmpty);
      expect(observer.records.single.input, isNull);
    });

    test('invalid input reports all violations without decode or run',
        () async {
      var decodes = 0;
      var runs = 0;
      final action = FixtureAction(
        input: const ObjectSchema({
          'name': StringSchema(),
          'count': IntegerSchema(minimum: 1),
        }, required: [
          'name'
        ]),
        onDecode: (json) {
          decodes++;
          return FixtureJson(json);
        },
        onRun: (input, invocation) async {
          runs++;
          return const Completed(FixtureJson({'value': 'unexpected'}));
        },
      );
      final observer = RecordingObserver();
      final harness = Harness([
        FixtureCapability([action])
      ], observers: [
        observer
      ]);
      final input = {'count': 0, 'extra': true};
      final result = await harness.invokeJson(
          action.spec.id, input, Invocation(origin: 'mcp')) as Failed;
      expect(result.failure.code, FailureCode.invalidInput);
      expect(result.failure.violations.map((v) => v.path),
          ['/extra', '/name', '/count']);
      expect((result.failure.toJson()['violations'] as List), hasLength(3));
      expect(decodes, 0);
      expect(runs, 0);
      expect(observer.records.single.input, same(input));
      expect(observer.records.single.failureCode, FailureCode.invalidInput);
    });

    test('non-map inputs produce root violations and retain original input',
        () async {
      final observer = RecordingObserver();
      final action = FixtureAction();
      final harness = Harness([
        FixtureCapability([action])
      ], observers: [
        observer
      ]);
      final inputs = <Object?>[
        false,
        7,
        'bad',
        ['bad'],
        {7: 'non-string key'}
      ];
      for (final input in inputs) {
        final outcome = await harness.invokeJson(
            action.spec.id, input, Invocation(origin: 'mcp')) as Failed;
        expect(outcome.failure.code, FailureCode.invalidInput);
        expect(outcome.failure.violations.single.path, '');
        expect(observer.records.last.input, same(input));
      }
      expect(observer.records, hasLength(inputs.length));
    });

    test('validated input is decoded and run receives the same invocation',
        () async {
      final invocation = Invocation(origin: 'mcp', id: 'correlation');
      final action = FixtureAction(
        input:
            const ObjectSchema({'count': IntegerSchema()}, required: ['count']),
        onRun: (input, received) async {
          expect(received, same(invocation));
          expect(input.value, {'count': 2.0});
          return const Completed(FixtureJson({'value': 'counted'}));
        },
      );
      final harness = Harness([
        FixtureCapability([action])
      ]);
      expect(
          (await harness.invokeJson(action.spec.id, {'count': 2.0}, invocation))
              .toEnvelope(),
          {
            'status': 'completed',
            'result': {'value': 'counted'},
          });
    });

    test('typed invocation validates input and records input.toJson()',
        () async {
      final observer = RecordingObserver();
      final action = FixtureAction(
          input: const ObjectSchema({'count': IntegerSchema()},
              required: ['count']));
      final harness = Harness([
        FixtureCapability([action])
      ], observers: [
        observer
      ]);
      const input = FixtureJson({'count': 1});
      final outcome =
          await harness.invoke(action, input, Invocation(origin: 'gui'));
      expect(outcome, isA<Completed<FixtureJson>>());
      expect(observer.records.single.input, same(input.value));
      final invalid = await harness.invoke(
          action,
          const FixtureJson({'count': 'bad'}),
          Invocation(origin: 'gui')) as Failed;
      expect(invalid.failure.code, FailureCode.invalidInput);
      expect(observer.records, hasLength(2));
    });

    test('domain Failure is returned unchanged in both invocation paths',
        () async {
      const failure =
          Failure(FailureCode.unavailable, 'No video.', retryable: true);
      final action =
          FixtureAction(onRun: (input, invocation) async => throw failure);
      final harness = Harness([
        FixtureCapability([action])
      ]);
      final json = await harness.invokeJson(
          action.spec.id, {}, Invocation(origin: 'mcp')) as Failed;
      final typed = await harness.invoke(
          action, const FixtureJson({}), Invocation(origin: 'gui')) as Failed;
      expect(json.failure, same(failure));
      expect(typed.failure, same(failure));
      expect(json.toEnvelope(), {
        'status': 'failed',
        'error': {
          'code': 'unavailable',
          'message': 'No video.',
          'retryable': true
        },
      });
    });

    test('unexpected run exception becomes internal and is recorded', () async {
      final observer = RecordingObserver();
      final error = StateError('run failed');
      final action =
          FixtureAction(onRun: (input, invocation) async => throw error);
      final harness = Harness([
        FixtureCapability([action])
      ], observers: [
        observer
      ]);
      final outcome = await harness.invokeJson(
          action.spec.id, {}, Invocation(origin: 'mcp')) as Failed;
      expect(outcome.failure.code, FailureCode.internal);
      expect(outcome.failure.message, '${action.spec.id} failed: $error');
      expect(observer.records.single.failureCode, FailureCode.internal);
    });

    test('decoder exceptions pass through the Harness exception boundary',
        () async {
      const failure = Failure(FailureCode.conflict, 'Decode conflict.');
      for (final error in <Object>[failure, StateError('decode failed')]) {
        final action = FixtureAction(onDecode: (json) => throw error);
        final harness = Harness([
          FixtureCapability([action])
        ]);
        final outcome = await harness.invokeJson(
            action.spec.id, {}, Invocation(origin: 'mcp')) as Failed;
        if (error == failure) {
          expect(outcome.failure, same(failure));
        } else {
          expect(outcome.failure.code, FailureCode.internal);
          expect(outcome.failure.message, '${action.spec.id} failed: $error');
        }
      }
    });

    test('NeedsDecision envelope includes executable ActionCall options',
        () async {
      final target = FixtureAction(id: 'test.target');
      final call = ActionCall.of(target, const NoInput());
      final choice = FixtureAction(
          onRun: (input, invocation) async => NeedsDecision(
                Decision(prompt: 'Choose a target.', options: [
                  DecisionOption(
                      label: 'Target', detail: 'Recommended', call: call),
                  const DecisionOption(
                      label: 'Again', call: ActionCall('test.target', {})),
                ]),
              ));
      final harness = Harness([
        FixtureCapability([choice, target])
      ]);
      final result = await harness.invokeJson(
          choice.spec.id, {}, Invocation(origin: 'mcp'));
      expect(result.toEnvelope(), {
        'status': 'needs_decision',
        'decision': {
          'prompt': 'Choose a target.',
          'options': [
            {
              'label': 'Target',
              'detail': 'Recommended',
              'call': {'action': 'test.target', 'input': <String, Object?>{}}
            },
            {
              'label': 'Again',
              'call': {'action': 'test.target', 'input': <String, Object?>{}}
            },
          ],
        },
      });
      expect(
          await harness.invokeJson(
              call.actionId, call.input, Invocation(origin: 'mcp')),
          isA<Completed<JsonEncodable>>());
    });

    test(
        'records have exact JSON fields, UTC start time and elapsed milliseconds',
        () async {
      final observer = RecordingObserver();
      final action = FixtureAction(effect: Effect.write);
      final harness = Harness([
        FixtureCapability([action])
      ], observers: [
        observer
      ]);
      final before = DateTime.now().toUtc();
      await harness.invokeJson(
          action.spec.id, {}, Invocation(origin: 'gui', id: 'record-1'));
      final after = DateTime.now().toUtc();
      final record = observer.records.single;
      final startedAt = DateTime.parse(record.startedAt);
      expect(startedAt.isUtc, isTrue);
      expect(startedAt.isBefore(before), isFalse);
      expect(startedAt.isAfter(after), isFalse);
      expect(record.elapsedMs, greaterThanOrEqualTo(0));
      expect(record.toJson(), {
        'invocationId': 'record-1',
        'actionId': action.spec.id,
        'origin': 'gui',
        'effect': 'write',
        'input': <String, Object?>{},
        'status': 'completed',
        'startedAt': record.startedAt,
        'elapsedMs': record.elapsedMs,
        'result': {'value': 'done'},
      });
      await harness.invokeJson(
          action.spec.id, false, Invocation(origin: 'mcp'));
      expect(observer.records.last.toJson()['failureCode'], 'invalid_input');
      expect(observer.records.last.toJson()['status'], 'failed');
    });

    test('throwing observers are isolated and every observer is notified once',
        () async {
      final first = RecordingObserver();
      final throwing = ThrowingObserver();
      final last = RecordingObserver();
      final action = FixtureAction();
      final harness = Harness([
        FixtureCapability([action])
      ], observers: [
        first,
        throwing,
        last
      ]);
      final completed = await harness.invokeJson(
          action.spec.id, {}, Invocation(origin: 'mcp'));
      final invalid = await harness.invokeJson(
          action.spec.id, [], Invocation(origin: 'mcp'));
      expect(completed, isA<Completed<JsonEncodable>>());
      expect((invalid as Failed).failure.code, FailureCode.invalidInput);
      expect(throwing.calls, 2);
      expect(first.records, hasLength(2));
      expect(last.records, hasLength(2));
      expect(last.records.first, same(first.records.first));
      expect(last.records.last, same(first.records.last));
    });
  });

  test('failure wire names and omission of empty violations', () {
    expect(FailureCode.values.map((code) => code.wireName), [
      'invalid_input',
      'not_found',
      'unavailable',
      'conflict',
      'internal',
    ]);
    expect(const Failure(FailureCode.notFound, 'Missing.').toJson(), {
      'code': 'not_found',
      'message': 'Missing.',
      'retryable': false,
    });
    expect(
        const Failure(FailureCode.invalidInput, 'Invalid.',
            violations: [SchemaViolation('/path', 'Missing.')]).toJson(),
        {
          'code': 'invalid_input',
          'message': 'Invalid.',
          'retryable': false,
          'violations': [
            {'path': '/path', 'message': 'Missing.'}
          ],
        });
  });
}
