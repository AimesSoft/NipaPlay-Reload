import 'package:nipa_harness/nipa_harness.dart';

final class ClassicActionData implements JsonEncodable {
  const ClassicActionData(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class ClassicAction extends Action<ClassicActionData, ClassicActionData> {
  const ClassicAction(this.spec, this.execute);
  @override
  final ActionSpec spec;
  final Future<JsonMap> Function(JsonMap, Invocation) execute;
  @override
  ClassicActionData decodeInput(JsonMap json) => ClassicActionData(json);
  @override
  Future<Outcome<ClassicActionData>> run(
          ClassicActionData input, Invocation invocation) async =>
      Completed(ClassicActionData(await execute(input.value, invocation)));
}
