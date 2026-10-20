@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/model_launch.dart';
import 'package:nipaplay/next/chat/session_store.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The model hears NipaPlay's base instructions, not Codex's coding-agent
/// ones; the harness's AGENTS.md still arrives as before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a turn carries the Nipa base instead of the coding-agent base',
      () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final version = await Process.run('codex', ['--version']);
    expect(version.exitCode, 0, reason: version.stderr.toString());

    final lab = await Directory.systemTemp.createTemp('nipa-base-');
    addTearDown(() => lab.delete(recursive: true));
    final root = await Directory('${lab.path}/next').create();
    final repository = await Directory('${lab.path}/harness').create();
    final initialized = await Process.run(
        'git', ['init', '--quiet', '--template=', '--initial-branch=main'],
        workingDirectory: repository.path);
    expect(initialized.exitCode, 0, reason: initialized.stderr.toString());
    await Directory('${repository.path}/.codex').create();
    await File('${repository.path}/.codex/config.toml').writeAsString(
        'sandbox_mode="danger-full-access"\napproval_policy="never"\n'
        '[features]\nmemories=false\n');
    await File('${repository.path}/AGENTS.md')
        .writeAsString('# Harness fixture\n\nThe harness speaks here.\n');
    final base = File('${root.path}/agent/nipa-base.md');
    await base.parent.create(recursive: true);
    await base.writeAsString(
        await File('assets/next/agent/nipa-base.md').readAsString());

    final requests = <Map<String, Object?>>[];
    final answered = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.method != 'POST' || request.uri.path != '/v1/responses') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      requests.add(jsonDecode(await utf8.decodeStream(request))
          as Map<String, Object?>);
      _replyOk(request.response, requests.length);
      await request.response.close();
      if (!answered.isCompleted) answered.complete();
    });

    final home = await Directory('${lab.path}/codex-home').create();
    await File('${home.path}/config.toml').writeAsString(
        'model="fixture-model"\nmodel_provider="fixture"\n'
        '[model_providers.fixture]\nname="Base fixture"\n'
        'base_url="http://127.0.0.1:${server.port}/v1"\n'
        'wire_api="responses"\nrequest_max_retries=0\nstream_max_retries=0\n'
        '[projects.${jsonEncode(repository.path)}]\ntrust_level="trusted"\n');
    sqfliteFfiInit();
    final store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final engine = TaskEngine(store: store, ownerDeviceId: 'base');
    addTearDown(engine.close);
    await engine.start();
    final endpoint = AgentEndpoint(
        harness: Harness([]),
        seed: {},
        appVersion: 'base',
        credentialFile: File('${root.path}/endpoint.json'),
        seedRepository: Directory('${root.path}/harness-seed'),
        port: 0);
    addTearDown(endpoint.stop);
    final host = ChatHost(
        endpoint: endpoint,
        repository: repository,
        labRoot: lab,
        sessions: SessionStore(store.database),
        codexExecutable: 'codex',
        modelLaunch: () async => ModelLaunch(revision: 0, home: home),
        baseInstructions: base);
    addTearDown(host.close);
    await host.start();
    await host.getMainSession();
    await host.startTurn('你好');
    await answered.future.timeout(const Duration(minutes: 1));

    final instructions = requests.first['instructions'] as String;
    expect(instructions, startsWith('You are Nipa, the assistant inside NipaPlay'));
    expect(instructions, isNot(contains('You are a coding agent')));
    expect(jsonEncode(requests.first['input']),
        contains('The harness speaks here.'));
  });
}

void _replyOk(HttpResponse response, int number) {
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
