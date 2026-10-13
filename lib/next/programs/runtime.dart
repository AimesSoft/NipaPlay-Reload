import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import '../capabilities/classic_action.dart';
import '../harness_redaction.dart';
import '../repository_location.dart';

/// Host configuration. There is no Action or registry setting that writes it.
Future<bool> loadProgramPermission(Directory root) async {
  final file = File('${root.path}/program.json');
  if (!await file.exists()) return false;
  final value = jsonDecode(await file.readAsString());
  if (value is! Map || value['enabled'] is! bool) {
    throw const FormatException('program.json requires a boolean enabled.');
  }
  return value['enabled'] as bool;
}

/// Only target-host operating-system essentials are inherited. No caller env.
Map<String, String> programEnvironment() => {
      for (final entry in Platform.environment.entries)
        if (const {
          'path',
          'home',
          'user',
          'logname',
          'lang',
          'lc_all',
          'lc_ctype',
          'tmpdir',
          'tmp',
          'temp',
          'systemroot',
          'windir',
          'comspec',
          'pathext',
          'userprofile',
          'appdata',
          'localappdata',
        }.contains(entry.key.toLowerCase()))
          entry.key: entry.value,
    };

({String executable, List<String> arguments}) programCommand(
    String command, String shell,
    {required bool windows}) {
  if (shell == 'default') shell = windows ? 'cmd' : 'sh';
  if (windows && shell == 'cmd') {
    return (executable: 'cmd.exe', arguments: ['/d', '/s', '/c', command]);
  }
  if (windows && shell == 'powershell') {
    return (
      executable: 'powershell.exe',
      arguments: [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        base64Encode(
            command.codeUnits.expand((u) => [u & 255, u >> 8]).toList())
      ]
    );
  }
  if (!windows && shell == 'sh') {
    return (executable: '/bin/sh', arguments: ['-c', command]);
  }
  throw const Failure(FailureCode.invalidInput,
      'Windows supports cmd/powershell; POSIX hosts support sh.');
}

final class ProgramRuntime implements JobExecutor {
  ProgramRuntime({required this.enabled, required this.location});
  bool enabled;
  final RepositoryLocation location;
  File? credentialFile;
  late TaskEngine engine;
  Future<JsonMap?> Function(Invocation)? returnTarget;
  final _active = <Future<void>>{};
  bool _closed = false;
  @override
  String get type => 'program';

  void requireEnabled() {
    if (!enabled || _closed) {
      throw const Failure(FailureCode.unavailable,
          'Program execution is disabled. Only this device host can enable program.json.');
    }
  }

  Future<JsonMap> submit(JsonMap input, Invocation invocation) async {
    requireEnabled();
    await location.ready;
    final command = input['command'] as String;
    if (command.length > 65536 || (input['title'] as String).length > 256) {
      throw const Failure(
          FailureCode.invalidInput, 'Command/title exceeds size limit.');
    }
    // Credentials belong in target-host files, not persisted command text.
    if (redactHarnessText(command) != command ||
        redactHarnessText(input['title'] as String) != input['title']) {
      throw const Failure(FailureCode.invalidInput,
          'Command/title contains private data. Reference target-local credentials instead.');
    }
    final shell = input['shell'] as String? ?? 'default';
    programCommand(command, shell, windows: Platform.isWindows);
    final target = input['followup'] == false
        ? null
        : await returnTarget?.call(invocation);
    final facts = <String, Object?>{
      'command': command,
      'shell': shell,
      'repository': location.path,
      'origin': invocation.origin,
      'invocationId': invocation.id,
      'timeoutSeconds': input['timeoutSeconds'] ?? 900,
    };
    final job = await engine.submit(
        type: type,
        title: input['title'] as String,
        input: {
          ...facts,
          if (target != null) 'returnTo': target
        },
        details: {
          ...facts,
          'stdoutTail': '',
          'stderrTail': '',
          'exitCode': null,
          'elapsedMs': 0
        });
    return {'jobId': job.jobId, 'job': job.toJson()};
  }

  Capability get capability => _ProgramCapability(this);

  @override
  Future<void> execute(JobContext context) async {
    final done = Completer<void>();
    _active.add(done.future);
    try {
      await _execute(context);
    } finally {
      _active.remove(done.future);
      done.complete();
    }
  }

  Future<void> _execute(JobContext context) async {
    requireEnabled();
    final input = context.job.input;
    final command = programCommand(
        input['command'] as String, input['shell'] as String,
        windows: Platform.isWindows);
    final stopwatch = Stopwatch()..start();
    final out = ProgramOutputTail(), err = ProgramOutputTail();
    final process = await Process.start(command.executable, command.arguments,
        workingDirectory: input['repository'] as String,
        environment: {
          ...programEnvironment(),
          if (credentialFile != null)
            'NIPAPLAY_ENDPOINT_FILE': credentialFile!.path
        },
        includeParentEnvironment: false);
    await process.stdin.close();
    final outDone = Completer<void>(), errDone = Completer<void>();
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(out.add, onDone: outDone.complete);
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(err.add, onDone: errDone.complete);
    Timer? timeout, publication;
    Future<void> reports = Future.value();
    var stopped = false, timedOut = false, finished = false;
    int? exitCode;
    JsonMap details() => {
          ...context.job.details,
          'stdoutTail': out.value,
          'stderrTail': err.value,
          'exitCode': exitCode,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'timedOut': timedOut,
          'stopped': stopped,
          'pid': process.pid,
        };
    try {
      await context.markSideEffectCommitted();
      await context.report(phase: 'execute', details: details());
      publication = Timer.periodic(const Duration(seconds: 1), (_) {
        reports = reports.then((_) async {
          if (!finished) await context.report(details: details());
        });
      });
      final deadline = Completer<void>();
      timeout = Timer(Duration(seconds: input['timeoutSeconds'] as int), () {
        timedOut = true;
        deadline.complete();
      });
      final reason = await Future.any([
        process.exitCode.then((code) {
          exitCode = code;
          return 'exit';
        }),
        deadline.future.then((_) => 'timeout'),
        context.stopRequested.then((_) => 'stop'),
      ]);
      stopped = reason == 'stop';
    } finally {
      timeout?.cancel();
      publication?.cancel();
      finished = true;
      // Descendants can keep pipes open even when the shell has exited.
      await stopProgramTree(process);
      exitCode ??= await process.exitCode;
      await Future.wait([outDone.future, errDone.future])
          .timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
      await stdout.cancel();
      await stderr.cancel();
      await reports;
      stopwatch.stop();
    }
    final receipt = JobReceipt(
        verification: VerificationLevel.verified, details: details());
    final latest = await context.snapshot();
    if (latest.state == JobState.cancelling) {
      await context.cancelled(receipt);
    } else if (timedOut || stopped || exitCode != 0) {
      await context.fail(
          Failure(
              FailureCode.unavailable,
              timedOut
                  ? 'Program timed out.'
                  : stopped
                      ? 'Program stopped.'
                      : 'Program exited with code $exitCode.'),
          receipt);
    } else {
      await context.succeed(receipt);
    }
  }

  @override
  Future<void> recover(JobContext context) => context.fail(
      const Failure(FailureCode.unavailable,
          'Program was interrupted; commands are never replayed automatically.'),
      JobReceipt(verification: VerificationLevel.unverified, details: {
        ...context.job.details,
        'reason': 'interrupted_no_replay'
      }));

  Future<void> close() async {
    _closed = true;
    for (final job in await engine.list(type: type)) {
      if (!job.state.isTerminal) await engine.cancel(job.jobId);
    }
    await Future.wait(_active.toList());
  }
}

Future<void> stopProgramTree(Process process) async {
  if (Platform.isWindows) {
    await Process.run('taskkill.exe', ['/PID', '${process.pid}', '/T', '/F'],
        environment: programEnvironment(), includeParentEnvironment: false);
    process.kill();
    return;
  }
  final tree = await Process.run('/bin/ps', ['-axo', 'pid=,ppid='],
      environment: programEnvironment(), includeParentEnvironment: false);
  if (tree.exitCode != 0) {
    process.kill(ProcessSignal.sigkill);
    throw const Failure(
        FailureCode.unavailable, 'Cannot inspect program process tree.');
  }
  final children = <int, List<int>>{};
  for (final line in const LineSplitter().convert(tree.stdout as String)) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length == 2) {
      (children[int.parse(fields[1])] ??= []).add(int.parse(fields[0]));
    }
  }
  void killChildren(int pid) {
    for (final child in children[pid] ?? <int>[]) {
      killChildren(child);
      Process.killPid(child, ProcessSignal.sigkill);
    }
  }

  killChildren(process.pid);
  process.kill(ProcessSignal.sigkill);
}

/// Retain complete redacted lines, and never expose an overlong partial line.
final class ProgramOutputTail {
  String _safe = '', _line = '';
  bool _discard = false;
  void add(String value) {
    for (final part in value.split('\n').indexed) {
      if (part.$1 > 0) {
        _safe +=
            _discard ? '[truncated line]\n' : '${redactHarnessText(_line)}\n';
        if (_safe.length > 8192) _safe = _safe.substring(_safe.length - 8192);
        _line = '';
        _discard = false;
      }
      if (!_discard) {
        _line += part.$2;
        if (_line.length > 16384) {
          _line = '';
          _discard = true;
        }
      }
    }
  }

  String get value {
    final text =
        '$_safe${_discard ? '[truncated line]' : redactHarnessText(_line)}';
    return text.length > 8192 ? text.substring(text.length - 8192) : text;
  }
}

final class _ProgramCapability implements Capability {
  _ProgramCapability(ProgramRuntime runtime)
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'program.run',
                  title: '在设备上运行程序',
                  description:
                      'Run a command/script as an ordinary-user background task in this device harness. Disabled by default; only the target host can enable it. No caller environment or credentials are transferred. Windows defaults to cmd (optional powershell), POSIX to sh. task.get/wait expose redacted output tails, exit code and elapsed time; task.cancel stops the process tree. Interrupted commands are not replayed. Completion returns to the originating conversation unless followup:false. Deletion and overwriting require user authorization.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'title': StringSchema(minLength: 1, secret: true),
                    'command': StringSchema(minLength: 1, secret: true),
                    'shell': StringSchema(
                        values: ['default', 'sh', 'cmd', 'powershell']),
                    'timeoutSeconds': IntegerSchema(minimum: 1, maximum: 3600),
                    'followup': BooleanSchema(),
                  }, required: [
                    'title',
                    'command'
                  ]),
                  output: ObjectSchema({}, additionalProperties: true)),
              runtime.submit)
        ];
  @override
  final List<Action> actions;
}
