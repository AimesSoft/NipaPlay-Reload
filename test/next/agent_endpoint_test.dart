import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';

void main() {
  late Directory root, repository;
  late File credentials;
  late AgentEndpoint endpoint;
  late HttpClient client;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('endpoint-constraints-');
    repository = Directory('${root.path}/harness');
    credentials = File('${root.path}/private/endpoint.json');
    endpoint = AgentEndpoint(
        harness: Harness([]),
        seed: {'nipa': utf8.encode('#!/usr/bin/env python3\n')},
        appVersion: 'test',
        credentialFile: credentials,
        port: 0);
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });
  tearDown(() async {
    client.close(force: true);
    await endpoint.stop();
    await root.delete(recursive: true);
  });

  test(
      'enable rotates private credentials while preserving every repository file',
      () async {
    await endpoint.start(repository);
    final original = jsonDecode(await credentials.readAsString()) as Map;
    final config = File('${repository.path}/.codex/config.toml');
    await config.parent.create();
    await config.writeAsString('User configuration');
    final before = await config.stat();
    await endpoint.stop();
    final running = await endpoint.start(repository) as AgentEndpointRunning;
    final rotated = jsonDecode(await credentials.readAsString()) as Map;
    expect(rotated['token'], isNot(original['token']));
    expect(await config.readAsString(), 'User configuration');
    expect((await config.stat()).modified, before.modified);
    if (!Platform.isWindows) {
      expect((await credentials.stat()).mode & 0x1ff, 0x180);
    }
    for (final path in ['/mcp', '/harness']) {
      final rejected = await client.postUrl(running.url.replace(path: path));
      rejected.headers.set('Authorization', 'Bearer ${original['token']}');
      final response = await rejected.close();
      expect(response.statusCode, 401);
      await response.drain<void>();
      final valid = await client.postUrl(running.url.replace(path: path));
      valid.headers.set('Authorization', 'Bearer ${rotated['token']}');
      valid.write(jsonEncode(path == '/mcp'
          ? {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}
          : {'operation': 'list'}));
      final accepted = await valid.close();
      expect(accepted.statusCode, 200);
      await accepted.drain<void>();
    }
  });

  test(
      'credentials cannot be placed inside the repository including via symlink',
      () async {
    await repository.create();
    final bad = AgentEndpoint(
        harness: Harness([]),
        seed: {},
        appVersion: 'test',
        credentialFile: File('${repository.path}/endpoint.json'),
        port: 0);
    expect(await bad.start(repository), isA<AgentEndpointFailed>());
    if (!Platform.isWindows) {
      await Link('${root.path}/alias').create(repository.path);
      final aliased = AgentEndpoint(
          harness: Harness([]),
          seed: {},
          appVersion: 'test',
          credentialFile: File('${root.path}/alias/private/endpoint.json'),
          port: 0);
      expect(await aliased.start(repository), isA<AgentEndpointFailed>());
    }
    expect(await credentials.exists(), isFalse);
  });
}
