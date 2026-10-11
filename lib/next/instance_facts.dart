import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/lab_profile.dart';

final class InstanceFacts {
  const InstanceFacts(this.version);
  final String version;

  Future<JsonMap> read() async {
    final native = Platform.isMacOS
        ? (await const MethodChannel('nipaplay/instance')
            .invokeMapMethod<String, Object?>('facts'))!
        : <String, Object?>{
            'executablePath': Platform.resolvedExecutable,
            'appBundlePath': null,
            'windowTitle': Platform.isWindows || Platform.isLinux
                ? await windowManager.getTitle()
                : null,
            'windowId': null,
            'viewId': null,
          };
    return {
      'pid': pid,
      ...native,
      'experimentalProfile': LabProfile.active,
      'profileName': LabProfile.name,
      'version': version,
    };
  }
}

const instanceFactsSchema = ObjectSchema({
  'pid': IntegerSchema(),
  'executablePath': StringSchema(),
  'appBundlePath': StringSchema(nullable: true),
  'windowTitle': StringSchema(nullable: true),
  'windowId': IntegerSchema(nullable: true),
  'viewId': IntegerSchema(nullable: true),
  'experimentalProfile': BooleanSchema(),
  'profileName': StringSchema(nullable: true),
  'version': StringSchema(),
}, required: [
  'pid',
  'executablePath',
  'appBundlePath',
  'windowTitle',
  'windowId',
  'viewId',
  'experimentalProfile',
  'profileName',
  'version'
]);

final class InstanceValue implements JsonEncodable {
  const InstanceValue(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class InstanceCapability implements Capability {
  InstanceCapability(InstanceFacts facts) : actions = [_InstanceAction(facts)];
  @override
  final List<Action> actions;
}

final class _InstanceAction extends Action<InstanceValue, InstanceValue> {
  const _InstanceAction(this.facts);
  final InstanceFacts facts;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'app.instance',
        title: 'Identify the connected NipaPlay process',
        description: 'Live process and main-window facts for this endpoint. '
            'Also returned as instance by nipa status. Paths identify this running '
            'build; appBundlePath is null on platforms without application bundles. '
            'experimentalProfile identifies the isolated lab configuration, not the Next switch.',
        effect: Effect.read,
        input: ObjectSchema({}),
        output: instanceFactsSchema,
      );
  @override
  InstanceValue decodeInput(JsonMap input) => InstanceValue(input);
  @override
  Future<Outcome<InstanceValue>> run(
          InstanceValue input, Invocation invocation) async =>
      Completed(InstanceValue(await facts.read()));
}
