@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/runtime/dsh_install.dart';
import 'package:nipaplay/next/runtime/dsh_manifest.dart';
import 'package:nipaplay/next/ui_data/host_settings.dart';

/// The runtime NipaPlay fetches for DeepSeek Harness: Node.js from nodejs.org
/// and the trimmed DSH from the npm registry, each file pinned by SHA-256.
/// Here the servers are local fixtures with the same layout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = DshManifest.hostPlatform();
  final skip = platform == null || platform.startsWith('windows')
      ? 'Needs tar and a POSIX shell.'
      : null;

  late Directory dir;
  late _Server server;
  setUp(() async {
    HttpOverrides.global = null;
    dir = await Directory.systemTemp.createTemp('dsh-install-');
    server = await _Server.start();
  });
  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  test('manifest asset parses and pins every file', () async {
    final manifest = DshManifest.parse(
        await File('assets/next/agent/dsh-runtime.json').readAsString());
    expect(manifest.id, startsWith('dsh-'));
    expect(manifest.nodes.keys,
        containsAll(['macos-arm64', 'macos-x64', 'linux-x64', 'linux-arm64', 'windows-x64']));
    expect(manifest.supports('macos-arm64'), true);
    expect(manifest.supports('linux-x64'), true);
    expect(manifest.supports('windows-x64'), true);
    expect(manifest.supports('linux-arm64'), false);
    for (final node in manifest.nodes.values) {
      expect(node.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(Uri.parse(node.url).host, 'nodejs.org');
      expect(node.bytes, greaterThan(1 << 20));
    }
    final paths = <String>{};
    for (final package in manifest.packages) {
      expect(package.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(package.url, endsWith('.tgz'));
      expect(paths.add(package.path), true, reason: package.path);
    }
    // The packages of a platform are filtered by npm's os and cpu.
    final arm = manifest.packagesFor('macos-arm64').map((p) => p.path);
    expect(arm, contains('node_modules/@deepseek-ai/dsh'));
    expect(arm, contains('node_modules/@img/sharp-darwin-arm64'));
    expect(arm, isNot(contains('node_modules/@img/sharp-darwin-x64')));
    // Each platform gets its own natives and the packages only it needed.
    Set<String> of(String platform) =>
        manifest.packagesFor(platform).map((p) => p.path.replaceFirst('node_modules/', '')).toSet();
    final linux = of('linux-x64'), windows = of('windows-x64'), mac = of('macos-arm64');
    expect(linux, containsAll(['@img/sharp-linux-x64', '@img/sharp-libvips-linux-x64', 'koffi', '@koromix/koffi-linux-x64']));
    expect(linux, isNot(contains('@img/sharp-linuxmusl-x64')));
    expect(linux, isNot(contains('@img/sharp-darwin-arm64')));
    expect(linux, isNot(contains('@deepseek-ai/dsh-tool-pwsh')));
    expect(windows, containsAll(['@img/sharp-win32-x64', '@deepseek-ai/dsh-tool-pwsh', 'koffi', '@koromix/koffi-win32-x64']));
    expect(windows, isNot(contains('@img/sharp-linux-x64')));
    // macOS keeps what it had: nothing of the others' arrived.
    expect(mac, isNot(contains('koffi')));
    expect(mac, isNot(contains('@deepseek-ai/dsh-tool-pwsh')));
    expect(mac, isNot(contains('@img/sharp-linux-x64')));
    expect(mac, isNot(contains('@img/sharp-win32-x64')));
    expect(mac, isNot(contains('@deepseek-ai/node-addon-system-linux-x64')));
    // The disabled rows' packages stay out.
    final names = manifest.packages.map((p) => p.name).toSet();
    for (final out in [
      '@deepseek-ai/dsh-session-log-deepseek',
      '@deepseek-ai/dsh-skill-office',
      '@deepseek-ai/libreoffice-kit',
      '@deepseek-ai/dsh-tool-workflow',
      '@deepseek-ai/dsh-session-telemetry-otel',
      '@deepseek-ai/dsh-deepseek-account',
      'node-pty',
    ]) {
      expect(names, isNot(contains(out)), reason: out);
    }
  });

  group('installation', () {
    late DshInstall install;
    late int changes;
    late _Fixture fixture;

    DshInstall make({bool Function()? inUse, DshFallback? fallback, bool verifySignature = false}) {
      fixture = _Fixture.build(dir, platform!, server.base);
      server.files
        ..clear()
        ..addAll(fixture.served);
      changes = 0;
      return install = DshInstall(
          root: Directory('${dir.path}/runtime'),
          manifest: fixture.manifest,
          platform: platform,
          notify: () => changes++,
          httpClient: HttpClient.new,
          inUse: inUse ?? () => false,
          verifySignature: verifySignature,
          fallback: fallback ?? DshFallback.npmmirror,
          concurrency: 3);
    }

    test('downloads, verifies, unpacks, and appears in one rename', () async {
      make();
      expect((await install.state()).status, UiDshStatus.notInstalled);
      expect(await install.runtime(), isNull);
      await install.install();
      final state = await install.state();
      expect(state.status, UiDshStatus.ready);
      expect(state.totalBytes, fixture.totalBytes);
      final runtime = (await install.runtime())!;
      expect(runtime.version, '1.0.0');
      expect(await File(runtime.bin).readAsString(), contains('dsh-bin'));
      expect((await Process.run(runtime.node, ['--version'])).stdout,
          contains('v24.22.0'));
      // Nested package at its own path; wrong-platform package absent.
      expect(
          await File('${install.installed.path}/lib/node_modules/@deepseek-ai/dsh/node_modules/zod/index.js')
              .exists(),
          true);
      expect(
          await Directory('${install.installed.path}/lib/node_modules/other-os')
              .exists(),
          false);
      // Downloads and the half-way directory are gone.
      expect(await Directory('${dir.path}/runtime/downloads').exists(), false);
      expect(await Directory('${install.installed.path}.pending').exists(), false);
      expect(changes, greaterThan(2));
      // A second call has nothing to do.
      final before = server.requests.length;
      await install.install();
      expect(server.requests.length, before);
    }, skip: skip);

    test('macOS refuses an unsigned runtime and preserves codesign diagnostics', () async {
      make(verifySignature: true);
      await install.install();
      final state = await install.state();
      expect(state.status, UiDshStatus.failed);
      expect(state.problem, contains('codesign exit'));
      expect(state.problem, contains('not signed'));
      expect(await install.runtime(), isNull);
    }, skip: !Platform.isMacOS);

    test('a stopped download continues from its partial file and finished files stay',
        () async {
      make();
      final node = fixture.manifest.nodes[platform]!;
      server.stallAfter[node.name] = 20000;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
        install.cancel();
      }));
      await install.install();
      expect((await install.state()).status, UiDshStatus.notInstalled);
      final part = File('${dir.path}/runtime/downloads/${node.sha256}.part');
      expect(await part.exists(), true);
      expect(await part.length(), lessThan(node.bytes));
      final kept = await part.length();
      final finished = Directory('${dir.path}/runtime/downloads')
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.part'))
          .length;
      server.stallAfter.clear();
      server.requests.clear();
      await install.install();
      expect((await install.state()).status, UiDshStatus.ready);
      final ranged = server.ranges[node.name];
      expect(ranged, 'bytes=$kept-');
      // Files that were whole are not asked for again.
      expect(server.requests.length,
          fixture.manifest.packagesFor(platform!).map((p) => p.sha256).toSet().length +
              1 -
              finished);
    }, skip: skip);

    test('a file that is not what the manifest pins is refused and named', () async {
      make();
      final target = fixture.manifest.packagesFor(platform!)[1];
      server.files['/${target.url}'] = utf8.encode('x' * target.bytes);
      await install.install();
      final state = await install.state();
      expect(state.status, UiDshStatus.failed);
      expect(state.problem, contains(target.url.split('/').last));
      expect(state.problem, contains('SHA-256'));
      expect(await install.runtime(), isNull);
      expect(
          await File('${dir.path}/runtime/downloads/${target.sha256}').exists(),
          false);
      // The same call, with the right bytes, now succeeds without a restart.
      server.files['/${target.url}'] = fixture.served['/${target.url}']!;
      await install.install();
      expect((await install.state()).status, UiDshStatus.ready);
    }, skip: skip);

    test('a missing file and an unreachable server are facts, not a vague failure',
        () async {
      make();
      final target = fixture.manifest.packagesFor(platform!).first;
      server.files.remove('/${target.url}');
      await install.install();
      var state = await install.state();
      expect(state.status, UiDshStatus.failed);
      expect(state.problem, contains('HTTP 404'));
      expect(state.problem, contains(target.url.split('/').last));
      expect(state.problem, contains('127.0.0.1'));
      await server.close();
      server = await _Server.start();
      // Nothing listens at the old address any more.
      await install.install();
      state = await install.state();
      expect(state.status, UiDshStatus.failed);
      expect(state.problem, isNotNull);
    }, skip: skip);

    test('a mirror changes where bytes come from, never what they must be', () async {
      make();
      final mirror = await _Server.start();
      addTearDown(mirror.close);
      mirror.files.addAll(fixture.served);
      // The official address answers nothing; only the mirror has the files.
      server.files.clear();
      await install.configure(
          registryMirror: '${mirror.base}/', nodeMirror: mirror.base);
      expect((await install.mirrors()).registry, mirror.base);
      await install.install();
      expect((await install.state()).status, UiDshStatus.ready);
      expect(server.requests, isEmpty);
      expect(mirror.requests, isNotEmpty);
      // A mirror must be a plain HTTPS address.
      await expectLater(install.configure(registryMirror: 'http://example.com'),
          throwsA(isA<FormatException>()));
      await expectLater(install.configure(nodeMirror: 'https://u:p@example.com'),
          throwsA(isA<FormatException>()));
      await install.remove();
      await install.configure(registryMirror: '', nodeMirror: '');
      expect((await install.mirrors()).registry, isNull);
    }, skip: skip);

    // The official addresses are the manifest's; npmmirror stands behind
    // them. Here the "official" address is a local server and the mirror
    // another (named localhost, so a failure can tell them apart).
    Future<(_Server, DshFallback)> mirror() async {
      final standIn = await _Server.start();
      addTearDown(standIn.close);
      final port = standIn.base.split(':').last;
      return (
        standIn,
        DshFallback(
            node: 'http://localhost:$port/mirrors/node',
            registry: 'http://localhost:$port',
            hosts: {'127.0.0.1'})
      );
    }

    /// The mirror holds what the fixture serves (nodejs.org/dist/v24.22.0/...
    /// is mirrors/node/v24.22.0/... there).
    void fill(_Server standIn) {
      for (final entry in fixture.served.entries) {
        standIn.files[entry.key.startsWith('/v24.22.0/')
            ? '/mirrors/node${entry.key}'
            : entry.key] = entry.value;
      }
    }

    test('when the official address does not answer, npmmirror delivers the same pinned bytes',
        () async {
      final (standIn, fallback) = await mirror();
      make(fallback: fallback);
      fill(standIn);
      // Nothing listens at the official address any more.
      await server.close();
      await install.install();
      expect((await install.state()).status, UiDshStatus.ready);
      expect(standIn.requests, isNotEmpty);
      final runtime = (await install.runtime())!;
      expect(await File(runtime.bin).readAsString(), contains('dsh-bin'));
    }, skip: skip);

    test('a file the official address lacks comes from npmmirror; the rest stay official',
        () async {
      final (standIn, fallback) = await mirror();
      make(fallback: fallback);
      fill(standIn);
      final target = fixture.manifest.packagesFor(platform!).first;
      server.files.remove('/${target.url}');
      await install.install();
      expect((await install.state()).status, UiDshStatus.ready);
      expect(standIn.requests, contains('/${target.url}'));
      expect(standIn.requests.length, lessThan(fixture.served.length));
      expect(server.requests, isNotEmpty);
    }, skip: skip);

    test('bytes from npmmirror are held to the manifest, and the failure tells both sources apart',
        () async {
      final (standIn, fallback) = await mirror();
      make(fallback: fallback);
      fill(standIn);
      final target = fixture.manifest.packagesFor(platform!)[1];
      server.files.remove('/${target.url}');
      standIn.files['/${target.url}'] = utf8.encode('y' * target.bytes);
      await install.install();
      final state = await install.state();
      expect(state.status, UiDshStatus.failed);
      expect(state.problem, contains(target.url.split('/').last));
      expect(state.problem, contains('官方源（127.0.0.1）：HTTP 404'));
      expect(state.problem, contains('备用源（localhost）：SHA-256'));
      expect(await install.runtime(), isNull);
    }, skip: skip);

    test('a mirror the person named is the only source: nothing falls back', () async {
      final (standIn, fallback) = await mirror();
      make(fallback: fallback);
      fill(standIn);
      final custom = await _Server.start();
      addTearDown(custom.close);
      await install.configure(registryMirror: custom.base, nodeMirror: custom.base);
      await install.install();
      final state = await install.state();
      expect(state.status, UiDshStatus.failed);
      expect(state.problem, contains('HTTP 404'));
      expect(state.problem, isNot(contains('备用源')));
      expect(standIn.requests, isEmpty);
      expect(server.requests, isEmpty);
    }, skip: skip);

    test('removing refuses while a chat process uses it', () async {
      var used = false;
      make(inUse: () => used);
      await install.install();
      used = true;
      await expectLater(install.remove(), throwsStateError);
      expect((await install.state()).status, UiDshStatus.ready);
      used = false;
      await install.remove();
      expect((await install.state()).status, UiDshStatus.notInstalled);
      expect(await install.runtime(), isNull);
    }, skip: skip);

    test('an older installation is removed once a new one is in place', () async {
      make();
      final old = await Directory('${dir.path}/runtime/dsh-0.1.0-node-20.0.0')
          .create(recursive: true);
      await install.install();
      expect(await old.exists(), false);
    }, skip: skip);

    test('a platform without a traced runtime says so and fetches nothing', () async {
      make();
      final other = DshInstall(
          root: Directory('${dir.path}/other'),
          manifest: fixture.manifest,
          platform: 'linux-riscv',
          notify: () {},
          httpClient: HttpClient.new,
          inUse: () => false);
      expect((await other.state()).status, UiDshStatus.unsupported);
      await other.install();
      expect((await other.state()).status, UiDshStatus.unsupported);
      expect(await other.runtime(), isNull);
      expect(server.requests, isEmpty);
    }, skip: skip);
  });
}

/// A local stand-in for nodejs.org and the registry.
final class _Server {
  _Server._(this._server);

  static Future<_Server> start() async {
    final server = _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    server._server.listen(server._handle);
    return server;
  }

  final HttpServer _server;
  final files = <String, List<int>>{};
  final requests = <String>[];
  final ranges = <String, String>{};

  /// Name -> bytes after which the answer stops (until the client gives up).
  final stallAfter = <String, int>{};
  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add(path);
    final data = files[path];
    if (data == null) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    final name = path.split('/').last;
    final range = request.headers.value('range');
    var start = 0;
    if (range != null) {
      ranges[name] = range;
      start = int.parse(range.substring(6, range.length - 1));
      request.response.statusCode = 206;
      request.response.headers
          .set('content-range', 'bytes $start-${data.length - 1}/${data.length}');
    }
    request.response.contentLength = data.length - start;
    final limit = stallAfter[name];
    try {
      for (var i = start; i < data.length; i += 16384) {
        if (limit != null && i - start >= limit) {
          await Future<void>.delayed(const Duration(seconds: 30));
          break;
        }
        request.response.add(data.sublist(i, min(i + 16384, data.length)));
        await request.response.flush();
        if (limit != null) await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await request.response.close();
    } on IOException {/* The client stopped, as the test intends. */}
  }

  Future<void> close() => _server.close(force: true);
}

/// Archives as nodejs.org and npm publish them, and the manifest that pins them.
final class _Fixture {
  _Fixture(this.manifest, this.served, this.totalBytes);

  final DshManifest manifest;
  final Map<String, List<int>> served;
  final int totalBytes;

  static _Fixture build(Directory dir, String platform, String base) {
    final work = Directory('${dir.path}/fixture')..createSync(recursive: true);
    final served = <String, List<int>>{};

    var counter = 0;
    List<int> tar(String name, Map<String, String> files, {Set<String> executable = const {}}) {
      final wrapper = Directory('${work.path}/${counter++}')..createSync(recursive: true);
      final root = Directory('${wrapper.path}/$name')..createSync(recursive: true);
      for (final entry in files.entries) {
        final file = File('${root.path}/${entry.key}')
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value);
        if (executable.contains(entry.key)) {
          Process.runSync('chmod', ['755', file.path]);
        }
      }
      final out = File('${wrapper.path}.tgz');
      final result = Process.runSync('tar', ['-czf', out.path, '-C', wrapper.path, name]);
      expect(result.exitCode, 0);
      return out.readAsBytesSync();
    }

    final arch = platform.split('-')[1] == 'arm64' ? 'arm64' : 'x64';
    final os = platform.startsWith('macos') ? 'darwin' : 'linux';
    final nodeDir = 'node-v24.22.0-$os-$arch';
    final nodeBytes = tar(
        nodeDir,
        {
          'bin/node': '#!/bin/sh\necho v24.22.0\n',
          'LICENSE': 'node license',
          // Incompressible, so the archive is big enough to stop half way.
          'include/node.h': (() {
            final random = Random(7);
            return base64.encode(List.generate(150000, (_) => random.nextInt(256)));
          })(),
        },
        executable: {'bin/node'});
    final nodeName = '$nodeDir.tar.gz';
    served['/v24.22.0/$nodeName'] = nodeBytes;

    final packages = <Map<String, Object?>>[];
    void package(String path, String name, Map<String, String> files,
        {List<String>? osList, List<String>? cpu}) {
      final base = name.split('/').last;
      final archive = tar('package', files);
      // Each npm tarball is a `package/` directory.
      final bytes = archive;
      final url = '$name/-/$base-1.0.0.tgz';
      served['/$url'] = bytes;
      packages.add({
        'path': path,
        'name': name,
        'version': '1.0.0',
        'url': url,
        'sha256': sha256.convert(bytes).toString(),
        'bytes': bytes.length,
        if (osList != null) 'os': osList,
        if (cpu != null) 'cpu': cpu,
      });
    }

    package('node_modules/@deepseek-ai/dsh', '@deepseek-ai/dsh',
        {'lib/bin.js': '// dsh-bin', 'package.json': '{"version":"1.0.0"}'});
    package('node_modules/@deepseek-ai/dsh/node_modules/zod', 'zod',
        {'index.js': 'zod', 'package.json': '{"version":"1.0.0"}'});
    package('node_modules/other-os', 'other-os', {'index.js': 'x'},
        osList: [os == 'darwin' ? 'linux' : 'darwin']);

    final json = {
      'schema': 1,
      'dsh': '1.0.0',
      'node': {
        'version': '24.22.0',
        'assets': {
          platform: {
            'url': '$base/v24.22.0/$nodeName',
            'sha256': sha256.convert(nodeBytes).toString(),
            'bytes': nodeBytes.length,
            'archive': 'tar',
            'executable': '$nodeDir/bin/node',
          }
        }
      },
      'registry': base,
      'platforms': [platform],
      'packages': packages,
    };
    final manifest = DshManifest.parse(jsonEncode(json));
    final wanted = manifest.packagesFor(platform);
    final total = nodeBytes.length +
        {for (final p in wanted) p.sha256: p.bytes}.values.fold<int>(0, (a, b) => a + b);
    return _Fixture(manifest, served, total);
  }
}
