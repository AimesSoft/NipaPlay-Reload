import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/harness_redaction.dart';
import 'package:nipaplay/security/secret_redactor.dart';

/// A 50 KB command output the way `strings blob | grep token` produces it:
/// many `token` words, quotes that never pair, and a few real secrets.
String _noisy({required String secretA, required String secretB}) {
  final out = StringBuffer();
  var i = 0;
  while (out.length < 50 * 1024) {
    out.write('webToken: "unclosed value $i token=\' password: "x api_key:\n');
    out.write('refresh_token\' authorization: nothing token token token\n');
    i++;
  }
  out.write('\napi_key: "$secretA"\n');
  out.write('{"token":"$secretB"}\n');
  out.write('Authorization: Bearer abcdefghijklmnop123456\n');
  out.write('see https://user:hunter2@example.com/x and ftp://u:p@h/\n');
  out.write('cookie: sid=abc123\n');
  return out.toString();
}

int _micros(void Function() body) {
  final watch = Stopwatch()..start();
  body();
  return watch.elapsedMicroseconds;
}

void main() {
  const limit = Duration(milliseconds: 500); // typically a few ms.
  const secretA = 'AKIAREALKEYSHAPE0123456789abcdef';
  const secretB = 'tok_live_9f8e7d6c5b4a39281706';

  test('a 50 KB unpaired-quote text is redacted fast and completely', () {
    final text = _noisy(secretA: secretA, secretB: secretB);
    expect(text.length, greaterThan(50 * 1024));
    late String result;
    final micros = _micros(() => result = redactHarnessText(text));
    // ignore: avoid_print
    print('redactHarnessText 50KB: ${micros / 1000} ms');
    expect(micros, lessThan(limit.inMicroseconds));
    expect(result, isNot(contains(secretA)));
    expect(result, isNot(contains(secretB)));
    expect(result, isNot(contains('abcdefghijklmnop123456')));
    expect(result, isNot(contains('hunter2')));
    expect(result, isNot(contains('sid=abc123')));
    expect(result, contains('CredentialRef(diagnostic, secret)'));
  });

  test('an item/completed carrying 50 KB aggregatedOutput stays fast', () {
    final text = _noisy(secretA: secretA, secretB: secretB);
    final message = {
      'method': 'item/completed',
      'params': {
        'threadId': 't',
        'item': {
          'id': 'i',
          'type': 'commandExecution',
          'aggregatedOutput': text,
          'command': 'strings kernel_blob.bin | grep token',
        },
      },
    };
    late Map redacted;
    final micros = _micros(() => redacted = redactHarnessJson(message) as Map);
    // ignore: avoid_print
    print('redactHarnessJson 50KB item/completed: ${micros / 1000} ms');
    expect(micros, lessThan(limit.inMicroseconds));
    final output =
        (redacted['params'] as Map)['item']['aggregatedOutput'] as String;
    expect(output, isNot(contains(secretA)));
    expect(output, isNot(contains(secretB)));
    expect(output, isNot(contains('hunter2')));
  });

  test('the usual shapes of a secret are still replaced', () {
    String r(String s) => SecretRedactor.text(s);
    expect(r('token="abc def"'), isNot(contains('abc')));
    expect(r('token="abc def"'), isNot(contains('def')));
    expect(r("password: 'it\"s'"), isNot(contains('it')));
    expect(r('{"api_key": "k1xyz"}'), isNot(contains('k1xyz')));
    expect(r('token=abc&x=1'), 'token=CredentialRef(diagnostic, secret)&x=1');
    expect(r('a token: "multi\nline" b'), isNot(contains('multi')));
    expect(r('a token: "multi\nline" b'), isNot(contains('line')));
    // Quoted values past the ceiling are still cut at the first delimiter.
    final long = 'x' * 6000;
    expect(r('token: "$long"'), isNot(contains(long)));
    expect(r('token: "$long'), isNot(contains(long)));
    // Unclosed quote: the value up to the next delimiter goes.
    expect(r('token: "abc'), isNot(contains('abc')));
  });
}
