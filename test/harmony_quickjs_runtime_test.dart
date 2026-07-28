import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/plugins/js_runtime_ohos.dart';

void main() {
  group('HarmonyQuickJsRuntimeAdapter', () {
    test('evaluates JavaScript and reports exceptions', () {
      final runtime = HarmonyQuickJsRuntimeAdapter();
      addTearDown(runtime.dispose);

      expect(runtime.evaluate('1 + 2'), '3');
      expect(
        runtime.evaluate(
          'JSON.stringify({language: "中文", supported: true})',
        ),
        '{"language":"中文","supported":true}',
      );
      expect(
        () => runtime.evaluate('throw new Error("boom")'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('boom'),
          ),
        ),
      );
    });

    test('routes synchronous bridge calls to the owning runtime', () {
      final first = HarmonyQuickJsRuntimeAdapter();
      final second = HarmonyQuickJsRuntimeAdapter();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      first.setupBridge('PluginBridge', (args) {
        return (args['value'] as int) + 1;
      });
      second.setupBridge('PluginBridge', (args) {
        return (args['value'] as int) + 2;
      });

      const script = 'sendMessage("PluginBridge", JSON.stringify({value: 40}))';
      expect(first.evaluate(script), '41');
      expect(second.evaluate(script), '42');
    });
  });
}
