import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/ui_capability.dart';
import 'package:nipaplay/next/capabilities/ui_open.dart';

import '../media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('source ui.open reports the observed player interface', () async {
    final fixture = MediaFixture();
    await fixture.open();
    try {
      for (final (result, expected) in <(JsonMap, String)>[
        ({'state': {'kernel': {'layer': 'next_core'}}}, 'next'),
        ({'state': {'hasVideo': true}}, 'classic'),
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
