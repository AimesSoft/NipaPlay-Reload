import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

/// Calendar policy is supplied by the harness. No missed tick is replayed.
final class HarnessSchedules {
  HarnessSchedules(this.submit, this.reportError);
  final Future<void> Function(JsonMap schedule, DateTime due) submit;
  final Future<void> Function(String error) reportError;
  final _next = <String, DateTime>{};
  final _definitions = <String, String>{};
  Directory? _repository;
  Timer? _timer;
  Future<void> _ticks = Future.value();
  String? _invalid;
  DateTime? _enabledAt, _lastTickAt;
  final _skippedLate = <String, int>{};
  final _skippedRunning = <String, int>{};
  final _lastSkippedDue = <String, DateTime>{};
  final _lastSubmittedDue = <String, DateTime>{};

  void enable(Directory repository) {
    _repository = repository;
    _next.clear();
    _definitions.clear();
    _invalid = null;
    _enabledAt = DateTime.now().toUtc();
    _lastTickAt = null;
    _skippedLate.clear();
    _skippedRunning.clear();
    _lastSkippedDue.clear();
    _lastSubmittedDue.clear();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final ticked = _ticks.then((_) => tick(DateTime.now()));
      _ticks =
          ticked.then<void>((_) {}, onError: (Object error, StackTrace stack) {
        Zone.current.handleUncaughtError(error, stack);
      });
    });
  }

  Future<void> disable() async {
    _timer?.cancel();
    _timer = null;
    _repository = null;
    await _ticks;
  }

  Future<void> tick(DateTime now) async {
    final repository = _repository;
    if (repository == null) return;
    _lastTickAt = now.toUtc();
    final file = File(p.join(repository.path, 'hooks', 'schedules.json'));
    if (!await file.exists()) {
      _next.clear();
      _definitions.clear();
      _invalid = null;
      return;
    }
    final text = await file.readAsString();
    final List<JsonMap> schedules;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        throw const FormatException('Expected a JSON array.');
      }
      schedules = decoded.map((value) {
        final reason = invalidReason(value, repository.path);
        if (reason != null) {
          throw FormatException(value is! Map<String, dynamic>
              ? 'Expected schedule object.'
              : 'Each schedule needs id, relative program and either positive integer everySeconds or dailyAt HH:mm.');
        }
        return Map<String, Object?>.from(value as Map);
      }).toList();
      if (schedules.map((s) => s['id']).toSet().length != schedules.length) {
        throw const FormatException('Schedule ids must be unique.');
      }
    } on FormatException catch (error) {
      if (_invalid != text) {
        _invalid = text;
        await reportError(error.toString());
      }
      _next.clear();
      _definitions.clear();
      return;
    }
    _invalid = null;
    final ids = schedules.map((s) => s['id']).toSet();
    _next.removeWhere((key, _) => !ids.contains(key));
    _definitions.removeWhere((key, _) => !ids.contains(key));
    for (final schedule in schedules) {
      final id = schedule['id'] as String;
      final definition = jsonEncode(schedule);
      if (_definitions[id] != definition) {
        _definitions[id] = definition;
        _next[id] = nextDue(schedule, now);
      }
      final due = _next[id]!;
      if (now.isBefore(due)) {
        continue;
      }
      _next[id] = nextDue(schedule, now);
      // A delayed application clock skips old occurrences instead of replaying.
      if (now.difference(due) < const Duration(seconds: 2)) {
        _lastSubmittedDue[id] = due.toUtc();
        await submit(schedule, due);
      } else {
        _skippedLate[id] = (_skippedLate[id] ?? 0) + 1;
        _lastSkippedDue[id] = due.toUtc();
      }
    }
  }

  /// A run that was due while the previous run of the same schedule had not
  /// finished is not started; this counts it.
  void skippedRunning(String id, DateTime due) {
    _skippedRunning[id] = (_skippedRunning[id] ?? 0) + 1;
    _lastSkippedDue[id] = due.toUtc();
  }

  /// Why one entry of schedules.json cannot run, or null when it can.
  static String? invalidReason(Object? value, String repository) {
    if (value is! Map<String, dynamic>) return 'Expected a schedule object.';
    final id = value['id'], program = value['program'];
    final interval = value['everySeconds'], daily = value['dailyAt'];
    if (id is! String || id.isEmpty) return 'id must be a non-empty string.';
    if (program is! String || program.isEmpty) {
      return 'program must be a path inside the harness.';
    }
    if (p.isAbsolute(program) ||
        !p.isWithin(repository, p.normalize(p.join(repository, program)))) {
      return 'program must be a relative path inside the harness.';
    }
    if ((interval == null) == (daily == null)) {
      return 'Give exactly one of everySeconds and dailyAt.';
    }
    if (interval != null && (interval is! int || interval < 1)) {
      return 'everySeconds must be a positive integer.';
    }
    if (daily != null &&
        (daily is! String ||
            !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(daily))) {
      return 'dailyAt must be HH:mm.';
    }
    return null;
  }

  /// What the file says now and what the clock has done with it: every
  /// entry with the reason it cannot run if so, when it runs next, and the
  /// occurrences that were not started. Counts cover this process only.
  Future<JsonMap> status() async {
    final repository = _repository;
    final result = <String, Object?>{
      'active': repository != null && _timer != null,
      'activeSince': _enabledAt?.toIso8601String(),
      'lastTickAt': _lastTickAt?.toIso8601String(),
    };
    if (repository == null) {
      return {...result, 'file': 'unavailable', 'error': null, 'entries': []};
    }
    final file = File(p.join(repository.path, 'hooks', 'schedules.json'));
    if (!await file.exists()) {
      return {...result, 'file': 'absent', 'error': null, 'entries': []};
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      return {
        ...result,
        'file': 'invalid',
        'error': error.toString(),
        'entries': []
      };
    }
    if (decoded is! List) {
      return {
        ...result,
        'file': 'invalid',
        'error': 'Expected a JSON array.',
        'entries': []
      };
    }
    final ids = <String, int>{};
    for (final value in decoded) {
      if (value is Map && value['id'] is String) {
        ids[value['id'] as String] = (ids[value['id'] as String] ?? 0) + 1;
      }
    }
    final entries = <JsonMap>[];
    var problem = false;
    for (var i = 0; i < decoded.length; i++) {
      final value = decoded[i];
      var reason = invalidReason(value, repository.path);
      final id = value is Map ? value['id'] : null;
      if (reason == null && ids[id]! > 1) reason = 'Schedule ids must be unique.';
      problem |= reason != null;
      final valid = reason == null;
      final map = value is Map ? value : const {};
      entries.add({
        'index': i,
        'id': id is String ? id : null,
        'valid': valid,
        'reason': reason,
        'program': map['program'] is String ? map['program'] : null,
        'everySeconds': map['everySeconds'] is int ? map['everySeconds'] : null,
        'dailyAt': map['dailyAt'] is String ? map['dailyAt'] : null,
        'nextDueAt': valid ? _next[id]?.toUtc().toIso8601String() : null,
        'lastStartedDueAt': valid ? _lastSubmittedDue[id]?.toIso8601String() : null,
        'skippedLate': valid ? _skippedLate[id] ?? 0 : null,
        'skippedWhileRunning': valid ? _skippedRunning[id] ?? 0 : null,
        'lastSkippedDueAt': valid ? _lastSkippedDue[id]?.toIso8601String() : null,
      });
    }
    return {
      ...result,
      'file': problem ? 'invalid' : 'valid',
      'error': problem
          ? 'An entry is invalid; none of the schedules in this file runs while any is.'
          : null,
      'entries': entries
    };
  }

  static DateTime nextDue(JsonMap schedule, DateTime now) {
    if (schedule['everySeconds'] case final int seconds) {
      return now.add(Duration(seconds: seconds));
    }
    final time =
        (schedule['dailyAt'] as String).split(':').map(int.parse).toList();
    var next = DateTime(now.year, now.month, now.day, time[0], time[1]);
    if (!next.isAfter(now)) {
      next = DateTime(now.year, now.month, now.day + 1, time[0], time[1]);
    }
    return next;
  }
}
