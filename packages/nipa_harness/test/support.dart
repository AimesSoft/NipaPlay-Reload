import 'package:nipa_harness/nipa_harness.dart';

final class FixtureJson implements JsonEncodable {
  const FixtureJson(this.value);

  final JsonMap value;

  @override
  JsonMap toJson() => value;
}

final class FixtureAction extends Action<FixtureJson, FixtureJson> {
  FixtureAction({
    String id = 'test.echo',
    Effect effect = Effect.read,
    ObjectSchema input = const ObjectSchema({}),
    ObjectSchema output = const ObjectSchema(
      {'value': StringSchema()},
      required: ['value'],
    ),
    this.onRun,
    this.onDecode,
  }) : spec = ActionSpec(
          id: id,
          title: 'Test action',
          description: 'Execute the test action.',
          effect: effect,
          input: input,
          output: output,
        );

  @override
  final ActionSpec spec;
  final Future<Outcome<FixtureJson>> Function(FixtureJson, Invocation)? onRun;
  final FixtureJson Function(JsonMap)? onDecode;

  @override
  FixtureJson decodeInput(JsonMap json) =>
      onDecode == null ? FixtureJson(json) : onDecode!(json);

  @override
  Future<Outcome<FixtureJson>> run(
    FixtureJson input,
    Invocation invocation,
  ) async =>
      onRun == null
          ? const Completed(FixtureJson({'value': 'done'}))
          : onRun!(input, invocation);
}

final class FixtureCapability implements Capability {
  FixtureCapability(this.actions);

  @override
  final List<Action> actions;
}

final class RecordingObserver implements InvocationObserver {
  final records = <InvocationRecord>[];

  @override
  void onInvocation(InvocationRecord record) => records.add(record);
}

final class ThrowingObserver implements InvocationObserver {
  int calls = 0;

  @override
  void onInvocation(InvocationRecord record) {
    calls++;
    throw StateError('observer failed');
  }
}
