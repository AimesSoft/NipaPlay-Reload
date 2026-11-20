import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Owns plugin processes, including launches still waiting for a terminal.
class PluginProcessManager {
  PluginProcessManager({this.terminalLauncher, this.onLog});

  /// Allows tests to run the terminal wrapper in a pseudo-TTY without UI.
  final Future<void> Function(String scriptPath)? terminalLauncher;
  final void Function(String message)? onLog;
  final Map<String, _PluginProcess> _processes = {};
  final Set<Future<void>> _stopping = {};
  bool _closing = false;

  bool isRunning(String id) => _processes.containsKey(id);

  bool start(String id, String executable, List<String> arguments,
      Map<String, String> environment,
      {bool minimizedTerminal = false}) {
    if (_closing || executable.isEmpty || _processes.containsKey(id)) {
      return false;
    }
    if (minimizedTerminal &&
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return false;
    }
    if (environment.keys
        .any((key) => !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key))) {
      return false;
    }
    final previousStops = Future.wait(_stopping.toList());
    final owned = _PluginProcess(
        terminalLauncher, (message) => onLog?.call('[Plugin:$id] $message'));
    _processes[id] = owned;
    owned.ready = previousStops
        .then((_) => owned.launch(executable, arguments, environment,
            minimizedTerminal: minimizedTerminal))
        .catchError((Object error) {
      // Do not print launch commands or configuration containing credentials.
      final detail = error is StateError ? error.message : error.runtimeType;
      stderr.writeln('[Plugin:$id] 外部进程启动失败: $detail');
    }).whenComplete(() {
      if (owned.pid == null && identical(_processes[id], owned)) {
        _processes.remove(id);
      }
    });
    unawaited(owned.ready.then((_) async {
      // stop() owns cleanup while cancellation is in progress. In particular,
      // preserve the PID/stop files until it has completed the terminal handshake.
      if (owned._cancelled) return;
      if (owned.pid == null) {
        await owned.cleanup();
        return;
      }
      await owned.exited;
      if (identical(_processes[id], owned)) _processes.remove(id);
      if (!owned._cancelled) await owned.cleanup();
    }));
    return true; // Accepted; OS launch errors are asynchronous.
  }

  bool stop(String id) {
    final owned = _processes.remove(id);
    if (owned == null) return false;
    final stopping = owned.stop();
    _stopping.add(stopping);
    unawaited(stopping.whenComplete(() => _stopping.remove(stopping)));
    return true;
  }

  Future<void> shutdown() async {
    _closing = true;
    for (final id in _processes.keys.toList()) {
      stop(id);
    }
    await Future.wait(_stopping.toList());
  }
}

class _PluginProcess {
  _PluginProcess(this.terminalLauncher, this.onLog);

  final Future<void> Function(String scriptPath)? terminalLauncher;
  final void Function(String message) onLog;
  late Future<void> ready;
  int? pid;
  Directory? _directory;
  Timer? _poll;
  Process? _launcher;
  int? _terminalWindowId;
  bool _cancelled = false;
  final Completer<void> _exit = Completer<void>();
  Future<void> get exited => _exit.future;

  static String _sh(String text) => "'${text.replaceAll("'", "'\\''")}'";
  static String _ps(String text) => "'${text.replaceAll("'", "''")}'";

  Future<void> launch(String executable, List<String> arguments,
      Map<String, String> environment,
      {required bool minimizedTerminal}) async {
    if (_cancelled) return;
    final file = File(executable).absolute;
    final cwd = executable.contains('/') || executable.contains('\\')
        ? file.parent.path
        : null;
    if (!minimizedTerminal) {
      final process = await Process.start(executable, arguments,
          workingDirectory: cwd, environment: environment);
      pid = process.pid;
      process.stdout.transform(utf8.decoder).listen((data) {
        onLog('stdout: ${data.trim()}');
      });
      process.stderr.transform(utf8.decoder).listen((data) {
        onLog('stderr: ${data.trim()}');
      });
      unawaited(process.exitCode.then((_) => _completeExit()));
      return;
    }

    final directory = await Directory.systemTemp.createTemp('nipaplay-plugin-');
    _directory = directory;
    if (!Platform.isWindows) {
      await Process.run('chmod', ['700', directory.path]);
    }
    final pidFile = File('${directory.path}/pid');
    final doneFile = File('${directory.path}/done');
    final target = cwd == null ? executable : file.path;
    if (Platform.isWindows) {
      final script = File('${directory.path}/launch.ps1');
      await script.writeAsString('\uFEFF${[
        r"$ErrorActionPreference = 'Stop'",
        '\$PID | Set-Content -LiteralPath ${_ps(pidFile.path)}',
        if (cwd != null) 'Set-Location -LiteralPath ${_ps(cwd)}',
        for (final entry in environment.entries)
          '[Environment]::SetEnvironmentVariable(${_ps(entry.key)}, ${_ps(entry.value)}, "Process")',
        'try {',
        '& ${_ps(target)} ${arguments.map(_ps).join(' ')}',
        r'if ($LASTEXITCODE -ne 0) { Read-Host "Bridge exited with code $LASTEXITCODE. Press Enter to close" }',
        '} catch { Write-Host \$_; Read-Host "Press Enter to close" }',
        "finally { New-Item -ItemType File -Path ${_ps(doneFile.path)} -Force | Out-Null }",
      ].join('\r\n')}');
      // Configuration stays in the private launcher file, never a shell command.
      final command = 'Start-Process powershell.exe -WindowStyle Minimized '
          '-ArgumentList @(\'-NoProfile\', \'-ExecutionPolicy\', \'Bypass\', \'-File\', '
          '${_ps('"${script.path}"')})';
      final encoded = base64Encode([
        for (final unit in command.codeUnits) ...[unit & 255, unit >> 8],
      ]);
      await _runLauncher('powershell.exe',
          ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded]);
    } else {
      final script = File('${directory.path}/launch.sh');
      await script.writeAsString([
        '#!/bin/bash',
        'echo \$\$ > ${_sh(pidFile.path)} || exit 1',
        'child=',
        'watcher=',
        'stop_tree() { local kid; for kid in \$(pgrep -P "\$1"); do stop_tree "\$kid"; done; kill -TERM "\$1" 2>/dev/null; sleep 0.1; kill -KILL "\$1" 2>/dev/null; }',
        'finish() { trap - TERM INT HUP; [ -z "\$child" ] || { stop_tree "\$child"; wait "\$child" 2>/dev/null; }; [ -z "\$watcher" ] || { stop_tree "\$watcher"; wait "\$watcher" 2>/dev/null; }; touch ${_sh(doneFile.path)}; exit 0; }',
        'trap finish TERM INT HUP',
        if (cwd != null) 'cd ${_sh(cwd)} || exit 1',
        for (final entry in environment.entries)
          'export ${entry.key}=${_sh(entry.value)}',
        // A background command otherwise gets /dev/null as stdin, breaking Guard.
        '${_sh(target)} ${arguments.map(_sh).join(' ')} < /dev/tty &',
        'child=\$!',
        'owner=\$\$',
        '( while [ ! -e ${_sh('${directory.path}/stop')} ]; do sleep 0.2; done; kill -TERM "\$owner" ) &',
        'watcher=\$!',
        'wait "\$child"',
        'code=\$?',
        'child=',
        'if [ "\$code" -ne 0 ]; then',
        '  echo "Bridge exited with code \$code. Press Enter to close."',
        '  read -r',
        'fi',
        'finish',
      ].join('\n'));
      final command = 'exec /bin/bash ${_sh(script.path)}';
      if (terminalLauncher != null) {
        await terminalLauncher!(script.path);
      } else if (Platform.isMacOS) {
        final result = await _runLauncher('/usr/bin/osascript', [
          '-e',
          'tell application "Terminal"\n'
              'do script ${jsonEncode(command)}\n'
              'set miniaturized of front window to true\n'
              'return id of front window\nend tell',
        ]);
        _terminalWindowId = int.tryParse(result.trim());
      } else {
        // These terminals provide an explicit minimized/iconic launch option.
        Process? terminal;
        for (final candidate in [
          ['xterm', '-iconic', '-T', 'NipaPlay Bridge', '-e'],
          ['konsole', '--separate', '--minimized', '-e'],
        ]) {
          try {
            terminal = await Process.start(candidate.first,
                [...candidate.skip(1), '/bin/bash', script.path]);
            break;
          } on ProcessException {
            continue;
          }
        }
        if (terminal == null) {
          throw StateError('Install xterm or Konsole for a minimized terminal');
        }
        unawaited(terminal.stdout.drain<void>());
        unawaited(terminal.stderr.drain<void>());
      }
    }

    // The terminal launcher PID is not the Bridge's owner PID.
    for (var i = 0; i < 100; i++) {
      if (_cancelled) return;
      if (await pidFile.exists()) {
        pid = int.tryParse((await pidFile.readAsString()).trim());
        if (pid != null) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (pid == null) throw StateError('Terminal did not acknowledge launch');
    var checking = false;
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (checking) return;
      checking = true;
      try {
        if (await doneFile.exists() ||
            (Platform.isWindows && !await _alive(pid!))) {
          _completeExit();
        }
      } finally {
        checking = false;
      }
    });
  }

  Future<String> _runLauncher(String command, List<String> arguments) async {
    if (_cancelled) return '';
    final launcher = await Process.start(command, arguments);
    _launcher = launcher;
    final output = launcher.stdout.transform(utf8.decoder).join();
    unawaited(launcher.stderr.drain<void>());
    if (_cancelled) launcher.kill();
    try {
      final code = await launcher.exitCode.timeout(const Duration(seconds: 15),
          onTimeout: () {
        launcher.kill();
        throw StateError(
            'Terminal launch timed out; check terminal permissions');
      });
      if (code != 0 && !_cancelled) {
        throw StateError('Terminal launch failed (code=$code)');
      }
      return await output;
    } finally {
      _launcher = null;
    }
  }

  static Future<bool> _alive(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
            'tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
        return result.stdout.toString().contains('"$pid"');
      }
      return (await Process.run('/bin/kill', ['-0', '$pid'])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  void _completeExit() {
    _poll?.cancel();
    if (!_exit.isCompleted) _exit.complete();
  }

  Future<void> stop() async {
    _cancelled = true;
    _poll?.cancel();
    _launcher?.kill();
    await ready;
    // A terminal may have written its PID just as cancellation arrived.
    final directory = _directory;
    if (pid == null && directory != null) {
      final file = File('${directory.path}/pid');
      if (await file.exists()) {
        pid = int.tryParse((await file.readAsString()).trim());
      }
    }
    final owner = pid;
    if (owner != null && !_exit.isCompleted) {
      if (!Platform.isWindows && directory != null) {
        // The terminal owns this process outside the macOS app sandbox. Ask its
        // wrapper to stop the tree, rather than relying on cross-sandbox signals.
        await File('${directory.path}/stop').writeAsString('stop');
        for (var attempt = 0; attempt < 10; attempt++) {
          if (await File('${directory.path}/done').exists()) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      } else if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '$owner', '/T', '/F']);
      } else {
        // Snapshot descendants before signaling the wrapper, which may reap them.
        final result = await Process.run('ps', ['-axo', 'pid=,ppid=']);
        final children = <int, List<int>>{};
        for (final line in result.stdout.toString().split('\n')) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length != 2) continue;
          final child = int.tryParse(parts[0]);
          final parent = int.tryParse(parts[1]);
          if (child != null && parent != null) {
            children.putIfAbsent(parent, () => []).add(child);
          }
        }
        final descendants = <int>[];
        void collect(int parent) {
          for (final child in children[parent] ?? <int>[]) {
            collect(child);
            descendants.add(child);
          }
        }

        collect(owner);
        for (final child in [...descendants, owner]) {
          Process.killPid(child, ProcessSignal.sigterm);
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        for (final child in [...descendants, owner]) {
          if (await _alive(child)) {
            Process.killPid(child, ProcessSignal.sigkill);
          }
        }
      }
    }
    _completeExit();
    await cleanup();
  }

  Future<void> cleanup() async {
    _poll?.cancel();
    final windowId = _terminalWindowId;
    _terminalWindowId = null;
    if (windowId != null) {
      final closer = await Process.start('/usr/bin/osascript', [
        '-e',
        'tell application "Terminal" to close window id $windowId saving no',
      ]);
      unawaited(closer.stdout.drain<void>());
      unawaited(closer.stderr.drain<void>());
      await closer.exitCode.timeout(const Duration(seconds: 1), onTimeout: () {
        closer.kill();
        return -1;
      });
    }
    final directory = _directory;
    _directory = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
