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

  void enable(Directory repository) {
    _repository = repository;
    _next.clear();
    _definitions.clear();
    _invalid = null;
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
    _repository = null;
    await _ticks;
  }

  Future<void> tick(DateTime now) async {
    final repository = _repository;
    if (repository == null) return;
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
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Expected schedule object.');
        }
        final id = value['id'], program = value['program'];
        final interval = value['everySeconds'], daily = value['dailyAt'];
        if (id is! String ||
            id.isEmpty ||
            program is! String ||
            !p.isWithin(repository.path,
                p.normalize(p.join(repository.path, program))) ||
            p.isAbsolute(program) ||
            ((interval == null) == (daily == null)) ||
            (interval != null && (interval is! int || interval < 1)) ||
            (daily != null &&
                (daily is! String ||
                    !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(daily)))) {
          throw const FormatException(
              'Each schedule needs id, relative program and either positive integer everySeconds or dailyAt HH:mm.');
        }
        return Map<String, Object?>.from(value);
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
        await submit(schedule, due);
      }
    }
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
