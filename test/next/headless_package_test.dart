@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/headless/dandanplay_login.dart';
import 'package:nipaplay/next/headless/host_marker.dart';
import 'package:nipaplay/next/headless/package_layout.dart';
import 'package:nipaplay/next/headless/vault.dart';
import 'package:nipaplay/next/sqlite_library.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:path/path.dart' as p;

/// What an installed package needs from the executable: finding its own files,
/// reporting its version, and letting the person at the host sign in.
void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('headless-pkg-'));
  tearDown(() => dir.delete(recursive: true));

  group('where the host finds its files', () {
    test('an installed package is found from the executable, not the working directory', () {
      final app = p.join(dir.path, 'app');
      Directory(p.join(app, 'assets', 'next', 'agent')).createSync(recursive: true);
      Directory(p.join(app, 'libexec')).createSync(recursive: true);
      final elsewhere = p.join(dir.path, 'elsewhere');
      Directory(p.join(elsewhere, 'assets', 'next', 'agent')).createSync(recursive: true);
      expect(
          headlessAssetPath('agent',
              executable: p.join(app, 'libexec', 'nipaplay-headless-host'),
              workingDirectory: elsewhere),
          p.join(app, 'assets', 'next', 'agent'));
    });

    test('beside the executable works too; a checkout falls back to the working directory', () {
      final bin = p.join(dir.path, 'bin');
      Directory(p.join(bin, 'assets', 'next', 'harness')).createSync(recursive: true);
      expect(
          headlessAssetPath('harness',
              executable: p.join(bin, 'host'), workingDirectory: dir.path),
          p.join(bin, 'assets', 'next', 'harness'));
      // Neither place has it (the Dart SDK running a checkout): the old default.
      expect(
          headlessAssetPath('agent',
              executable: p.join(dir.path, 'sdk', 'dart'), workingDirectory: '/work'),
          p.join('/work', 'assets', 'next', 'agent'));
    });

    test('with no version defined the host says dev, never an old number', () {
      // The tests run without -DNIPAPLAY_VERSION: a build that forgot to pass
      // it must not report the version of some earlier release.
      expect(headlessVersion, 'dev');
      expect(headlessAppVersion, 'dev-headless');
      for (final file in [
        File('lib/next/headless/core.dart'),
        File('bin/nipaplay_headless.dart'),
      ]) {
        expect(file.readAsStringSync(),
            isNot(matches(RegExp(r"'\d+\.\d+\.\d+[^']*'"))),
            reason: '${file.path} writes a version number into the code');
      }
    });
  });

  group('the SQLite library on a server', () {
    DynamicLibrary Function(String) opening(Set<String> available, List<String> asked) =>
        (name) {
          asked.add(name);
          if (!available.contains(name)) throw ArgumentError('cannot open $name');
          return DynamicLibrary.process();
        };

    test('a server with only the runtime package opens libsqlite3.so.0', () {
      final asked = <String>[];
      var overridden = 0;
      ensureSqliteLibrary(
          linux: true,
          load: opening({'libsqlite3.so.0'}, asked),
          override: (open) {
            overridden++;
            // What the loader will call is the name that opened.
            asked.clear();
            open();
            expect(asked, ['libsqlite3.so.0']);
          });
      expect(overridden, 1);
    });

    test('where libsqlite3.so opens, or on another system, nothing is changed', () {
      var overridden = 0;
      ensureSqliteLibrary(
          linux: true,
          load: opening({'libsqlite3.so', 'libsqlite3.so.0'}, []),
          override: (_) => overridden++);
      ensureSqliteLibrary(linux: false, load: opening({}, []), override: (_) => overridden++);
      // No library at all: the sqlite3 package reports its own error.
      ensureSqliteLibrary(linux: true, load: opening({}, []), override: (_) => overridden++);
      expect(overridden, 0);
      expect(firstLoadableLibrary(linuxSqliteNames, opening({}, [])), isNull);
    });
  });

  group('the data directory', () {
    test('a new or empty directory becomes one; a foreign directory is refused', () async {
      final data = Directory(p.join(dir.path, 'new', 'data'));
      await ensureHeadlessMarker(data);
      expect(jsonDecode(File('${data.path}/headless.json').readAsStringSync()),
          {'format': 1, 'host': 'nipaplay-headless'});
      await ensureHeadlessMarker(data);
      final foreign = Directory(p.join(dir.path, 'foreign'))..createSync();
      File('${foreign.path}/notes.txt').writeAsStringSync('mine');
      await expectLater(ensureHeadlessMarker(foreign), throwsStateError);
      expect(File('${foreign.path}/headless.json').existsSync(), false);
    });
  });

  group('--login-dandanplay', () {
    late HttpServer server;
    late List<Map<String, Object?>> seen;
    late int status;
    late Map<String, Object?> reply;
    late Directory data;

    setUp(() async {
      data = Directory(p.join(dir.path, 'data'));
      seen = [];
      status = 200;
      reply = {'token': 'jwt.header.payload', 'user': {'screenName': 'someone'}};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(() async {
        await for (final request in server) {
          final body = jsonDecode(await utf8.decodeStream(request));
          seen.add({
            'path': request.uri.path,
            'headers': {
              'signature': request.headers.value('x-signature'),
              'timestamp': request.headers.value('x-timestamp'),
            },
            'body': body,
          });
          request.response
            ..statusCode = status
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(reply));
          await request.response.close();
        }
      }());
    });
    tearDown(() => server.close(force: true));

    Future<(int, List<String>)> login(String stdin) async {
      final lines = <String>[];
      final code = await runHeadlessDandanplayLogin(data,
          input: Stream.value(utf8.encode(stdin)),
          write: lines.add,
          server: () async => 'http://127.0.0.1:${server.port}/');
      return (code, lines);
    }

    test('the token reaches the vault and is not said; the password is only in the signed request', () async {
      final (code, lines) = await login('someone@example.test\nS3cret pass word\n');
      expect(code, 0);
      expect(jsonDecode(lines.single), containsPair('status', 'signed_in'));
      expect(lines.join(), isNot(contains('jwt.header')));
      expect(lines.join(), isNot(contains('S3cret')));
      final vault = HeadlessVault(Directory(p.join(data.path, 'vault')));
      expect(await vault.read(const CredentialRef('preferences', 'dandanplay_token')),
          'jwt.header.payload');
      expect(File('${data.path}/headless.json').existsSync(), true);
      // Nothing outside the vault holds the password or the token.
      for (final file in data.listSync(recursive: true).whereType<File>()) {
        if (file.path.contains('${p.separator}vault${p.separator}')) continue;
        final text = file.readAsStringSync();
        expect(text, isNot(contains('S3cret')));
        expect(text, isNot(contains('jwt.header')));
      }
      final request = seen.single;
      expect(request['path'], '/api/v2/login');
      final body = request['body'] as Map;
      expect(body['userName'], 'someone@example.test');
      expect(body['password'], 'S3cret pass word');
      final timestamp = body['unixTimestamp'];
      expect(body['hash'],
          md5.convert(utf8.encode('nipaplayv1S3cret pass word${timestamp}someone@example.testserver-managed')).toString());
      expect((request['headers'] as Map)['signature'],
          base64.encode(sha256.convert(utf8.encode('nipaplayv1$timestamp/api/v2/loginserver-managed')).bytes));
    });

    test('a refusal exits non-zero, says the reason and keeps no token', () async {
      status = 200;
      reply = {'success': false, 'errorMessage': 'The password is wrong.'};
      final (code, lines) = await login('someone\nwrong\r\n');
      expect(code, 1);
      expect(jsonDecode(lines.single), containsPair('status', 'failed'));
      expect(lines.single, contains('The password is wrong.'));
      expect(lines.single, isNot(contains('wrong\\r')));
      expect(
          await HeadlessVault(Directory(p.join(data.path, 'vault')))
              .read(const CredentialRef('preferences', 'dandanplay_token')),
          isNull);
    });

    test('input without a password is refused before any request', () async {
      for (final text in ['', 'someone', 'someone\n', '\npassword\n']) {
        final (code, _) = await login(text);
        expect(code, 1, reason: 'input: ${jsonEncode(text)}');
      }
      expect(seen, isEmpty);
    });
  });
}
