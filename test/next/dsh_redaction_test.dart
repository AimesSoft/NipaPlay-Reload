import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/dsh_runtime.dart';
import 'package:nipaplay/next/headless/vault.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/secret_redactor.dart';

/// #1119: a tool that printed a credential (a `cat` of the headless vault)
/// handed it to the model. DSH's bridge now hides what NipaPlay knows to be
/// secret before the model or the session log sees a tool's result, and
/// refuses calls that name the vault.
Future<Map<String, Object?>> _node(String body) async {
  final script =
      File('assets/next/agent/dsh/nipa-app-server.mjs').absolute.uri.toString();
  final result = await Process.run('node', [
    '--input-type=module',
    '-e',
    "import * as bridge from ${jsonEncode(script)};\n$body"
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, Object?>;
}

void main() {
  final node = Process.runSync('node', ['--version']).exitCode == 0;

  test('tool output: every form of a known secret is hidden, nothing else',
      () async {
    final out = await _node(r'''
const r = new bridge.Redactions();
r.remember(['sk-live-0123456789abcdef', 'x', 'abc', 'p4ss', 'http', '密码', 'n!', 42, 'p@ss w/ord+1234']);
const text = (t) => r.text(t);
console.log(JSON.stringify({
  plain: text('key=sk-live-0123456789abcdef\n'),
  json: text('{"secret":"p@ss w\/ord+1234"}'),
  url: text('https://x/?k=' + encodeURIComponent('p@ss w/ord+1234')),
  tiny: text('x marks the spot'),
  short: text('pw=p4ss'),
  word: text('abc, but not abcdef'),
  inside: text('see https://example.org'),
  escaped: text('{"out":"\\np4ss"}'),
  encodedAlone: text('https://x/?p=' + encodeURIComponent('密码')),
  encodedInside: text('https://x/' + encodeURIComponent('密码重置')),
  escapedSpace: text('{"out":"\\u00a0p4ss"}'),
  encodedStop: text('https://x/?p=' + encodeURIComponent('密码。')),
  encodedLetter: text('https://x/' + encodeURIComponent('密码') + '%61'),
  insideEscape: text('{"out":"\\n!"}'),
  untouched: text('nothing here'),
  size: r.size,
}));
''');
    expect(out['plain'], 'key=${'[已隐去的凭据]'}\n');
    expect(out['json'], isNot(contains('ord+1234')));
    expect(out['url'], isNot(contains('ord%2B1234')));
    // A short password is hidden where it stands alone (#1119 review), not
    // inside a longer word: a password `http` leaves `https://` whole. One
    // character cannot be told from text.
    expect(out['short'], 'pw=${'[已隐去的凭据]'}');
    expect(out['word'], '${'[已隐去的凭据]'}, but not abcdef');
    expect(out['inside'], 'see https://example.org');
    expect(out['tiny'], 'x marks the spot');
    // After a JSON escape (`\n`) it still stands alone; encoded, a short
    // secret is still short, and the bytes of a following letter join it.
    expect(out['escaped'], isNot(contains('p4ss')));
    expect(out['encodedAlone'], 'https://x/?p=${'[已隐去的凭据]'}');
    expect(out['encodedInside'],
        'https://x/${Uri.encodeComponent('密码重置')}');
    // Neighbours are read as what they stand for: `\u00a0` is a space,
    // `%E3%80%82` a full stop, `%61` the letter a; and `\n!` is a newline
    // and `!`, not the secret `n!`.
    expect(out['escapedSpace'], isNot(contains('p4ss')));
    expect(out['encodedStop'],
        'https://x/?p=${'[已隐去的凭据]'}${Uri.encodeComponent('。')}');
    expect(out['encodedLetter'],
        'https://x/${Uri.encodeComponent('密码')}%61');
    expect(out['insideEscape'], r'{"out":"\n!"}');
    expect(out['untouched'], 'nothing here');
  }, skip: node ? false : 'node is not on PATH');

  test('post-execute: success, failure, value and block decisions', () async {
    final out = await _node(r'''
const r = new bridge.Redactions();
r.remember(['sk-live-0123456789abcdef']);
const leak = [{ type: 'text', text: 'TOKEN=sk-live-0123456789abcdef' }, { type: 'image', data: 'x' }];
const ok = { isError: false, value: null, content: leak };
const failed = { isError: true, error: { message: 'curl: sk-live-0123456789abcdef' }, content: leak };
const clean = { isError: false, value: null, content: [{ type: 'text', text: 'fine' }] };
const accept = { kind: 'accept' };
console.log(JSON.stringify({
  success: r.decision(ok, accept),
  failure: r.decision(failed, accept),
  value: r.decision(ok, { kind: 'accept', value: { out: 'sk-live-0123456789abcdef' } }),
  block: r.decision(ok, { kind: 'block', feedback: leak }),
  untouched: r.decision(clean, accept) === accept,
  none: new bridge.Redactions().decision(ok, accept) === accept,
}));
''');
    final success = out['success'] as Map;
    expect(success['kind'], 'accept');
    expect(jsonEncode(success['content']), isNot(contains('sk-live')));
    expect((success['content'] as List)[1], {'type': 'image', 'data': 'x'});
    final failure = out['failure'] as Map;
    expect(failure['kind'], 'block');
    expect(jsonEncode(failure['feedback']), isNot(contains('sk-live')));
    expect(jsonEncode(out['value']), isNot(contains('sk-live')));
    expect(jsonEncode(out['block']), isNot(contains('sk-live')));
    expect(out['untouched'], isTrue);
    expect(out['none'], isTrue);
  }, skip: node ? false : 'node is not on PATH');

  test('a call naming the vault is refused, in any argument', () async {
    final out = await _node(r'''
const vault = ['/srv/nipa/data/vault'];
console.log(JSON.stringify({
  bash: bridge.namesProtectedPath({ command: 'cat /srv/nipa/data/vault/*.json' }, vault),
  read: bridge.namesProtectedPath({ path: '/srv/nipa/data/vault/abc.json' }, vault),
  nested: bridge.namesProtectedPath({ edits: [{ file: '/srv/nipa/data/vault/x' }] }, vault),
  other: bridge.namesProtectedPath({ command: 'ls /srv/nipa/data/downloads' }, vault),
  none: bridge.namesProtectedPath({ command: 'cat /srv/nipa/data/vault/x' }, []),
}));
''');
    expect(out, {
      'bash': true,
      'read': true,
      'nested': true,
      'other': false,
      'none': false,
    });
  }, skip: node ? false : 'node is not on PATH');

  test('the bridge is told where the vault is, never what is in it', () {
    final rows = dshPatch(
        route: DshRoute(
            model: 'm', baseUrl: 'https://example.invalid', key: 'sk-x-123456789'),
        plugins: Directory('/plugins'),
        personaPrefix: '',
        personaSuffix: '',
        harness: '/harness',
        version: 'v',
        protectedPaths: ['/srv/nipa/data/vault']);
    final encoded = jsonEncode(rows);
    expect(encoded, contains('"protectedPaths":["/srv/nipa/data/vault"]'));
    expect(encoded, isNot(contains('sk-x-123456789')));
  });

  test('the headless vault makes every stored value known at start',
      () async {
    final dir = await Directory.systemTemp.createTemp('headless-vault-');
    addTearDown(() => dir.delete(recursive: true));
    // Written by an earlier run, and not read in this one.
    final secret = 'tmdb-${DateTime.now().microsecondsSinceEpoch}-secret';
    final vault = Directory('${dir.path}/vault')..createSync();
    File('${vault.path}/stored.json').writeAsStringSync(jsonEncode({
      'ref': const CredentialRef('tmdb', 'api-key').toJson(),
      'secret': secret
    }));
    File('${vault.path}/damaged.json').writeAsStringSync('{not json');
    expect(SecretRedactor.remembered().keys, isNot(contains(secret)));
    await HeadlessVault(vault).initialize();
    expect(SecretRedactor.remembered().keys, contains(secret));
  });
}
