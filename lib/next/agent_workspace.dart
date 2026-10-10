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
  await File('${codex.path}/config.toml').writeAsString(config.toString());
}
