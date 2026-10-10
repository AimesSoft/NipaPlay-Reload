import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nipa_harness/mcp.dart';
import 'package:nipa_harness/nipa_harness.dart';

import 'agent_workspace.dart';

sealed class AgentEndpointStatus {
  const AgentEndpointStatus();
}

final class AgentEndpointStopped extends AgentEndpointStatus {
  const AgentEndpointStopped();
}

final class AgentEndpointRunning extends AgentEndpointStatus {
  const AgentEndpointRunning({required this.url, required this.workspace});

  final Uri url;
  final Directory workspace;
}

final class AgentEndpointFailed extends AgentEndpointStatus {
  const AgentEndpointFailed(this.message);

  final String message;
}

final class AgentEndpoint {
  AgentEndpoint({
    required Harness harness,
    required Directory root,
    required String appVersion,
    required String agentsMd,
    int port = 47811,
  })  : _harness = harness,
        _root = root,
        _appVersion = appVersion,
        _agentsMd = agentsMd,
        _port = port;

  final Harness _harness;
  final Directory _root;
  final String _appVersion;
  final String _agentsMd;
  final int _port;
  HttpServer? _server;
  AgentEndpointRunning? _running;

  Future<AgentEndpointStatus> start() async {
    if (_running case final running?) return running;

    await _root.create(recursive: true);
    final file = File('${_root.path}/endpoint.json');
    final String token;
    if (await file.exists()) {
      token =
          (jsonDecode(await file.readAsString()) as JsonMap)['token'] as String;
    } else {
      final random = Random.secure();
      token = base64Url
          .encode(List.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      // Restrict a temporary file before the token is written, then rename it
      // into place so a crash never leaves a readable or empty token file.
      final pending = File('${file.path}.tmp');
      await pending.writeAsString('');
      if (!Platform.isWindows) {
        final arguments = ['600', pending.path];
        final result = await Process.run('chmod', arguments);
        if (result.exitCode != 0) {
          throw ProcessException(
            'chmod',
            arguments,
            result.stderr.toString(),
            result.exitCode,
          );
        }
      }
      await pending.writeAsString(jsonEncode({'token': token}), flush: true);
      await pending.rename(file.path);
    }

    final endpoint = McpEndpoint(
      _harness,
      serverInfo: McpServerInfo(
        name: 'nipaplay',
        title: 'NipaPlay',
        version: _appVersion,
      ),
      token: token,
      instructions: 'Query before acting. When an outcome is needs_decision, '
          'execute the chosen option\'s call if the user\'s intent determines '
          'the option; otherwise ask the user. Follow the workspace AGENTS.md.',
    );
    final HttpServer server;
    try {
      server = await endpoint.serve(port: _port);
    } on SocketException catch (error) {
      return AgentEndpointFailed('Cannot bind port $_port: $error');
    }
    _server = server;
    final url = Uri.parse('http://127.0.0.1:${server.port}/mcp');
    final workspace = Directory('${_root.path}/workspace');
    await writeAgentWorkspace(
      directory: workspace,
      url: url,
      token: token,
      catalog: _harness.catalog,
      agentsMd: _agentsMd,
    );
    final running = AgentEndpointRunning(url: url, workspace: workspace);
    _running = running;
    return running;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _running = null;
  }
}
