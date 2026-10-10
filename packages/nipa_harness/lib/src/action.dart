part of 'kernel.dart';

enum Effect { read, write, destructive }

final class ActionSpec {
  const ActionSpec({
    required this.id,
    required this.title,
    required this.description,
    required this.effect,
    required this.input,
    required this.output,
  });

  final String id;
  final String title;
  final String description;
  final Effect effect;
  final ObjectSchema input;
  final ObjectSchema output;
}

abstract base class Action<I extends JsonEncodable, O extends JsonEncodable> {
  const Action();

  ActionSpec get spec;
  I decodeInput(JsonMap json);
  Future<Outcome<O>> run(I input, Invocation invocation);
}

abstract interface class Capability {
  List<Action> get actions;
}
