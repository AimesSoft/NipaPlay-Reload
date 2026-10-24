@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/headless/dsh.dart';
import 'package:nipaplay/next/runtime/dsh_manifest.dart';
import 'package:path/path.dart' as p;

/// How the headless host finds and starts the runtime Nipa runs on.
void main() {
  late Directory dir;
  final assets = Directory('assets/next/agent').absolute;
  setUp(() async => dir = await Directory.systemTemp.createTemp('headless-dsh-'));
  tearDown(() => dir.delete(recursive: true));

  Directory data() => Directory(p.join(dir.path, 'data'))..createSync();

  test('nothing installed locates nothing; the installed tree is what is launched', () async {
    final platform = DshManifest.hostPlatform();
    final dsh = HeadlessDsh.open(
        data: data(), agentAssets: assets, environment: const {}, platform: platform);
    expect(await dsh.locate(), isNull);
    expect(dsh.fixed, false);
    expect(dsh.install.supported, platform != null);
    if (platform == null) return;
    // The layout DshInstall leaves: node/, lib/node_modules/@deepseek-ai/dsh/lib/bin.js.
    final installed = dsh.install.installed;
    final node = File(p.join(installed.path, 'node', platform.startsWith('windows') ? 'node.exe' : 'node'))
      ..createSync(recursive: true);
    File(p.join(installed.path, 'lib', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'))
        .createSync(recursive: true);
    File(p.join(installed.path, 'installed.json')).writeAsStringSync('{}');
    final runtime = (await dsh.locate())!;
    expect(runtime.node, node.absolute.path);
    expect(runtime.bin, endsWith('bin.js'));
    expect(runtime.version, DshManifest.parse(
        File(p.join(assets.path, 'dsh-runtime.json')).readAsStringSync()).dsh);
  });

  test('an installation named by the environment wins; codex is refused', () async {
    final node = File(p.join(dir.path, 'my-node'))..writeAsStringSync('');
    final bin = File(p.join(dir.path, 'root', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'))
      ..createSync(recursive: true);
    final dsh = HeadlessDsh.open(data: data(), agentAssets: assets, environment: {
      'NIPAPLAY_AGENT_RUNTIME': 'dsh',
      'NIPAPLAY_DSH_NODE': node.path,
      'NIPAPLAY_DSH_ROOT': p.join(dir.path, 'root'),
    });
    expect(dsh.fixed, true);
    final runtime = (await dsh.locate())!;
    expect(runtime.node, node.path);
    expect(runtime.bin, '${p.join(dir.path, 'root')}/node_modules/@deepseek-ai/dsh/lib/bin.js');
    expect(bin.existsSync(), true);
    expect(
        () => HeadlessDsh.open(
            data: data(),
            agentAssets: assets,
            environment: {'NIPAPLAY_AGENT_RUNTIME': 'codex'}),
        throwsStateError);
  });

  test('the platforms the manifest pins can all be installed from it', () {
    final manifest = DshManifest.parse(
        File(p.join(assets.path, 'dsh-runtime.json')).readAsStringSync());
    for (final platform in ['macos-arm64', 'linux-x64', 'windows-x64']) {
      expect(manifest.supports(platform), true, reason: platform);
    }
  });

  // Real DeepSeek Harness: set NIPAPLAY_DSH_NODE and NIPAPLAY_DSH_ROOT (the
  // runtime a download left, or any DSH install), or this is skipped.
  final env = Platform.environment;
  final real = env['NIPAPLAY_DSH_NODE'] != null && env['NIPAPLAY_DSH_ROOT'] != null;
  test('the located runtime starts with the plugins and opens a thread', () async {
    final dsh = HeadlessDsh.open(
        data: data(),
        agentAssets: assets,
        environment: {...env, 'NIPAPLAY_AGENT_RUNTIME': 'dsh'});
    final runtime = (await dsh.locate())!;
    final check = await dsh.check(runtime);
    expect(check.version, runtime.version);
    expect(check.threadId, isNotEmpty);
    expect(
        jsonDecode(File(p.join(dsh.data.path, 'dsh-check', 'patch.json')).readAsStringSync()),
        isA<List>());
  }, skip: real ? null : 'No DeepSeek Harness runtime (NIPAPLAY_DSH_NODE, NIPAPLAY_DSH_ROOT).');
}
