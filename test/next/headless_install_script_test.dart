@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The install, upgrade and uninstall scripts of the Linux package, run against
/// a package whose host is a stand-in shell script. (The real package is
/// installed and run in containers; this keeps the script logic from drifting.)
void main() {
  final linux = Platform.isLinux;
  late Directory dir;
  late Directory home;
  late Directory package;

  Map<String, String> environment() => {
        'HOME': home.path,
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'XDG_DATA_HOME': p.join(home.path, '.local', 'share'),
        'XDG_CONFIG_HOME': p.join(home.path, '.config'),
      };

  Future<ProcessResult> run(String script, List<String> arguments) =>
      Process.run('bash', [p.join(package.path, script), ...arguments],
          environment: environment(), includeParentEnvironment: false);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('headless-install-');
    home = Directory(p.join(dir.path, 'home'))..createSync();
    package = Directory(p.join(dir.path, 'nipaplay-headless'))..createSync();
    final source = Directory('scripts/next/headless/package').absolute;
    for (final name in ['install.sh', 'uninstall.sh']) {
      File(p.join(source.path, name)).copySync(p.join(package.path, name));
    }
    Directory(p.join(package.path, 'bin')).createSync();
    File(p.join(source.path, 'nipaplay-headless'))
        .copySync(p.join(package.path, 'bin', 'nipaplay-headless'));
    Directory(p.join(package.path, 'libexec')).createSync();
    // The stand-in host: reports its arguments; --agent-status creates the marker.
    File(p.join(package.path, 'libexec', 'nipaplay-headless-host'))
        .writeAsStringSync(r'''#!/bin/sh
data=
for a in "$@"; do if [ "$prev" = --data ]; then data=$a; fi; prev=$a; done
case " $* " in *" --agent-status "*) mkdir -p "$data"; echo '{"format":1}' > "$data/headless.json";; esac
echo "host:$*"
''');
    Directory(p.join(package.path, 'assets', 'next')).createSync(recursive: true);
    File(p.join(package.path, 'VERSION')).writeAsStringSync('9.9.9\n');
    File(p.join(package.path, 'README.md')).writeAsStringSync('readme');
    await Process.run('chmod', [
      '+x',
      p.join(package.path, 'install.sh'),
      p.join(package.path, 'uninstall.sh'),
      p.join(package.path, 'bin', 'nipaplay-headless'),
      p.join(package.path, 'libexec', 'nipaplay-headless-host'),
    ]);
  });
  tearDown(() => dir.delete(recursive: true));

  final base = () => p.join(home.path, '.local', 'share', 'nipaplay-headless');

  test('installs the program and a command, creates the data directory, and says how to run it without a service',
      () async {
    final result = await run('install.sh', ['--no-service']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File(p.join(base(), 'app', 'libexec', 'nipaplay-headless-host')).existsSync(), true);
    expect(File(p.join(base(), 'app', 'uninstall.sh')).existsSync(), true);
    expect(File(p.join(base(), 'data', 'headless.json')).existsSync(), true,
        reason: 'the data directory is initialised so mesh.json can be placed');
    final command = Link(p.join(home.path, '.local', 'bin', 'nipaplay-headless'));
    expect(command.existsSync(), true);
    expect(result.stdout, contains('9.9.9'));
    expect(result.stdout, contains('nipaplay-headless'));
    expect(Directory(p.join(home.path, '.config', 'systemd')).existsSync(), false);
  }, skip: !linux);

  test('the command gives the program the installed data directory, and an own --data wins', () async {
    await run('install.sh', ['--no-service']);
    final command = p.join(home.path, '.local', 'bin', 'nipaplay-headless');
    final data = p.join(base(), 'data');
    final plain = await Process.run(command, ['--model-status'],
        environment: environment(), includeParentEnvironment: false);
    expect(plain.stdout, contains('host:--data $data --model-status'));
    final own = await Process.run(command, ['--data', '/elsewhere', '--model-status'],
        environment: environment(), includeParentEnvironment: false);
    expect(own.stdout, contains('--data $data --data /elsewhere --model-status'));
  }, skip: !linux);

  test('installing again replaces the program and keeps everything in the data directory', () async {
    await run('install.sh', ['--no-service']);
    final keep = File(p.join(base(), 'data', 'next.db'))..writeAsStringSync('mine');
    File(p.join(base(), 'app', 'stale-file')).writeAsStringSync('old');
    File(p.join(package.path, 'VERSION')).writeAsStringSync('9.9.10\n');
    final result = await run('install.sh', ['--no-service']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File(p.join(base(), 'app', 'stale-file')).existsSync(), false);
    expect(File(p.join(base(), 'app', 'VERSION')).readAsStringSync().trim(), '9.9.10');
    expect(keep.readAsStringSync(), 'mine');
  }, skip: !linux);

  test('uninstall keeps the data; --purge removes it', () async {
    await run('install.sh', ['--no-service']);
    File(p.join(base(), 'data', 'next.db')).writeAsStringSync('mine');
    final kept = await Process.run(
        'bash', [p.join(base(), 'app', 'uninstall.sh')],
        environment: environment(), includeParentEnvironment: false);
    expect(kept.exitCode, 0, reason: '${kept.stderr}');
    expect(Directory(p.join(base(), 'app')).existsSync(), false);
    expect(Link(p.join(home.path, '.local', 'bin', 'nipaplay-headless')).existsSync(), false);
    expect(File(p.join(base(), 'data', 'next.db')).readAsStringSync(), 'mine');

    await run('install.sh', ['--no-service']);
    final purged = await Process.run(
        'bash', [p.join(base(), 'app', 'uninstall.sh'), '--purge'],
        environment: environment(), includeParentEnvironment: false);
    expect(purged.exitCode, 0, reason: '${purged.stderr}');
    expect(Directory(base()).existsSync(), false);
  }, skip: !linux);

  test('a package for another architecture and unsafe paths are refused', () async {
    File(p.join(package.path, 'ARCH')).writeAsStringSync('mips\n');
    final other = await run('install.sh', ['--no-service']);
    expect(other.exitCode, isNot(0));
    expect(other.stderr, contains('mips'));
    File(p.join(package.path, 'ARCH')).deleteSync();
    final spaced = await run('install.sh', ['--no-service', '--data', '/tmp/has space']);
    expect(spaced.exitCode, isNot(0));
    final relative = await run('install.sh', ['--no-service', '--media-root', 'movies']);
    expect(relative.exitCode, isNot(0));
    expect(Directory(base()).existsSync(), false);
  }, skip: !linux);

  test('--system without root is refused before anything is written', () async {
    if (Process.runSync('id', ['-u']).stdout.toString().trim() == '0') return;
    final result = await run('install.sh', ['--system']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('root'));
  }, skip: !linux);
}
