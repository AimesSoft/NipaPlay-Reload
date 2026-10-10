import 'package:nipa_harness/nipa_harness.dart';
import '../settings/registry.dart';
import 'runtime.dart';

final class MeshCapability implements Capability {
  MeshCapability(MeshRuntime runtime)
      : actions = [
          _MeshAction(runtime, 'devices', Effect.read),
          _MeshAction(runtime, 'invoke', Effect.write),
          _MeshAction(runtime, 'invoke_destructive', Effect.destructive),
        ];
  @override
  final List<Action> actions;
}

final class _MeshAction extends Action<MeshJson, JsonEncodable> {
  _MeshAction(this.runtime, this.operation, this.effect);
  final MeshRuntime runtime;
  final String operation;
  final Effect effect;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'mesh.$operation',
      title: 'Mesh $operation',
      description: operation == 'devices'
          ? 'List same-account devices, reachability, and their authenticated Action catalogs.'
          : effect == Effect.destructive
              ? 'Invoke a destructive Action on a device; explicit user authorization is required.'
              : 'Invoke a non-destructive Action directly on a same-account device.',
      effect: effect,
      input: operation == 'devices'
          ? const ObjectSchema({})
          : const ObjectSchema({
              'deviceId': StringSchema(minLength: 1),
              'action': StringSchema(minLength: 1),
              'input': ObjectSchema({}, additionalProperties: true),
            }, required: [
              'deviceId',
              'action',
              'input'
            ]),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  MeshJson decodeInput(JsonMap json) => MeshJson(json);
  @override
  Future<Outcome<JsonEncodable>> run(
      MeshJson input, Invocation invocation) async {
    if (operation == 'devices') {
      return Completed(MeshJson(await runtime.devices()));
    }
    return runtime.invoke(input.json['deviceId'] as String,
        input.json['action'] as String, input.json['input'] as JsonMap,
        destructive: effect == Effect.destructive);
  }
}

SettingEntry meshAddressSetting(MeshRuntime runtime) => SettingEntry(
    key: 'mesh.addressCandidates',
    title: 'Mesh overlay / public addresses',
    description:
        'Advertise user-supplied direct addresses on the next heartbeat. Trust is checked by mutual TLS.',
    schema: const ArraySchema(ObjectSchema({
      'kind': StringSchema(values: ['overlay', 'public', 'manual', 'relay']),
      'host': StringSchema(minLength: 1),
      'port': IntegerSchema(minimum: 1, maximum: 65535),
      'priority': IntegerSchema(),
      'expires_in': IntegerSchema(),
    }, required: [
      'kind',
      'host',
      'port'
    ])),
    defaultValue: const <Object?>[],
    validateValue: meshAddressViolations,
    storageKey: '@runtime:mesh.addressCandidates',
    reader: 'MeshRuntime.manualAddresses',
    writer: 'MeshRuntime.setManualAddresses',
    read: runtime.manualAddresses,
    write: runtime.setManualAddresses,
    decodeStorage: (value) => value);
