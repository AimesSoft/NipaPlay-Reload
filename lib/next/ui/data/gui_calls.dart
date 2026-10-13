import 'package:nipa_harness/nipa_harness.dart';

/// The capability layer as the person at this window: every Action through
/// the harness with `origin: gui`, the same ones Nipa calls. The pages for
/// downloads, background work, history, collections, folders, caches,
/// updates, plugins and sync read and change things only through here.
final class GuiCalls {
  /// [harness] is read at each call (it may come once the core is ready).
  GuiCalls(this.harness);

  /// Nothing to call: every Action is unavailable (tests that never touch
  /// these pages).
  GuiCalls.none() : harness = _none;

  final Future<Harness> Function() harness;

  static Future<Harness> _none() async => Harness(const []);

  Invocation get _gui => Invocation(origin: 'gui');

  Future<Outcome<JsonEncodable>> invoke(String action, JsonMap input) async =>
      (await harness()).invokeJson(action, input, _gui);

  /// The Action's result. A failure throws its [Failure]; an Action asking
  /// for a decision throws [DecisionNeeded], to be put to the person.
  Future<JsonMap> call(String action, JsonMap input) async =>
      switch (await invoke(action, input)) {
        Completed(:final value) => value.toJson(),
        Failed(:final failure) => throw failure,
        NeedsDecision(:final decision) => throw DecisionNeeded(decision),
      };

  /// Runs the option the person chose.
  Future<JsonMap> choose(DecisionOption option) =>
      call(option.call.actionId, option.call.input);

  /// Whether the receiving host has [action] at all.
  Future<bool> has(String action) async =>
      (await harness()).lookup(action) != null;
}

/// An Action stopped to ask: its options, each an executable call.
final class DecisionNeeded implements Exception {
  const DecisionNeeded(this.decision);
  final Decision decision;

  @override
  String toString() => 'DecisionNeeded(${decision.prompt})';
}

/// A failure as an Action's batch result carries it.
Failure failureOf(Map json) => Failure(
      FailureCode.values.firstWhere((c) => c.wireName == json['code'],
          orElse: () => FailureCode.internal),
      '${json['message'] ?? ''}',
      retryable: json['retryable'] == true,
    );

/// A decision as a task snapshot carries it (`task.get`).
Decision decisionOf(Map json) => Decision(
      prompt: '${json['prompt'] ?? ''}',
      options: [
        for (final o in ((json['options'] as List?) ?? const []).cast<Map>())
          DecisionOption(
            label: '${o['label']}',
            detail: o['detail'] as String?,
            call: ActionCall('${(o['call'] as Map)['action']}',
                Map<String, Object?>.from((o['call'] as Map)['input'] as Map)),
          ),
      ],
    );

/// A short word for what went wrong, for a line under a control.
String callFailure(Object error) {
  if (error is Failure) {
    return switch (error.code) {
      FailureCode.invalidInput => '这样不行',
      FailureCode.notFound => '已经不在了',
      FailureCode.conflict => '刚被改过，再试一次',
      FailureCode.unavailable => '现在做不了',
      _ => '没能完成',
    };
  }
  return '没能完成';
}
