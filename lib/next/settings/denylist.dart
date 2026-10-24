import 'package:nipaplay/security/credential_key_policy.dart';

/// Both stable registry keys and verified legacy storage names are blocked.
const settingsDenylist = <String>{
  ...CredentialKeyPolicy.scalarKeys,
  'danmaku.spoilerAiApiKey',
  'webdav_connections',
  'smb_connections',
  'server_profiles',
  'tmdb',
  'metadata.tmdb',
  'agent.token',
  'next/credentials.json',
  'next/endpoint.json',
  'labs_enable_agent_endpoint',
  'labs.enableAgentEndpoint',
  'agent.endpointEnabled',
  'agent.executionMode',
  'agent.approvalPolicy',
  'agent.pluginInstallPermission',
  'plugins.installPermission',
  'web_server_auto_start',
  'web_server_port',
  'web_server_ipv6_enabled',
  'remote_control_receiver_enabled',
  'remote_control_trusted_devices',
  'remoteAccess.enabled',
  'remoteAccess.autoStart',
  'remoteAccess.port',
  'remoteAccess.ipv6Enabled',
  'remoteControl.receiverEnabled',
  'remoteControl.trustedDevices',
  'fileProxyPort',
  'mesh.fileProxyPort',
  'mesh/fileProxyPort',
};

const settingsDeniedPrefixes = <String>[
  'model.',
  'model_',
  'codex.',
  'hostSettings.',
  'program.',
  'program_',
  'remoteRun.',
  'remote_run_',
  'mesh.trust',
  'mesh.issuer',
  'mesh.coordinator',
  'mesh.enabled',
  'mesh.agentDevice',
  'remote_control_',
  'web_server_',
  'remoteAccess.',
  'remoteControl.',
  'credentials.',
  'credential.',
  'vault.',
  'agent.permissions.',
  'agent.approval.',
  'agent.execution.',
  'agent.execution',
  'agent.approval',
  'agent.endpoint',
  'agent.permission',
];

final _deniedKeys = {for (final key in settingsDenylist) key.toLowerCase()};
final _deniedPrefixes = {
  for (final prefix in settingsDeniedPrefixes) prefix.toLowerCase()
};
final _secretName = RegExp(
    r'(^|[._])(password|passwd|token|secret|api_?key|credential)([._]|$)');
final _camelCase = RegExp(r'([a-z])([A-Z])');

bool isSettingDenied(String key) {
  final normalized = key.toLowerCase();
  final segmented =
      key.replaceAllMapped(_camelCase, (m) => '${m[1]}_${m[2]}').toLowerCase();
  return (CredentialKeyPolicy.isSecretKey(normalized) &&
          normalized != 'plugin_enabled_ids') ||
      _deniedKeys.contains(normalized) ||
      _deniedPrefixes.any(normalized.startsWith) ||
      _secretName.hasMatch(segmented) ||
      normalized.endsWith('password') ||
      normalized.endsWith('token') ||
      normalized.endsWith('apikey');
}
