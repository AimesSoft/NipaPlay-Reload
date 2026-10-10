import 'dart:io';

import 'package:nipa_harness/mcp.dart';
import 'package:nipa_harness/nipa_harness.dart';

Future<void> writeAgentWorkspace({
  required Directory directory,
  required Uri url,
  required String token,
  required List<ActionSpec> catalog,
  required String agentsMd,
}) async {
  await directory.create(recursive: true);
  await File('${directory.path}/AGENTS.md').writeAsString(agentsMd);

  final codex = Directory('${directory.path}/.codex');
  await codex.create(recursive: true);
  final config = StringBuffer('''
sandbox_mode = "danger-full-access"
approval_policy = "never"
web_search = "live"

[mcp_servers.nipaplay]
url = "$url"
http_headers = { Authorization = "Bearer $token" }
default_tools_approval_mode = "auto"
''');
  for (final spec in catalog) {
    if (spec.effect == Effect.destructive) {
      config.write('''

[mcp_servers.nipaplay.tools.${mcpToolName(spec.id)}]
approval_mode = "prompt"
''');
    }
  }
  final pending = File('${codex.path}/config.toml.tmp');
  await pending.writeAsString('');
  final ProcessResult permissions;
  if (Platform.isWindows) {
    permissions = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'''$ErrorActionPreference = 'Stop';
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User;
$acl = [System.Security.AccessControl.FileSecurity]::new();
$acl.SetOwner($sid);
$acl.SetAccessRuleProtection($true, $false);
$acl.SetAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow'));
Set-Acl -LiteralPath $env:NIPAPLAY_AGENT_CONFIG -AclObject $acl;'''
    ], environment: {'NIPAPLAY_AGENT_CONFIG': pending.path});
  } else {
    permissions = await Process.run('chmod', ['600', pending.path]);
  }
  if (permissions.exitCode != 0) {
    throw StateError('Cannot restrict Agent config to the current user.');
  }
  await pending.writeAsString(config.toString(), flush: true);
  await pending.rename('${codex.path}/config.toml');
}
