import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/harness_redaction.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/secret_redactor.dart';

void main() {
  test('chat deltas keep order and match whole-text redaction', () async {
    const token = 'sk-live-ABCDEFGHIJ';
    SecretRedactor.remember(const CredentialRef('test', 'chat-delta'), token);
    const deltas = [
      'first ',
      'sk-li',
      've-ABCD',
      'EFGHIJ',
      ' then password=hunter2',
      ' last'
    ];

    var previous = '';
    final published = <String>[];
    for (final delta in deltas) {
      final (safe, held) =
          await protectChatDeltaOffMain('$previous$delta', const {token});
      published.add(safe);
      previous = held;
    }
    published.add(previous);

    final joined = published.join();
    expect(joined, redactHarnessText(deltas.join()));
    expect(joined, isNot(contains(token)));
    expect(joined, isNot(contains('hunter2')));
    expect(joined, startsWith('first '));
    expect(joined, endsWith(' last'));
  });
}
