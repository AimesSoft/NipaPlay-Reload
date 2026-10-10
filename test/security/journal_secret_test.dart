import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';

final class _SecretAction extends Action<_Input, NoInput> {
  Object? received;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'test.credentials',
        title: 'Test',
        description: 'Test secrets',
        effect: Effect.write,
        input: ObjectSchema({
          'unusualName': StringSchema(secret: true),
          'nested':
              ObjectSchema({'items': ArraySchema(StringSchema(secret: true))}),
          'url': StringSchema()
        }, required: [
          'unusualName'
        ]),
        output: ObjectSchema({}),
      );
  @override
  _Input decodeInput(JsonMap json) => _Input(json);
  @override
  Future<Outcome<NoInput>> run(_Input input, Invocation invocation) async {
    received = input.toJson();
    return const Completed(NoInput());
  }
}

final class _Input implements JsonEncodable {
  _Input(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _Capability implements Capability {
  _Capability(this.action);
  final _SecretAction action;
  @override
  List<Action> get actions => [action];
}

void main() {
  test(
      'schema secrets and credential URLs reach actions but never observers or journal',
      () async {
    final dir = await Directory.systemTemp.createTemp('secret-journal-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/journal.jsonl');
    final action = _SecretAction();
    final harness =
        Harness([_Capability(action)], observers: [JsonlJournal(file)]);
    final input = <String, Object?>{
      'unusualName': 'secret-sentinel',
      'nested': {
        'items': ['nested-sentinel']
      },
      'url': 'https://example.invalid/video?api_key=url-sentinel'
    };
    await harness.invokeJson(
        'test.credentials', input, Invocation(origin: 'test'));
    expect(action.received, input);
    final log = await file.readAsString();
    for (final secret in [
      'secret-sentinel',
      'nested-sentinel',
      'url-sentinel'
    ]) {
      expect(log, isNot(contains(secret)));
    }
    expect(
        jsonDecode(log)['input']['unusualName']['credentialRef']['namespace'],
        'invocation');
    expect(
        ((action.spec.input.toJsonSchema()['properties'] as Map)['unusualName']
            as Map)['writeOnly'],
        true);
    await harness.invokeJson(
        'test.credentials',
        {'unusualName': 42, 'token': 'invalid-sentinel'},
        Invocation(origin: 'test'));
    expect(await file.readAsString(), isNot(contains('invalid-sentinel')));
  });
}
