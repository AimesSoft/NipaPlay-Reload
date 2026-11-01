import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/plugins/plugin_process_manager.dart';
import 'package:nipaplay/plugins/models/plugin_ui_entry.dart';

Future<void> waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for process');
}

void main() {
  test('password metadata is opt-in', () {
    expect(PluginTextSetting.fromJson({}).obscureText, isFalse);
    expect(
        PluginTextSetting.fromJson({'obscureText': true}).obscureText, isTrue);
  });

  for (final terminal in [false, true]) {
    test('environment, process tree and shutdown (terminal=$terminal)',
        () async {
      final root = await Directory.systemTemp.createTemp('bridge test ');
      Process? terminalProcess;
      final manager = PluginProcessManager(
        terminalLauncher:
            terminal && Platform.environment['NIPAPLAY_TEST_TERMINAL'] != '1'
                ? (script) async {
                    final tty = await Process.start('/usr/bin/script',
                        ['-q', '/dev/null', '/bin/bash', script]);
                    terminalProcess = tty;
                    unawaited(tty.stdout.drain<void>());
                    unawaited(tty.stderr.drain<void>());
                  }
                : null,
      );
      addTearDown(() async {
        await manager.shutdown();
        await root.delete(recursive: true);
      });
      final executable = File("${root.path}/bridge ' script.sh");
      final output = File('${root.path}/output');
      final pids = File('${root.path}/pids');
      final interaction = File('${root.path}/interaction');
      final injected = File('${root.path}/must-not-exist');
      final secret = ' 密码\'"\$HOME;\$(touch "${injected.path}")\nnext line ';
      await executable.writeAsString(r'''#!/bin/bash
printf '%s' "$STEAMPASSWORD" > "$OUTPUT"
echo $$ > "$PID_FILE"
if [ -n "$INTERACTION_FILE" ]; then
  read -r guard
  printf '%s' "$guard" > "$INTERACTION_FILE"
fi
sleep 60 &
echo $! >> "$PID_FILE"
wait
''');
      await Process.run('chmod', ['700', executable.path]);
      expect(
          manager.start(
              'bridge',
              executable.path,
              [],
              {
                'STEAMPASSWORD': secret,
                'OUTPUT': output.path,
                'PID_FILE': pids.path,
                if (terminal &&
                    Platform.environment['NIPAPLAY_TEST_TERMINAL'] != '1')
                  'INTERACTION_FILE': interaction.path,
              },
              minimizedTerminal: terminal),
          isTrue);
      expect(manager.isRunning('bridge'), isTrue);
      expect(manager.start('bridge', executable.path, [], {}), isFalse);
      await waitFor(() => pids.existsSync());
      if (terminalProcess != null) {
        terminalProcess!.stdin.writeln('guard-code');
        await waitFor(() => interaction.existsSync());
        expect(await interaction.readAsString(), 'guard-code');
      }
      await waitFor(() => pids.readAsLinesSync().length == 2);
      expect(await output.readAsString(), secret);
      expect(injected.existsSync(), isFalse);
      final ids = (await pids.readAsLines()).map(int.parse).toList();
      await manager.shutdown();
      expect(manager.isRunning('bridge'), isFalse);
      expect(manager.start('bridge', executable.path, [], {}), isFalse);
      for (final id in ids) {
        final alive = await Process.run('/bin/kill', ['-0', '$id']);
        expect(alive.exitCode, isNot(0),
            reason: 'Process $id survived shutdown');
      }
    }, skip: Platform.isWindows || (terminal && !Platform.isMacOS));
  }

  test('terminal keeps failed Bridge output until Enter closes it', () async {
    Process? tty;
    var output = '';
    final manager = PluginProcessManager(terminalLauncher: (script) async {
      tty = await Process.start(
          '/usr/bin/script', ['-q', '/dev/null', '/bin/bash', script]);
      tty!.stdout.transform(const SystemEncoding().decoder).listen((data) {
        output += data;
      });
      unawaited(tty!.stderr.drain<void>());
    });
    addTearDown(manager.shutdown);
    expect(
        manager.start(
            'bridge', '/bin/sh', ['-c', 'echo login-failed; exit 7'], {},
            minimizedTerminal: true),
        isTrue);
    await waitFor(() => output.contains('code 7'));
    expect(output, contains('login-failed'));
    expect(manager.isRunning('bridge'), isTrue);
    tty!.stdin.writeln();
    await waitFor(() => !manager.isRunning('bridge'));
  }, skip: !Platform.isMacOS);

  test('immediate stop cancels a pending start', () async {
    final root = await Directory.systemTemp.createTemp('bridge-pending-');
    final marker = File('${root.path}/unexpected');
    final manager = PluginProcessManager();
    addTearDown(() => root.delete(recursive: true));
    expect(
        manager
            .start('bridge', '/bin/sh', ['-c', 'touch "${marker.path}"'], {}),
        isTrue);
    expect(manager.stop('bridge'), isTrue);
    await manager.shutdown();
    expect(marker.existsSync(), isFalse);
  }, skip: Platform.isWindows);

  test('stale exit callback cannot remove a replacement', () async {
    final manager = PluginProcessManager();
    addTearDown(manager.shutdown);
    expect(manager.start('bridge', '/bin/sleep', ['60'], {}), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(manager.stop('bridge'), isTrue);
    expect(manager.start('bridge', '/bin/sleep', ['60'], {}), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(manager.isRunning('bridge'), isTrue);
  }, skip: Platform.isWindows);

  test('failed launch releases reservation', () async {
    final manager = PluginProcessManager();
    addTearDown(manager.shutdown);
    expect(manager.start('bridge', '/nonexistent/nipaplay-bridge', [], {}),
        isTrue);
    await waitFor(() => !manager.isRunning('bridge'));
  });
}
