import '../security/memory_vault.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';

final class _TestAction extends Action<NoInput, NoInput> {
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'test.query',
        title: 'Query test state',
        description: 'Return an empty test state.',
        effect: Effect.read,
        input: ObjectSchema({}),
        output: ObjectSchema({}),
      );

  @override
  NoInput decodeInput(JsonMap json) => const NoInput();

  @override
  Future<Outcome<NoInput>> run(NoInput input, Invocation invocation) async =>
      const Completed(NoInput());
}

final class _TestCapability implements Capability {
  @override
  List<Action> get actions => [_TestAction()];
}

Future<JsonMap> _rpc(
  HttpClient client,
  Uri url,
  String token,
  String method, {
  JsonMap params = const {},
}) async {
  final request = await client.postUrl(url);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({
    'jsonrpc': '2.0',
    'id': 1,
    'method': method,
    'params': params,
  }));
  final response = await request.close();
  expect(response.statusCode, HttpStatus.ok);
  final body = jsonDecode(await utf8.decoder.bind(response).join()) as JsonMap;
  expect(body['jsonrpc'], '2.0');
  expect(body['id'], 1);
  return body['result'] as JsonMap;
}

void main() {
  late Directory temporary;
  late Directory root;
  late AgentEndpoint endpoint;
  late Harness harness;
  late CredentialStore credentials;
  late HttpClient client;
  const agentsMd = '# NipaPlay\n媒体能力由 Harness 提供。\n';

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('agent-endpoint-');
    root = Directory('${temporary.path}/next');
    harness = Harness([_TestCapability()]);
    credentials = CredentialStore(MemoryVault(), desktop: true);
    endpoint = AgentEndpoint(
      harness: harness,
      credentials: credentials,
      root: root,
      appVersion: '1.2.3',
      agentsMd: agentsMd,
      port: 0,
    );
    client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => temporary.delete(recursive: true));
    addTearDown(endpoint.stop);
    addTearDown(() => client.close(force: true));
  });

  test('creates a 32-byte vault token, reference file, and workspace', () async {
    final running = await endpoint.start() as AgentEndpointRunning;
    final file = File('${root.path}/endpoint.json');
    final contents = jsonDecode(await file.readAsString()) as JsonMap;
    final token = (await credentials.vault.read(const CredentialRef('agent', 'token')))!;
    expect(contents['token'], const CredentialRef('agent', 'token').placeholder);
    expect(await file.readAsString(), isNot(contains(token)));
    expect(contents.keys, ['token']);
    expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(base64Url.decode(base64Url.normalize(token)), hasLength(32));
    expect(running.url.scheme, 'http');
    expect(running.url.host, '127.0.0.1');
    expect(running.url.port, greaterThan(0));
    expect(running.url.path, '/mcp');
    expect(running.workspace.path, '${root.path}/workspace');
    expect(await File('${running.workspace.path}/AGENTS.md').readAsString(),
        agentsMd);
    expect(
        await File('${running.workspace.path}/.codex/config.toml')
            .readAsString(),
        '''
[mcp_servers.nipaplay]
url = "${running.url}"
http_headers = { Authorization = "Bearer $token" }
default_tools_approval_mode = "auto"
''');
  });

  test('authenticates initialize and invokes the fake capability', () async {
    final running = await endpoint.start() as AgentEndpointRunning;
    final token = (await credentials.vault.read(const CredentialRef('agent', 'token')))!;
    final initialized = await _rpc(client, running.url, token, 'initialize',
        params: {'protocolVersion': '2025-11-25'});
    expect(initialized['protocolVersion'], '2025-11-25');
    expect(initialized['serverInfo'], {
      'name': 'nipaplay',
      'title': 'NipaPlay',
      'version': '1.2.3',
    });
    final instructions = initialized['instructions'] as String;
    expect(instructions, contains('NipaPlay exposes'));
    expect(instructions, contains('needs_decision'));
    expect(instructions, contains('call'));
    expect(instructions, contains('accepted work'));
    expect(instructions, contains('Credentials remain in the host'));
    expect(instructions, isNot(contains('before acting')));
    expect(instructions, isNot(contains('ask the user')));
    final called = await _rpc(client, running.url, token, 'tools/call',
        params: {'name': 'test_query', 'arguments': {}});
    expect(called['structuredContent'], {'status': 'completed', 'result': {}});
    expect(called['isError'], isFalse);
  });

  test('repeated start and stop are idempotent and release the port', () async {
    await endpoint.stop();
    final first = await endpoint.start() as AgentEndpointRunning;
    final second = await endpoint.start() as AgentEndpointRunning;
    expect(second.url, first.url);
    expect(second.workspace.path, first.workspace.path);
    await endpoint.stop();
    await endpoint.stop();
    final rebound =
        await HttpServer.bind(InternetAddress.loopbackIPv4, first.url.port);
    addTearDown(() => rebound.close(force: true));
  });

  test('reuses the token after stop and across endpoint instances', () async {
    await endpoint.start();
    final file = File('${root.path}/endpoint.json');
    final original = await file.readAsString();
    await endpoint.stop();
    await endpoint.start();
    expect(await file.readAsString(), original);
    await endpoint.stop();

    final restarted = AgentEndpoint(
      harness: harness,
      credentials: credentials,
      root: root,
      appVersion: '1.2.3',
      agentsMd: agentsMd,
      port: 0,
    );
    addTearDown(restarted.stop);
    final running = await restarted.start() as AgentEndpointRunning;
    expect(await file.readAsString(), original);
    final token = (await credentials.vault.read(const CredentialRef('agent', 'token')))!;
    expect(await _rpc(client, running.url, token, 'ping'), isEmpty);
  });

  test('reports the occupied port and can start after it is released',
      () async {
    final occupied = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = occupied.port;
    addTearDown(() => occupied.close(force: true));
    final blocked = AgentEndpoint(
      harness: harness,
      credentials: credentials,
      root: root,
      appVersion: '1.2.3',
      agentsMd: agentsMd,
      port: port,
    );
    addTearDown(blocked.stop);
    final failure = await blocked.start() as AgentEndpointFailed;
    expect(failure.message, contains('$port'));
    expect(await Directory('${root.path}/workspace').exists(), isFalse);
    await occupied.close(force: true);
    final running = await blocked.start() as AgentEndpointRunning;
    expect(running.url.port, port);
  });

  test('propagates token JSON errors', () async {
    await root.create(recursive: true);
    await File('${root.path}/endpoint.json').writeAsString('{');
    await expectLater(endpoint.start(), throwsFormatException);
  });
}
