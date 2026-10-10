part of 'kernel.dart';

final class Invocation {
  Invocation({required this.origin, String? id})
      : id =
            id ?? 'inv-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  static int _sequence = 0;
  final String id;
  final String origin;
}

final class InvocationRecord implements JsonEncodable {
  const InvocationRecord._({
    required this.invocationId,
    required this.actionId,
    required this.origin,
    required this.effect,
    required this.input,
    required this.status,
    required this.failureCode,
    required this.startedAt,
    required this.elapsedMs,
  });

  final String invocationId;
  final String actionId;
  final String origin;
  final Effect effect;
  final Object? input;
  final String status;
  final FailureCode? failureCode;
  final String startedAt;
  final int elapsedMs;

  @override
  JsonMap toJson() => {
        'invocationId': invocationId,
        'actionId': actionId,
        'origin': origin,
        'effect': effect.name,
        'input': input,
        'status': status,
        if (failureCode != null) 'failureCode': failureCode!.wireName,
        'startedAt': startedAt,
        'elapsedMs': elapsedMs,
      };
}

abstract interface class InvocationObserver {
  void onInvocation(InvocationRecord record);
}

final class Harness {
  Harness(
    Iterable<Capability> capabilities, {
    List<InvocationObserver> observers = const [],
  }) : _observers = List.of(observers) {
    for (final capability in capabilities) {
      for (final action in capability.actions) {
        final id = action.spec.id;
        if (!_actionId.hasMatch(id)) {
          throw ArgumentError.value(id, 'id', 'Invalid action id.');
        }
        if (_actions.containsKey(id)) {
          throw ArgumentError.value(id, 'id', 'Duplicate action id.');
        }
        _actions[id] = action;
      }
    }
  }

  static final _actionId = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');
  final Map<String, Action> _actions = {};
  final List<InvocationObserver> _observers;

  List<ActionSpec> get catalog =>
      _actions.values.map((action) => action.spec).toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  Action? lookup(String actionId) => _actions[actionId];

  Future<Outcome<O>> invoke<I extends JsonEncodable, O extends JsonEncodable>(
    Action<I, O> action,
    I input,
    Invocation invocation,
  ) =>
      _execute(action.spec, invocation, () => input.toJson(), (json) async {
        final violations = action.spec.input.validate(json);
        if (violations.isNotEmpty) {
          throw Failure(FailureCode.invalidInput, 'Invalid input.',
              violations: violations);
        }
        return action.run(input, invocation);
      });

  Future<Outcome<JsonEncodable>> invokeJson(
    String actionId,
    Object? input,
    Invocation invocation,
  ) async {
    final action = lookup(actionId);
    if (action == null) {
      return Failed(
          Failure(FailureCode.notFound, 'Unknown action: $actionId.'));
    }
    return _execute(action.spec, invocation, () => input, (json) async {
      final value = json ?? <String, Object?>{};
      final violations = action.spec.input.validate(value);
      if (violations.isNotEmpty) {
        throw Failure(FailureCode.invalidInput, 'Invalid input.',
            violations: violations);
      }
      final decoded =
          action.decodeInput(Map<String, Object?>.from(value as Map));
      return action.run(decoded, invocation);
    });
  }

  Future<Outcome<O>> _execute<O extends JsonEncodable>(
    ActionSpec spec,
    Invocation invocation,
    Object? Function() jsonInput,
    Future<Outcome<O>> Function(Object? input) run,
  ) async {
    final startedAt = DateTime.now().toUtc().toIso8601String();
    final stopwatch = Stopwatch()..start();
    Object? input;
    Outcome<O> outcome;
    try {
      input = jsonInput();
      outcome = await run(input);
    } on Failure catch (failure) {
      outcome = Failed(failure);
    } catch (error) {
      outcome = Failed(Failure(
        FailureCode.internal,
        '${spec.id} failed: $error',
      ));
    }
    stopwatch.stop();
    final record = InvocationRecord._(
      invocationId: invocation.id,
      actionId: spec.id,
      origin: invocation.origin,
      effect: spec.effect,
      input: input,
      status: switch (outcome) {
        Completed<O>() => 'completed',
        NeedsDecision<O>() => 'needs_decision',
        Failed<O>() => 'failed',
      },
      failureCode: switch (outcome) {
        Failed<O>(:final failure) => failure.code,
        _ => null,
      },
      startedAt: startedAt,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    for (final observer in _observers) {
      try {
        observer.onInvocation(record);
      } catch (_) {
        // Observer failures must not change an action's outcome.
      }
    }
    return outcome;
  }
}
