@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/dsh_runtime.dart';
import 'package:nipaplay/next/chat/model_launch.dart';

/// Actual app-server processes, with local fixed model responses. Both HTTP
/// requests must arrive before either response is released: a serial runner
/// cannot satisfy this assertion. No real model or application is started.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['codex', 'dsh']) {
    test('$kind keeps two conversations in progress independently', () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final dir = await Directory.systemTemp.createTemp('chat-concurrency-');
      addTearDown(() => dir.delete(recursive: true));
      final repository = await Directory('${dir.path}/harness').create();
      final initialized = await Process.run(
          'git', ['init', '--quiet', '--template=', '--initial-branch=main'],
          workingDirectory: repository.path);
      expect(initialized.exitCode, 0);
      final requests = <String, Completer<void>>{
        'CONCURRENT_A': Completer<void>(),
        'CONCURRENT_B': Completer<void>(),
      };
      final gates = {for (final key in requests.keys) key: Completer<void>()};
      addTearDown(() {
        for (final gate in gates.values) {
          if (!gate.isCompleted) gate.complete();
        }
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var number = 0;
      server.listen((request) async {
        if (request.method != 'POST' || request.uri.path != '/v1/responses') {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final body = await utf8.decoder.bind(request).join();
        final key = requests.keys.singleWhere(body.contains);
        if (!requests[key]!.isCompleted) requests[key]!.complete();
        await gates[key]!.future;
        _reply(request.response, ++number);
        await request.response.close();
      });
      final home = await Directory('${dir.path}/codex-home').create();
      await File('${home.path}/config.toml').writeAsString(
          'model="fixture-model"\nmodel_provider="fixture"\n'
          '[features]\nmemories=false\n'
          '[model_providers.fixture]\nname="Local fixture"\n'
          'base_url="http://127.0.0.1:${server.port}/v1"\n'
          'wire_api="responses"\nexperimental_bearer_token="local-fixture"\n'
          'request_max_retries=0\nstream_max_retries=0\n'
          '[projects.${jsonEncode(repository.path)}]\ntrust_level="trusted"\n');
      final endpoint = AgentEndpoint(
          harness: Harness([]),
          seed: {},
          appVersion: 'chat-test',
          port: 0,
          credentialFile: File('${dir.path}/next/endpoint.json'),
          seedRepository: Directory('${dir.path}/next/harness-seed'));
      await endpoint.seedRepository.parent.create(recursive: true);
      addTearDown(endpoint.stop);
      final runtime = kind == 'dsh' ? _dsh() : null;
      final host = ChatHost(
          endpoint: endpoint,
          repository: repository,
          labRoot: dir,
          codexExecutable: 'codex',
          dsh: runtime,
          dshPlugins:
              runtime == null ? null : Directory('assets/next/agent/dsh'),
          modelLaunch: () async => ModelLaunch(
              revision: 0,
              home: home,
              route: runtime == null
                  ? null
                  : DshRoute(
                      baseUrl: 'http://127.0.0.1:${server.port}/v1',
                      model: 'fixture-model',
                      key: 'local-fixture',
                      maxRetries: 0,
                      imageInput: false)));
      addTearDown(host.close);
      await host.start();
      final first = (await host.getMainSession())['thread']['id'] as String;
      final endedA = host.events.firstWhere((e) =>
          e['method'] == 'turn/completed' && e['params']['threadId'] == first);
      expect(await host.startFollowup(first, 'CONCURRENT_A'), isNotNull);
      await requests['CONCURRENT_A']!
          .future
          .timeout(const Duration(seconds: 20));
      expect(host.busyFor(first), true);

      final second = (await host.newConversation())['thread']['id'] as String;
      final endedB = host.events.firstWhere((e) =>
          e['method'] == 'turn/completed' && e['params']['threadId'] == second);
      expect(await host.prepareFollowup(second), second);
      expect(await host.startFollowup(second, 'CONCURRENT_B'), isNotNull);
      await requests['CONCURRENT_B']!
          .future
          .timeout(const Duration(seconds: 20));
      expect(host.busyFor(first), true);
      expect(host.busyFor(second), true);
      expect(await host.startFollowup(first, 'must steer instead'), isNull);
      await host.switchSession(first);
      expect(host.busyFor(second), true);
      gates['CONCURRENT_B']!.complete();
      expect(
          (await endedB.timeout(const Duration(seconds: 20)))['params']['turn']
              ['status'],
          'completed');
      expect(host.busy, true);
      expect(host.busyFor(first), true);
      expect(host.busyFor(second), false);
      gates['CONCURRENT_A']!.complete();
      expect(
          (await endedA.timeout(const Duration(seconds: 20)))['params']['turn']
              ['status'],
          'completed');
      expect(host.busy, false);
    });
  }
}

DshRuntime _dsh() {
  final environment = Platform.environment;
  if (environment['NIPAPLAY_DSH_NODE'] != null) {
    return DshRuntime.select(
        {...environment, 'NIPAPLAY_AGENT_RUNTIME': 'dsh'})!;
  }
  final base = '${environment['HOME']}/.nipa-next/y15';
  return DshRuntime.select({
    'NIPAPLAY_AGENT_RUNTIME': 'dsh',
    'NIPAPLAY_DSH_NODE': '$base/node-install/node_modules/node/bin/node',
    'NIPAPLAY_DSH_ROOT': '$base/dsh-install',
  })!;
}

void _reply(HttpResponse response, int number) {
  response.headers.set('content-type', 'text/event-stream');
  void event(Map<String, Object?> value) =>
      response.write('data: ${jsonEncode(value)}\n\n');
  final item = {
    'id': 'msg_$number',
    'type': 'message',
    'role': 'assistant',
    'status': 'completed',
    'content': [
      {'type': 'output_text', 'text': 'OK', 'annotations': []}
    ]
  };
  event({
    'type': 'response.created',
    'response': {
      'id': 'resp_$number',
      'object': 'response',
      'status': 'in_progress',
      'output': []
    }
  });
  event({
    'type': 'response.output_item.added',
    'output_index': 0,
    'item': {...item, 'status': 'in_progress'}
  });
  event({
    'type': 'response.output_text.delta',
    'item_id': 'msg_$number',
    'output_index': 0,
    'content_index': 0,
    'delta': 'OK'
  });
  event({'type': 'response.output_item.done', 'output_index': 0, 'item': item});
  event({
    'type': 'response.completed',
    'response': {
      'id': 'resp_$number',
      'object': 'response',
      'status': 'completed',
      'output': [item],
      'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2}
    }
  });
}
