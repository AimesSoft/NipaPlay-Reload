import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/classic_action.dart';
import 'package:nipaplay/next/capabilities/family_descriptions.dart';
import 'package:nipaplay/next/mesh/runtime.dart';

void main() {
  test('family describes the receiving catalogue without unavailable actions',
      () async {
    late final Harness harness;
    harness = Harness([
      FamilyDescriptionCapability(() => harness.catalog),
      _Fixture(),
    ]);
    final result = (await harness.invokeJson('capability.describe',
            {'family': 'subtitle'}, Invocation(origin: 'fixture')))
        .toEnvelope();
    expect(result['status'], 'completed');
    final facts = result['result'] as Map;
    expect(facts['description'], contains('unavailable'));
    expect((facts['actions'] as List).map((item) => item['id']),
        ['subtitle.tracks']);
    expect(meshActionAllowed('capability.describe'), true);
    expect(meshActionAllowed('state.describe'), true);
    expect(meshActionAllowed('settings.set'), true);
    final missing = (await harness.invokeJson('capability.describe',
            {'family': 'download'}, Invocation(origin: 'fixture')))
        .toEnvelope();
    expect(missing['status'], 'failed');
  });
}

class _Fixture implements Capability {
  @override
  List<Action> get actions => [
        ClassicAction(
          const ActionSpec(
            id: 'subtitle.tracks',
            title: 'Tracks',
            description: 'Fixture',
            effect: Effect.read,
            input: ObjectSchema({}),
            output: ObjectSchema({}),
          ),
          (input, invocation) async => {},
        ),
      ];
}
