import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/ui_capability.dart';
import 'package:nipaplay/next/capabilities/ui_open.dart';

import '../media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'Mesh ui.open leaves resume to the source rather than an earlier snapshot',
      () async {
    final fixture = MediaFixture();
    await fixture.open();
    addTearDown(fixture.close);
    JsonMap? played;
    final api = Harness([
      UiCapability(
        media: () => fixture.service,
        resolveEntity: (_) async => {
          'episodeId': 'mesh-episode:one',
          'url': 'http://127.0.0.1/grant',
          'resumeMs': 120000,
        },
        play: (input, _) async {
          played = input;
          return const Completed(UiOpenValue({
            'path': 'mesh:///mesh-episode%3Aone',
            'state': {
              'kernel': {'layer': 'next_core'}
            }
          }));
        },
      )
    ]);
    final outcome = await api.invokeJson(
        'ui.open', {'entityId': 'mesh-episode:one'}, Invocation(origin: 'gui'));
    expect(outcome, isA<Completed>());
    expect(played, {'path': 'http://127.0.0.1/grant'});
  });

  test('source ui.open reports the observed player interface', () async {
    final fixture = MediaFixture();
    await fixture.open();
    try {
      for (final (result, expected) in <(JsonMap, String)>[
        (
          {
            'state': {
              'kernel': {'layer': 'next_core'}
            }
          },
          'next'
        ),
        (
          {
            'state': {'hasVideo': true}
          },
          'classic'
        ),
        ({'player': 'external'}, 'external_player'),
      ]) {
        final api = Harness([
          UiCapability(
            media: () => fixture.service,
            play: (_, __) async => Completed(UiOpenValue(result)),
          ),
        ]);
        final outcome = await api.invokeJson('ui.open',
            {'path': 'mesh:///peer-episode'}, Invocation(origin: 'test'));
        expect((outcome as Completed).value.toJson()['interface'], expected);
      }
    } finally {
      await fixture.close();
    }
  });
}
