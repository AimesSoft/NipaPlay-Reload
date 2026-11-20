import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/followups/service.dart';

/// #1122: EMPTY_RESPONSE must not be classified as a dropped stream or trigger
/// outer followup redeliveries (6 turns x 4 inner attempts = 24 requests).
void main() {
  test('Followups.isProviderHiccup excludes EMPTY_RESPONSE mapped to other',
      () {
    expect(
      Followups.isProviderHiccup({
        'message':
            'model "gpt-6.1-sol" returned a completed response with no content',
        'codexErrorInfo': 'other',
        'additionalDetails': 'EMPTY_RESPONSE',
      }),
      isFalse,
    );
    expect(
      Followups.isProviderHiccup({
        'message': 'stream closed unexpectedly',
        'codexErrorInfo': {'responseStreamDisconnected': {'httpStatusCode': null}},
        'additionalDetails': 'TRANSPORT',
      }),
      isTrue,
    );
    expect(
      Followups.isProviderHiccup({
        'message': 'rate limited (429)',
        'codexErrorInfo': {
          'responseTooManyFailedAttempts': {'httpStatusCode': 429}
        },
        'additionalDetails': 'RATE_LIMIT',
      }),
      isTrue,
    );
  });

  test('nipa-app-server turnError keeps EMPTY_RESPONSE out of stream disconnects',
      () async {
    final node = await Process.run('node', ['--version']);
    if (node.exitCode != 0) {
      markTestSkipped('node is not available on PATH');
      return;
    }
    final script = File('assets/next/agent/dsh/nipa-app-server.mjs').absolute;
    final result = await Process.run('node', [
      '--input-type=module',
      '-e',
      '''
import { turnError } from ${jsonEncode(script.uri.toString())};
console.log(JSON.stringify({
  empty: turnError({ code: 'EMPTY_RESPONSE', message: 'model "gpt-6.1-sol" returned a completed response with no content' }),
  transport: turnError({ code: 'TRANSPORT', message: 'connection reset' }),
  timeout: turnError({ code: 'TIMEOUT', message: 'timed out' }),
  idle: turnError({ code: 'LLM_STREAM_IDLE_TIMEOUT', message: 'idle timeout' }),
  rateLimit: turnError({ code: 'RATE_LIMIT', status: 429, message: 'too many requests' }),
}));
'''
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
    final empty = decoded['empty'] as Map<String, Object?>;
    expect(empty['codexErrorInfo'], 'other');
    expect(empty['additionalDetails'], 'EMPTY_RESPONSE');
    expect(Followups.isProviderHiccup(empty), isFalse);

    for (final key in ['transport', 'timeout', 'idle']) {
      final mapped = decoded[key] as Map<String, Object?>;
      expect(mapped['codexErrorInfo'], isA<Map>());
      expect((mapped['codexErrorInfo'] as Map).containsKey('responseStreamDisconnected'),
          isTrue,
          reason: key);
      expect(Followups.isProviderHiccup(mapped), isTrue, reason: key);
    }
    expect(Followups.isProviderHiccup(decoded['rateLimit']), isTrue);
  });
}
