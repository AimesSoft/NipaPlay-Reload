import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';
import '../harness_redaction.dart';

/// Optional body services must not hold the conversation endpoint hostage.
/// A failed service keeps its own error until an explicit retry succeeds.
final class StartupServices {
  final _services = <String, _Service>{};
  bool active = false;
  void Function()? onChanged;

  void register(String id, String title, Future<void> Function() start) {
    _services[id] = _Service(title, start);
  }

  JsonMap get status => {
        'active': active,
        'state': !active
            ? 'stopped'
            : _services.values.any((s) => s.state == 'failed')
                ? 'degraded'
                : _services.values.any((s) => s.state != 'ready')
                    ? 'starting'
                    : 'ready',
        'components': [
          for (final entry in _services.entries)
            {
              'id': entry.key,
              'title': entry.value.title,
              'state': entry.value.state,
              'attempts': entry.value.attempts,
              'startedAt': entry.value.startedAt,
              'finishedAt': entry.value.finishedAt,
              if (entry.value.error != null) 'error': entry.value.error,
            }
        ],
      };

  void start() {
    active = true;
    for (final id in _services.keys) {
      unawaited(run(id));
    }
  }

  Future<void> run(String id) {
    final service = _services[id];
    if (service == null) {
      throw const Failure(
          FailureCode.invalidInput, 'Unknown startup component.');
    }
    if (!active) {
      throw const Failure(
          FailureCode.unavailable, 'Next services are stopped.');
    }
    return service.pending ??=
        _run(service).whenComplete(() => service.pending = null);
  }

  Future<void> _run(_Service service) async {
    service.state = 'starting';
    service.attempts++;
    service.startedAt = DateTime.now().toUtc().toIso8601String();
    service.finishedAt = null;
    onChanged?.call();
    try {
      await service.start();
      service.state = 'ready';
      service.error = null;
    } catch (error, stack) {
      service.state = 'failed';
      service.error = {
        'code': 'initialization_failed',
        'message':
            redactHarnessText(error is Failure ? error.message : '$error'),
        'stack':
            redactHarnessText(stack.toString().split('\n').take(8).join('\n')),
      };
    } finally {
      service.finishedAt = DateTime.now().toUtc().toIso8601String();
      onChanged?.call();
    }
  }

  /// Return immediately; the caller reads status for the actual outcome.
  JsonMap retry(String? id) {
    if (!active) {
      throw const Failure(
          FailureCode.unavailable, 'Next services are stopped.');
    }
    final ids = id == null
        ? [
            for (final e in _services.entries)
              if (e.value.state == 'failed') e.key
          ]
        : [id];
    for (final key in ids) {
      unawaited(run(key));
    }
    return {'requested': ids, ...status};
  }

  Future<void> pause() async {
    active = false;
    // Finish in-flight initialization before its resources are disposed. A new
    // startup cannot overlap an old service's writes or start a timer after stop.
    await Future.wait([
      for (final s in _services.values)
        if (s.pending != null) s.pending!
    ]);
    for (final s in _services.values) {
      if (s.state != 'failed') s.state = 'stopped';
    }
  }
}

final class _Service {
  _Service(this.title, this.start);
  final String title;
  final Future<void> Function() start;
  String state = 'pending';
  int attempts = 0;
  String? startedAt, finishedAt;
  JsonMap? error;
  Future<void>? pending;
}
