import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/public_url.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/harness_redaction.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/security/credential_vault.dart';

void main() {
  test('server and seed retain public URLs and exclude private locators/known secrets', () async {
    const known = 'x34-known+/ secret';
    SecretRedactor.remember(const CredentialRef('fixture', 'x34'), known);
    const public = 'https://images.example.test/poster.jpg?width=1280&language=zh-CN#art';
    final private = [
      'https://user@example.test/image.jpg',
      'https://user:password-marker@example.test/image.jpg',
      for (final name in ['token', 'access_token', 'api_key', 'Signature', 'sig', 'X-Amz-Credential', 'X-Goog-Signature', '%74oken'])
        'https://example.test/image.jpg?$name=private-marker&width=1280',
      'https://example.test/image.jpg#token=private-marker',
    ];
    final input = {'imageUrl': public, 'text': 'image: $public', 'private': private,
      'known': [known, Uri.encodeComponent(known), Uri.encodeQueryComponent(known)],
      'nested': {'cookie': 'private-cookie-marker', 'authorization': 'Bearer private-bearer-marker'}};
    final server = redactHarnessJson(input) as Map;
    expect(server['imageUrl'], public);
    expect(server['text'], 'image: $public');
    for (final url in private) {
      expect(publicValue(url, const StringSchema()), '[redacted URL]');
    }
    expect(publicValue(public, const StringSchema()), public);
    const code = '''import runpy,json,sys
module=runpy.run_path("assets/next/harness/nipa")
data=json.loads(sys.stdin.read())
print(json.dumps(module["redact"](data, ["x34-known+/ secret"])))
''';
    final process = await Process.start('python3', ['-c', code]);
    process.stdin.write(jsonEncode(input));
    await process.stdin.close();
    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();
    expect(await process.exitCode, 0, reason: stderr);
    final cli = jsonDecode(stdout) as Map;
    expect(cli['imageUrl'], public);
    expect(cli['text'], 'image: $public');
    for (final result in [jsonEncode(server), stdout, jsonEncode(publicHarnessFacts(input))]) {
      for (final secret in ['private-marker', 'password-marker', 'private-cookie-marker', 'private-bearer-marker', known, Uri.encodeComponent(known), Uri.encodeQueryComponent(known)]) {
        expect(result, isNot(contains(secret)));
      }
    }
  });

  test('tracker and RSS keys never pass as public links', () {
    for (final private in [
      'https://pt.example/torrentrss.php?rows=10&rsskey=abcdef',
      'https://tracker.example/announce.php?authkey=abc&torrent_pass=def',
      'https://tracker.example/0123456789abcdef0123456789abcdef/announce',
      'https://u2.example/announce?secure=abc',
      'https://site.example/download.php?id=1&uid=2&hash=abc',
    ]) {
      expect(redactPrivateUrls(private), '[redacted URL]', reason: private);
    }
    for (final public in [
      'https://lain.bgm.tv/pic/cover/l/01/d5/504950_WmdZx.jpg',
      'https://image.tmdb.org/t/p/original/xJHokMbljvjADYdit5fK5VQsXEG.jpg',
      'https://mikanani.me/RSS/Bangumi?bangumiId=3141&subgroupid=370',
    ]) {
      expect(redactPrivateUrls(public), public);
    }
  });
}
