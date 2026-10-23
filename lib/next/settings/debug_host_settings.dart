import 'dart:convert';
import 'dart:developer';

import '../ui_data/host_settings.dart';

/// Installed only by Debug LabProfile runtime. Not an Action or mesh method.
void installDebugHostSettings(NextHostSettings settings) {
  registerExtension('ext.nipaplay.hostSettings', (_, params) async {
    try {
      Object? result;
      switch (params['op']) {
        case 'model':
          final value = await settings.model();
          result = {
            'source': value.source.name,
            'provider': value.provider,
            'baseUrl': value.baseUrl,
            'model': value.model,
            'hasKey': value.hasKey,
            'codexAvailable': value.codexAvailable,
            'inUse': value.inUse,
            'problem': value.problem,
            'runtime': value.runtime.name,
            'api': value.api.name,
            'reasoning': value.reasoning,
          };
        case 'setModel':
          final choice = jsonDecode(params['choice']!) as Map;
          await settings.setModel(UiModelChoice(
              source: UiModelSource.values.byName(choice['source'] as String),
              provider: choice['provider'] as String?,
              baseUrl: choice['baseUrl'] as String?,
              model: choice['model'] as String?,
              apiKey: choice['apiKey'] as String?,
              api: choice['api'] == null
                  ? null
                  : UiModelApi.values.byName(choice['api'] as String),
              reasoning: choice['reasoning'] as String?,
              compat: (choice['compat'] as Map?)?.cast<String, Object?>()));
          result = {'saved': true};
        case 'importCodex':
          await settings.importCodexModel();
          result = {'imported': true};
        case 'runtime':
          final runtime = settings.runtimeSettings;
          final agent = await runtime.agentRuntime();
          final dsh = await runtime.dshRuntime();
          result = {
            'kind': agent.kind.name,
            'fixed': agent.fixed,
            'dsh': {
              'status': dsh.status.name,
              'version': dsh.version,
              'receivedBytes': dsh.receivedBytes,
              'totalBytes': dsh.totalBytes,
              'problem': dsh.problem,
            },
          };
        case 'installDsh':
          await settings.runtimeSettings.installDsh();
          result = {'done': true};
        case 'checkModel':
          final value = await settings.checkModel();
          result = {
            'ok': value.ok,
            'message': value.message,
            'latencyMs': value.latency?.inMilliseconds
          };
        case 'remotePrograms':
          result = {'enabled': await settings.remotePrograms()};
        default:
          throw ArgumentError('Unknown host settings operation');
      }
      return ServiceExtensionResponse.result(jsonEncode(result));
    } catch (_) {
      // VM error responses never echo a request containing a key.
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, '宿主设置操作失败');
    }
  });
}
