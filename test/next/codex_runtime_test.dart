import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/runtime/codex_manifest.dart';
import 'package:nipaplay/next/runtime/codex_runtime.dart';
import 'package:nipaplay/next/ui_data/host_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in ['windows', 'linux']) {
    test(
        '$platform complete native layout, cancellation, resume, digest rejection',
        () async {
      HttpOverrides.global = null;
      final root = await Directory.systemTemp.createTemp('x61-$platform-');
      final fixture =
          await Directory('${root.path}/fixture/package/vendor/native/bin')
              .create(recursive: true);
      final binary = platform == 'windows' ? 'codex.exe' : 'codex';
      final random = Random(61);
      await File('${fixture.path}/$binary')
          .writeAsBytes(List.generate(128 * 1024, (_) => random.nextInt(256)));
      await File('${fixture.path}/helper').writeAsString('helper');
      await File('${fixture.parent.path}/LICENSE-component')
          .writeAsString('fixture license');
      final archive = File('${root.path}/fixture.tgz');
      expect(
          (await Process.run('tar', [
            '-czf',
            archive.path,
            '-C',
            '${root.path}/fixture',
            'package'
          ]))
              .exitCode,
          0);
      final bytes = await archive.readAsBytes();
      final ranges = <String?>[];
      var ignoreRange = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final range = request.headers.value('range');
        ranges.add(range);
        final start = range == null || ignoreRange
            ? 0
            : int.parse(range.substring(6, range.length - 1));
        if (range != null && !ignoreRange) {
          request.response.statusCode = 206;
          request.response.headers.set('content-range',
              'bytes $start-${bytes.length - 1}/${bytes.length}');
        }
        request.response.contentLength = bytes.length - start;
        try {
          for (var i = start; i < bytes.length; i += 4096) {
            request.response.add(bytes.sublist(i, min(i + 4096, bytes.length)));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          await request.response.close();
        } on IOException {/* The client deliberately cancels this fixture. */}
      });
      final asset = CodexAsset('fixture.tgz', sha256.convert(bytes).toString(),
          bytes.length, 'package/vendor/native/bin/$binary');
      late CodexRuntime runtime;
      var shouldCancel = true;
      var cancelled = false;
      runtime = CodexRuntime(
          root: Directory('${root.path}/runtime'),
          platform: platform,
          asset: CodexAsset(
              asset.name, asset.sha256, asset.bytes, asset.executable),
          notify: () {
            if (shouldCancel && !cancelled) {
              unawaited(runtime.state().then((s) {
                if (!cancelled &&
                    s.receivedBytes >= 8192 &&
                    s.status == UiCodexStatus.downloading) {
                  cancelled = true;
                  unawaited(runtime.cancel());
                }
              }));
            }
          },
          inUse: () => false,
          httpClient: () => _FixtureClient('http://127.0.0.1:${server.port}'));
      try {
        await runtime.install();
        expect((await runtime.state()).status, UiCodexStatus.notInstalled);
        final retained = await runtime.partial.length();
        expect(retained, inExclusiveRange(0, bytes.length));
        shouldCancel = false;
        await runtime.install();
        expect(ranges.last, 'bytes=$retained-');
        expect((await runtime.state()).status, UiCodexStatus.ready);
        expect(
            await File(
                    '${runtime.installed.path}/package/vendor/native/bin/helper')
                .readAsString(),
            'helper');
        expect(
            await File(
                    '${runtime.installed.path}/licenses/package/vendor/native/LICENSE-component')
                .exists(),
            true);
        expect(await runtime.executable(), startsWith(root.absolute.path));
        await runtime.remove();
        final corrupted = [...bytes];
        corrupted[15] ^= 1;
        await runtime.partial.writeAsBytes(corrupted);
        await runtime.install();
        expect((await runtime.state()).status, UiCodexStatus.failed);
        expect((await runtime.state()).problem, contains('SHA-256'));
        expect(await runtime.partial.exists(), false);
        expect(await runtime.installed.exists(), false);
        // Servers that ignore Range restart from byte zero instead of appending.
        await runtime.partial.writeAsBytes(bytes.sublist(0, 8192));
        ignoreRange = true;
        await runtime.install();
        expect((await runtime.state()).status, UiCodexStatus.ready);
        await runtime
            .configure(const UiCodexRuntimeChoice(source: UiCodexSource.path));
        expect(await runtime.executable(),
            platform == 'windows' ? 'codex.exe' : 'codex');
        expect(
            () => runtime.configure(const UiCodexRuntimeChoice(
                mirror: 'https://user:secret@example.com')),
            throwsFormatException);
      } finally {
        await runtime.cancel();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    });
  }
  test('manifest pins six desktop native package assets, never latest', () {
    expect(codexAssets.length, 6);
    for (final asset in codexAssets.values) {
      expect(asset.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(asset.url, contains('/rust-v0.144.1/codex-npm-'));
      expect(asset.executable, startsWith('package/vendor/'));
    }
  });
}

/// Rewrite only the fixture URL. Runtime still exercises HTTP Range and hashes.
class _FixtureClient implements HttpClient {
  _FixtureClient(this.base);
  final String base;
  final HttpClient client = HttpClient()..findProxy = (_) => 'DIRECT';
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      client.getUrl(Uri.parse('$base${url.path}'));
  @override
  void close({bool force = false}) => client.close(force: force);
  @override
  set autoUncompress(bool value) => client.autoUncompress = value;
  @override
  set connectionTimeout(Duration? value) => client.connectionTimeout = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
