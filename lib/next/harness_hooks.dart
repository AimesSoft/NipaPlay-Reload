import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'harness_redaction.dart';
import 'harness_schedules.dart';

/// User programs execute once per accepted event, with persisted task receipts.
final class HarnessHooks implements JobExecutor {
  HarnessHooks(
      {this.timeout = const Duration(seconds: 60),
      this.scheduledTimeout = const Duration(minutes: 15)}) {
    schedules = HarnessSchedules(_scheduled, (error) async {
      await scheduleError?.call(error);
    });
  }
  final Duration timeout;
  final Duration scheduledTimeout;
  late final HarnessSchedules schedules;
  Future<void> Function(String error)? scheduleError;
  late TaskEngine engine;
  Future<void> Function(String event, String objectId, JsonMap payload)?
      observeEvent;
  Directory? _repository;
  File? _credentialFile;
  int _generation = DateTime.now().microsecondsSinceEpoch;
  final _processes = <String, Process>{};
  final _done = <String, Future<void>>{};
  Future<void> _submissions = Future.value();
  Future<void> drain() => _submissions;
  static const events = {
    'download.completed',
    'download.file_completed',
    'library.file_added',
    'playback.started',
    'playback.ended', 'playback.failed', 'playback.state_changed', 'playback.seek_requested',
    'settings.changed', 'media.assets.changed', 'media.sources.state_changed',
    'media.scan.completed', 'task.state_changed', 'network.state_changed',
    'cache.pruned', 'window.bounds_changed', 'storage.space_changed'
  };

  void enable(Directory repository, File credentialFile) {
    _generation++;
    _repository = repository;
    _credentialFile = credentialFile;
    schedules.enable(repository);
  }

  final _fileOccurrences = <String>{};

  Future<void> taskChanged(Job job) async {
    await fileCompletions(job);
    if (job.type == 'download' && job.state == JobState.succeeded) {
      await emit('download.completed', job.jobId, job.toJson());
    }
    if (const {'media.scan', 'media.scan_classic'}.contains(job.type) && job.state.isTerminal) {
      await emit('media.scan.completed', job.jobId,
          {'revision': job.revision, 'state': job.state.wireName, 'receipt': job.receipt?.toJson()});
    }
  }

  Future<void> fileCompletions(Job job) async {
    if (job.type == 'download') {
      for (final row in (job.checkpoint['completedFiles'] as List? ?? [])
          .cast<JsonMap>()) {
        final objectId = row['objectId'] as String;
        if (row['verification'] == 'verified' &&
            !_fileOccurrences.contains(objectId)) {
          await emit('download.file_completed', objectId, {
            'jobId': row['jobId'],
            'infoHash': job.input['infoHash'],
            'file': row,
          });
          _fileOccurrences.add(objectId);
        }
      }
    }
  }

  Future<void> disable() async {
    _generation++;
    await schedules.disable();
    _repository = null;
    _credentialFile = null;
    await _submissions;
    for (final process in _processes.values) {
      process.kill(
          Platform.isWindows ? ProcessSignal.sigterm : ProcessSignal.sigkill);
    }
    await Future.wait(_done.values.toList());
  }

  Future<void> _scheduled(JsonMap schedule, DateTime due) async {
    final repository = _repository;
    final credentialFile = _credentialFile;
    if (repository == null || credentialFile == null) return;
    final id = schedule['id'] as String;
    final jobs = await engine.list(type: type);
    if (jobs.any((job) =>
        !job.state.isTerminal &&
        job.input['repository'] == repository.path &&
        job.input['scheduleId'] == id)) {
      return;
    }
    await engine.submit(type: type, title: '定时脚本 $id', input: {
      'event': 'schedule',
      'objectId': id,
      'scheduleId': id,
      'occurredAt': due.toUtc().toIso8601String(),
      'data': schedule,
      'generation': _generation,
      'program': p.join(repository.path, schedule['program'] as String),
      'repository': repository.path,
      'credentialFile': credentialFile.path,
    }, details: {
      'event': 'schedule',
      'objectId': id
    });
  }

  Future<Job?> emit(String event, String objectId, JsonMap data) async {
    if (!events.contains(event) || objectId.isEmpty) {
      throw ArgumentError('Unknown hook event or empty objectId.');
    }
    final previous = _submissions;
    final done = Completer<void>();
    _submissions = done.future;
    await previous;
    try {
      final payload = redactHarnessJson({
        'eventId': '${DateTime.now().microsecondsSinceEpoch}-${_generation}',
        'event': event,
        'objectId': objectId,
        'entityId': objectId,
        'revision': data['revision'],
        'changedFields': data['changedFields'] ?? data.keys.toList(),
        'facts': data,
        'occurredAt': event == 'download.file_completed'
            ? (data['file'] as Map)['completedAt']
            : DateTime.now().toUtc().toIso8601String(),
        'data': data,
      }) as JsonMap;
      await observeEvent?.call(event, objectId, payload);
      final repository = _repository;
      final credentialFile = _credentialFile;
      if (repository == null || credentialFile == null) return null;
      String? program;
      for (final extension
          in Platform.isWindows ? ['.exe', '.cmd', '.bat', '.py'] : ['']) {
        final candidate =
            File(p.join(repository.path, 'hooks', '$event$extension'));
        if (await candidate.exists() &&
            (Platform.isWindows || (await candidate.stat()).mode & 0x49 != 0)) {
          program = candidate.path;
          break;
        }
      }
      if (program == null) return null;
      final eventKey =
          sha256.convert(utf8.encode(jsonEncode([event, objectId,
            if (!const {'download.completed', 'download.file_completed', 'library.file_added', 'playback.started'}.contains(event))
              payload['eventId']]))).toString();
      final jobs = await engine.list(type: type);
      for (final job in jobs) {
        if ((!job.state.isTerminal || event == 'download.file_completed') &&
            job.input['eventKey'] == eventKey) {
          return job;
        }
      }
      return engine.submit(type: type, title: 'Hook $event', input: {
        ...payload,
        'eventKey': eventKey,
        'generation': _generation,
        'program': program,
        'repository': repository.path,
        'credentialFile': credentialFile.path
      }, details: {
        'event': event,
        'objectId': payload['objectId']
      });
    } finally {
      done.complete();
    }
  }

  @override
  String get type => 'harness.hook';

  @override
  Future<void> execute(JobContext context) async {
    final completion = Completer<void>();
    _done[context.job.jobId] = completion.future;
    try {
      await _run(context);
    } finally {
      _processes.remove(context.job.jobId);
      _done.remove(context.job.jobId);
      completion.complete();
    }
  }

  @override
  Future<void> recover(JobContext context) => context.fail(
      const Failure(
          FailureCode.unavailable, 'Hook was interrupted; it was not rerun.'),
      JobReceipt(verification: VerificationLevel.unverified, details: {
        'exitCode': null,
        'elapsedMs': 0,
        'stdoutTail': '',
        'stderrTail': '',
        'reason': 'interrupted_no_replay'
      }));

  Future<void> _run(JobContext context) async {
    final input = context.job.input;
    final stopwatch = Stopwatch()..start();
    final out = _OutputTail(), err = _OutputTail();
    var timedOut = false;
    var stopped = false;
    int? exitCode;
    String? launchError;
    if (_repository?.path != input['repository'] ||
        input['generation'] != _generation) {
      launchError = 'Next is disabled or the harness changed.';
    } else {
      await context.report(phase: 'execute');
      final program = input['program'] as String;
      try {
        final Process process;
        final environment = {
          'NIPAPLAY_HOOK': context.job.jobId,
          'NIPAPLAY_ENDPOINT_FILE': input['credentialFile'] as String
        };
        if (Platform.isWindows && p.extension(program) == '.py') {
          process = await Process.start('python', [program],
              workingDirectory: input['repository'] as String,
              environment: environment);
        } else {
          process = await Process.start(program, [],
              workingDirectory: input['repository'] as String,
              environment: environment,
              runInShell: Platform.isWindows &&
                  {'.cmd', '.bat'}.contains(p.extension(program)));
        }
        _processes[context.job.jobId] = process;
        await context.markSideEffectCommitted();
        final stdoutDone = Completer<void>(), stderrDone = Completer<void>();
        final stdout = process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(out.add, onDone: stdoutDone.complete);
        final stderr = process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(err.add, onDone: stderrDone.complete);
        final deadline = Completer<int?>();
        final timer =
            Timer(input['scheduleId'] == null ? timeout : scheduledTimeout, () {
          timedOut = true;
          deadline.complete(null);
          process.kill(Platform.isWindows
              ? ProcessSignal.sigterm
              : ProcessSignal.sigkill);
        });
        final stop = Completer<int?>();
        context.stopRequested.then((_) {
          stopped = true;
          stop.complete(null);
          process.kill(Platform.isWindows
              ? ProcessSignal.sigterm
              : ProcessSignal.sigkill);
        });
        if (_repository?.path != input['repository'] ||
            input['generation'] != _generation) {
          stopped = true;
          process.kill(Platform.isWindows
              ? ProcessSignal.sigterm
              : ProcessSignal.sigkill);
        }
        try {
          process.stdin.add(utf8.encode(jsonEncode({
            for (final key in ['eventId', 'event', 'objectId', 'entityId', 'occurredAt', 'revision', 'changedFields', 'facts', 'data'])
              key: input[key]
          })));
          // A hook is allowed to exit without consuming all of stdin.
          unawaited(() async {
            try {
              await process.stdin.close();
            } on IOException catch (error) {
              err.add('stdin: ${redactHarnessText(error.toString())}\n');
            }
          }());
          exitCode = await Future.any(
              [process.exitCode, deadline.future, stop.future]);
          exitCode ??= await process.exitCode
              .timeout(const Duration(seconds: 1), onTimeout: () => -1);
          // The same deadline bounds descendants that retain pipe handles.
          await Future.any([
            Future.wait([stdoutDone.future, stderrDone.future]).then((_) {}),
            deadline.future.then((_) {}),
            stop.future.then((_) {}),
          ]);
        } finally {
          timer.cancel();
          await stdout.cancel();
          await stderr.cancel();
        }
      } on ProcessException catch (error) {
        launchError = redactHarnessText(error.toString());
      }
    }
    final receipt = JobReceipt(
        verification: exitCode == 0 && !timedOut && !stopped
            ? VerificationLevel.verified
            : VerificationLevel.unverified,
        details: {
          'exitCode': exitCode,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'timedOut': timedOut,
          'stdoutTail': out.text,
          'stderrTail': err.text,
          if (launchError != null) 'launchError': launchError
        });
    final current = await context.snapshot();
    if (current.cancelRequestedAt != null) {
      await context.cancelled(receipt);
    } else if (exitCode == 0 && !timedOut && !stopped) {
      await context.succeed(receipt);
    } else {
      await context.fail(
          Failure(
              FailureCode.unavailable,
              launchError ??
                  (timedOut
                      ? 'Hook timed out.'
                      : 'Hook exited with $exitCode.')),
          receipt);
    }
  }
}

/// Sanitize whole lines before retaining a tail. An oversized unfinished line is
/// omitted entirely, so trimming never exposes part of a known secret.
final class _OutputTail {
  String _tail = '', _line = '';
  bool _discardLine = false;
  void add(String chunk) {
    final parts = chunk.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (!_discardLine) {
        _line += parts[i];
        if (_line.length > 65536) {
          _line = '';
          _discardLine = true;
        }
      }
      if (i < parts.length - 1) {
        _retain(_discardLine
            ? '[oversized line omitted]\n'
            : '${redactHarnessText(_line)}\n');
        _line = '';
        _discardLine = false;
      }
    }
  }

  void _retain(String value) {
    _tail += value;
    if (_tail.length > 8192) _tail = _tail.substring(_tail.length - 8192);
  }

  String get text {
    final value = _tail +
        (_discardLine ? '[oversized line omitted]' : redactHarnessText(_line));
    return value.length > 8192 ? value.substring(value.length - 8192) : value;
  }
}
