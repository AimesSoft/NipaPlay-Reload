import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_workspace.dart';

const _read = ActionSpec(
  id: 'media.library.search',
  title: 'Search library',
  description: 'Search the library.',
  effect: Effect.read,
  input: ObjectSchema({}),
  output: ObjectSchema({}),
);
const _write = ActionSpec(
  id: 'playback.open',
  title: 'Open media',
  description: 'Open media for playback.',
  effect: Effect.write,
  input: ObjectSchema({}),
  output: ObjectSchema({}),
);
const _delete = ActionSpec(
  id: 'media.library.delete',
  title: 'Delete media',
  description: 'Delete media from the library.',
  effect: Effect.destructive,
  input: ObjectSchema({}),
  output: ObjectSchema({}),
);
const _clear = ActionSpec(
  id: 'history.clear',
  title: 'Clear history',
  description: 'Delete watch history.',
  effect: Effect.destructive,
  input: ObjectSchema({}),
  output: ObjectSchema({}),
);

void main() {
  late Directory root;
  late Directory workspace;
  final url = Uri.parse('http://127.0.0.1:47811/mcp');
  const agentsMd = '# NipaPlay\n\n先查询再行动。\n';
  const baseConfig = '''
sandbox_mode = "danger-full-access"
approval_policy = "never"
web_search = "live"

[mcp_servers.nipaplay]
url = "http://127.0.0.1:47811/mcp"
http_headers = { Authorization = "Bearer test-token" }
default_tools_approval_mode = "auto"
''';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agent-workspace-');
    workspace = Directory('${root.path}/next/workspace');
    addTearDown(() => root.delete(recursive: true));
  });

  test('writes exact instructions and config for read and write actions',
      () async {
    await writeAgentWorkspace(
      directory: workspace,
      url: url,
      token: 'test-token',
      catalog: const [_read, _write],
      agentsMd: agentsMd,
    );

    expect(await File('${workspace.path}/AGENTS.md').readAsString(), agentsMd);
    expect(await File('${workspace.path}/.codex/config.toml').readAsString(),
        baseConfig);
  });

  test('prompts only for destructive tools using their MCP names', () async {
    await writeAgentWorkspace(
      directory: workspace,
      url: url,
      token: 'test-token',
      catalog: const [_read, _delete, _write, _clear],
      agentsMd: agentsMd,
    );

    expect(await File('${workspace.path}/AGENTS.md').readAsString(), agentsMd);
    expect(await File('${workspace.path}/.codex/config.toml').readAsString(),
        '''$baseConfig
[mcp_servers.nipaplay.tools.media_library_delete]
approval_mode = "prompt"

[mcp_servers.nipaplay.tools.history_clear]
approval_mode = "prompt"
''');
  });

  test('overwrites both files and removes obsolete tool approvals', () async {
    await writeAgentWorkspace(
      directory: workspace,
      url: url,
      token: 'old-token',
      catalog: const [_delete],
      agentsMd: 'Old instructions',
    );
    await writeAgentWorkspace(
      directory: workspace,
      url: Uri.parse('http://127.0.0.1:12345/mcp'),
      token: 'new-token',
      catalog: const [_read, _write],
      agentsMd: agentsMd,
    );

    expect(await File('${workspace.path}/AGENTS.md').readAsString(), agentsMd);
    expect(
        await File('${workspace.path}/.codex/config.toml').readAsString(), '''
sandbox_mode = "danger-full-access"
approval_policy = "never"
web_search = "live"

[mcp_servers.nipaplay]
url = "http://127.0.0.1:12345/mcp"
http_headers = { Authorization = "Bearer new-token" }
default_tools_approval_mode = "auto"
''');
  });

  test('token config is private on initial creation and replacement', () async {
    if (Platform.isWindows) return;
    for (final token in ['old-token', 'new-token']) {
      await writeAgentWorkspace(
          directory: workspace,
          url: url,
          token: token,
          catalog: const [_read],
          agentsMd: agentsMd);
      final config = File('${workspace.path}/.codex/config.toml');
      expect((await config.stat()).mode & 0x1ff, 0x180);
      expect(await config.readAsString(), contains('Bearer $token'));
      expect(await File('${config.path}.tmp').exists(), isFalse);
      await Process.run('chmod', ['644', config.path]);
    }
  });
}
