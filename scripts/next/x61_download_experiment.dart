@Timeout(Duration(minutes: 12))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/runtime/codex_manifest.dart';
import 'package:nipaplay/next/runtime/codex_runtime.dart';
import 'package:nipaplay/next/ui_data/host_settings.dart';

/// Opt-in network experiment. Not discovered by the normal test/next suite.
/// Leaves its /tmp runtime for x61_experiment.py; that script removes it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real pinned macOS ARM64 download, cancellation, resume and corruption',
      () async {
    HttpOverrides.global = null;
    final root = Directory('/tmp/nipa-next/x61/download');
    final evidence = Directory('docs/next/evidence/x61');
    await evidence.create(recursive: true);
    late CodexRuntime runtime;
    var cancelled = false;
    runtime = CodexRuntime.desktop(
        root: root,
        inUse: () => false,
        notify: () {
          if (!cancelled) {
            unawaited(runtime.state().then((state) {
              if (!cancelled &&
                  state.status == UiCodexStatus.downloading &&
                  state.receivedBytes >= 4 * 1024 * 1024) {
                cancelled = true;
                unawaited(runtime.cancel());
              }
            }));
          }
        });
    final watch = Stopwatch()..start();
    await runtime.install();
    final retained = await runtime.partial.length();
    expect(retained, greaterThan(0));
    expect((await runtime.state()).status, UiCodexStatus.notInstalled);
    await runtime.install();
    final installed = await runtime.state();
    final summary = <String, Object?>{
      'version': codexVersion,
      'asset': codexAssets['macos-arm64']!.name,
      'url': codexAssets['macos-arm64']!.url,
      'expectedSha256': codexAssets['macos-arm64']!.sha256,
      'cancelledBytes': retained,
      'resumedStatus': installed.status.name,
      'problem': installed.problem,
      'elapsedMs': watch.elapsedMilliseconds,
    };
    await File('${evidence.path}/download.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
    expect(installed.status, UiCodexStatus.ready);
    final files = <Object?>[];
    await for (final entity
        in runtime.installed.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        files.add({
          'path': entity.path.substring(runtime.installed.path.length + 1),
          'bytes': await entity.length(),
          'sha256': (await sha256.bind(entity.openRead()).first).toString()
        });
      }
    }
    summary['files'] = files;
    final binary = installed.executable!;
    final signature = await Process.run(
        '/usr/bin/codesign', ['--verify', '--strict', '-R=notarized', binary]);
    summary['notarizedSignatureExit'] = signature.exitCode;
    expect(signature.exitCode, 0);
    final quarantine =
        '0083;${(DateTime.now().millisecondsSinceEpoch ~/ 1000).toRadixString(16)};NipaPlay;';
    expect(
        (await Process.run('/usr/bin/xattr',
                ['-w', 'com.apple.quarantine', quarantine, binary]))
            .exitCode,
        0);
    summary['quarantine'] = (await Process.run(
            '/usr/bin/xattr', ['-p', 'com.apple.quarantine', binary]))
        .stdout
        .toString()
        .trim();
    final version = await Process.run(binary, ['--version'],
        environment: {'CODEX_HOME': '${root.path}/version-home'});
    summary['quarantinedVersionExit'] = version.exitCode;
    summary['quarantinedVersion'] = version.stdout.toString().trim();
    expect(version.exitCode, 0);
    final corrupt = CodexRuntime.desktop(
        root: Directory('/tmp/nipa-next/x61/corrupt'),
        notify: () {},
        inUse: () => false);
    await corrupt.root.create(recursive: true);
    // The initial inventory download is outside the repository, never evidence.
    await File('/tmp/nipa-next/x61/inspect.tgz').copy(corrupt.partial.path);
    final file = await corrupt.partial.open(mode: FileMode.append);
    await file.setPosition(100);
    final original = await File(corrupt.partial.path).open();
    await original.setPosition(100);
    final byte = await original.readByte();
    await original.close();
    await file.writeByte(byte ^ 1);
    await file.close();
    await corrupt.install();
    summary['corruptStatus'] = (await corrupt.state()).status.name;
    summary['corruptProblem'] = (await corrupt.state()).problem;
    summary['corruptPartialDeleted'] = !await corrupt.partial.exists();
    expect((await corrupt.state()).status, UiCodexStatus.failed);
    expect(await corrupt.partial.exists(), false);
    await corrupt.root.delete(recursive: true);
    await File('${evidence.path}/download.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
  });
}
