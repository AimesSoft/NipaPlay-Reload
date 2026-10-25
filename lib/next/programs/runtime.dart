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
      // Python on Windows reads and writes pipes in the console code page
      // (GBK, ...); the scripts Nipa runs speak UTF-8 (tools/README.md).
      if (Platform.isWindows) ...{
        'PYTHONUTF8': '1',
        'PYTHONIOENCODING': 'utf-8',
      },
    };

/// What to start for [command], and the environment values it needs.
///
/// Dart quotes each argument for the Windows command line with backslash
/// escapes, which cmd.exe does not read: a command with a double quote in it
/// (a path with spaces, nearly any real command) reached `cmd /c` broken. The
/// command therefore travels in an environment variable that cmd expands
/// itself, so it parses exactly the text Nipa wrote.
({String executable, List<String> arguments, Map<String, String> environment})
    programCommand(String command, String shell, {required bool windows}) {
  if (shell == 'default') shell = windows ? 'cmd' : 'sh';
  if (windows && shell == 'cmd') {
    return (
      executable: 'cmd.exe',
      // chcp makes cmd's own output UTF-8, which is what is read back.
      arguments: ['/d', '/s', '/c', 'chcp 65001>nul&%$programCommandVariable%'],
      environment: {programCommandVariable: command},
    );
  }
  if (windows && shell == 'powershell') {
    // Windows PowerShell writes a pipe in the console code page unless told.
    const utf8 = r'[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false; '
        r'$OutputEncoding = [Console]::OutputEncoding; ';
    return (
      executable: 'powershell.exe',
      arguments: [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        base64Encode(
            (utf8 + command).codeUnits.expand((u) => [u & 255, u >> 8]).toList())
      ],
      environment: const {},
    );
  }
  if (!windows && shell == 'sh') {
    return (
      executable: '/bin/sh',
      arguments: ['-c', command],
      environment: const {},
    );
  }
  throw const Failure(FailureCode.invalidInput,
      'Windows supports cmd/powershell; POSIX hosts support sh.');
}

/// The variable a Windows cmd command is handed to the shell in.
const programCommandVariable = 'NIPAPLAY_PROGRAM_COMMAND';

final class ProgramRuntime implements JobExecutor {
  ProgramRuntime({required this.enabled, required this.location});
  bool enabled;
  final RepositoryLocation location;
  File? credentialFile;
  late TaskEngine engine;
  Future<JsonMap?> Function(Invocation)? returnTarget;
  final _active = <Future<void>>{};
  bool _closed = false;

  /// Why NipaPlay itself stopped a program, by job, for its receipt.
  final _cancelReasons = <String, String>{};
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
        // Who asked is the task's own origin (a kernel field), not a detail.
        details: {
          for (final fact in facts.entries)
            if (fact.key != 'origin') fact.key: fact.value,
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
    // Cancelled before it ran (left waiting while Next's interface was
    // closed): nothing is started only to be stopped.
    if ((await context.snapshot()).state == JobState.cancelling) {
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.verified,
          details: {
            ...context.job.details,
            'started': false,
            if (_cancelReasons.remove(context.job.jobId) case final reason?)
              'cancelReason': reason,
          }));
      return;
    }
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
          ...command.environment,
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
    JsonMap? termination;
    JsonMap details() => {
          ...context.job.details,
          'stdoutTail': out.value,
          'stderrTail': err.value,
          'exitCode': exitCode,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'timedOut': timedOut,
          'stopped': stopped,
          'pid': process.pid,
          if (termination != null) 'termination': termination,
          if (_cancelReasons[context.job.jobId] case final reason?)
            'cancelReason': reason,
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
      termination = await stopProgramTree(process);
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
    _cancelReasons.remove(context.job.jobId);
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

  /// Cancels every program not finished yet and returns once each process
  /// tree is gone. [reason] goes into the receipt (`cancelReason`), where
  /// Nipa reads why it ended.
  Future<void> cancelRunning({required String reason}) async {
    for (final job in await engine.list(type: type)) {
      if (job.state.isTerminal) continue;
      _cancelReasons[job.jobId] = reason;
      final cancelled = await engine.cancel(job.jobId);
      // One that never started ends at once, with the engine's receipt.
      if (cancelled.state == JobState.cancelled) {
        _cancelReasons.remove(job.jobId);
        await engine.amendReceipt(
            job.jobId,
            JobReceipt(
                verification: cancelled.receipt?.verification ??
                    VerificationLevel.unverified,
                details: {
                  ...?cancelled.receipt?.details,
                  'cancelReason': reason,
                }));
      }
    }
    await Future.wait(_active.toList());
  }

  Future<void> close() async {
    _closed = true;
    await cancelRunning(reason: 'nipaplay_closing');
  }
}

/// How long a program has after TERM before it is killed.
const programStopGrace = Duration(seconds: 2);

/// Ends [process] and every process it started: TERM to the whole tree
/// first, then KILL to what is still there after [grace]. Returns what was
/// done, for the receipt; null when nothing of it was left running.
Future<JsonMap?> stopProgramTree(Process process,
    {Duration grace = programStopGrace}) async {
  final watch = Stopwatch()..start();
  var exited = false;
  unawaited(process.exitCode.then((_) => exited = true));
  if (Platform.isWindows) {
    // Nothing of it left to stop: as on POSIX, no termination to report.
    if (await process.exitCode
        .then((_) => true)
        .timeout(const Duration(milliseconds: 5), onTimeout: () => false)) {
      return null;
    }
    Future<void> taskkill(bool force) => Process.run('taskkill.exe',
        ['/PID', '${process.pid}', '/T', if (force) '/F'],
        environment: programEnvironment(), includeParentEnvironment: false);
    await taskkill(false);
    final ended = await process.exitCode
        .then((_) => true)
        .timeout(grace, onTimeout: () => false);
    if (!ended) {
      await taskkill(true);
      process.kill();
    }
    return {
      'signal': 'taskkill',
      'forced': !ended,
      'elapsedMs': watch.elapsedMilliseconds,
    };
  }
  // The tree as it is now: once the shell is gone its children belong to
  // launchd, and only these pids still name them.
  bool running(int pid) =>
      pid == process.pid ? !exited : _signal(pid, ProcessSignal.sigcont);
  final tree = await _descendants([process.pid]);
  var alive = [
    for (final pid in [process.pid, ...?tree])
      if (running(pid)) pid
  ];
  if (alive.isEmpty) return null;
  final signaled = List.of(alive);
  for (final pid in alive) {
    _signal(pid, ProcessSignal.sigterm);
  }
  while (watch.elapsed < grace) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    alive = [
      for (final pid in alive)
        if (running(pid)) pid
    ];
    if (alive.isEmpty) break;
  }
  // Whatever the survivors started meanwhile goes with them.
  if (alive.isNotEmpty) {
    alive = {...alive, ...?await _descendants(alive)}.toList();
    for (final pid in alive) {
      _signal(pid, ProcessSignal.sigkill);
    }
    if (alive.contains(process.pid)) process.kill(ProcessSignal.sigkill);
  }
  return {
    'signaled': signaled,
    'killed': alive,
    'graceMs': grace.inMilliseconds,
    'elapsedMs': watch.elapsedMilliseconds,
    if (tree == null) 'descendantsUnknown': true,
  };
}

bool _signal(int pid, ProcessSignal signal) {
  try {
    return Process.killPid(pid, signal);
  } on ArgumentError {
    return false;
  }
}

/// Every process under [roots], level by level, from pgrep (ps is setuid,
/// which a sandboxed NipaPlay, such as a lab instance, may not run). Null
/// when pgrep cannot be run.
Future<List<int>?> _descendants(List<int> roots) async {
  final found = <int>[];
  var level = roots;
  while (level.isNotEmpty) {
    final ProcessResult result;
    try {
      result = await Process.run('/usr/bin/pgrep', ['-P', level.join(',')],
          environment: programEnvironment(), includeParentEnvironment: false);
    } on ProcessException {
      return null;
    }
    // 1: no process matched.
    if (result.exitCode > 1) return null;
    level = [
      for (final line in const LineSplitter().convert(result.stdout as String))
        if (int.tryParse(line.trim()) case final pid?)
          if (!found.contains(pid) && !roots.contains(pid)) pid
    ];
    found.addAll(level);
  }
  return found;
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
                      'Run a command/script as an ordinary-user background task in this device harness. Disabled by default; only the target host can enable it. No caller environment or credentials are transferred. Windows defaults to cmd (optional powershell), POSIX to sh. task.get/wait expose redacted output tails, exit code and elapsed time; task.cancel stops the process tree (TERM, then KILL after 2 s; receipt termination lists what was signaled and killed). Closing Next\'s interface cancels programs still running, receipt cancelReason next_interface_closed. Interrupted commands are not replayed. Completion returns to the originating conversation unless followup:false. Deletion and overwriting require user authorization.',
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
