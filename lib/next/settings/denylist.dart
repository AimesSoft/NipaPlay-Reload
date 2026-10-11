import 'package:nipaplay/security/credential_store.dart';

/// Both stable registry keys and verified legacy storage names are blocked.
const settingsDenylist = <String>{
  ...CredentialStore.scalarKeys,
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
};

const settingsDeniedPrefixes = <String>[
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

bool isSettingDenied(String key) {
  final normalized = key.toLowerCase();
  final segmented = key
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .toLowerCase();
  return (CredentialStore.isSecretKey(normalized) &&
          normalized != 'plugin_enabled_ids') ||
      settingsDenylist.any((v) => v.toLowerCase() == normalized) ||
      settingsDeniedPrefixes
          .any((v) => normalized.startsWith(v.toLowerCase())) ||
      RegExp(r'(^|[._])(password|passwd|token|secret|api_?key|credential)([._]|$)')
          .hasMatch(segmented) ||
      normalized.endsWith('password') ||
      normalized.endsWith('token') ||
      normalized.endsWith('apikey');
}
