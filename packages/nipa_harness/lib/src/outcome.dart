part of 'kernel.dart';

sealed class Outcome<O extends JsonEncodable> {
  const Outcome();

  JsonMap toEnvelope() => switch (this) {
        Completed<O>(:final value) => {
            'status': 'completed',
            'result': value.toJson(),
          },
        NeedsDecision<O>(:final decision) => {
            'status': 'needs_decision',
            'decision': decision.toJson(),
          },
        Failed<O>(:final failure) => {
            'status': 'failed',
            'error': failure.toJson(),
          },
      };
}

final class Completed<O extends JsonEncodable> extends Outcome<O> {
  const Completed(this.value);

  final O value;
}

final class NeedsDecision<O extends JsonEncodable> extends Outcome<O> {
  const NeedsDecision(this.decision);

  final Decision decision;
}

final class Failed<O extends JsonEncodable> extends Outcome<O> {
  const Failed(this.failure);

  final Failure failure;
}

final class Decision implements JsonEncodable {
  const Decision({required this.prompt, required this.options});

  final String prompt;
  final List<DecisionOption> options;

  @override
  JsonMap toJson() => {
        'prompt': prompt,
        'options': [for (final option in options) option.toJson()],
      };
}

final class DecisionOption implements JsonEncodable {
  const DecisionOption({required this.label, this.detail, required this.call});

  final String label;
  final String? detail;
  final ActionCall call;

  @override
  JsonMap toJson() => {
        'label': label,
        if (detail != null) 'detail': detail,
        'call': call.toJson(),
      };
}

final class ActionCall implements JsonEncodable {
  const ActionCall(this.actionId, this.input);
  ActionCall.of(Action action, JsonEncodable input)
      : this(action.spec.id, input.toJson());

  final String actionId;
  final JsonMap input;

  @override
  JsonMap toJson() => {'action': actionId, 'input': input};
}

enum FailureCode {
  invalidInput,
  notFound,
  unavailable,
  conflict,
  internal;

  String get wireName => switch (this) {
        invalidInput => 'invalid_input',
        notFound => 'not_found',
        unavailable => 'unavailable',
        conflict => 'conflict',
        internal => 'internal',
      };
}

final class Failure implements Exception, JsonEncodable {
  const Failure(
    this.code,
    this.message, {
    this.retryable = false,
    this.violations = const [],
    this.details = const {},
  });

  final FailureCode code;
  final String message;
  final bool retryable;
  final List<SchemaViolation> violations;
  final JsonMap details;

  @override
  JsonMap toJson() => {
        'code': code.wireName,
        'message': message,
        'retryable': retryable,
        if (details.isNotEmpty) 'details': details,
        if (violations.isNotEmpty)
          'violations': [
            for (final violation in violations) violation.toJson()
          ],
      };
}
