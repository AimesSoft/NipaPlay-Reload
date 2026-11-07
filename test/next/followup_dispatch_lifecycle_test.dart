import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/model_launch.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/repository_location.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'a newly dispatched followup stays started until its actual turn completes',
      () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final dir = await Directory.systemTemp.createTemp('followup-dispatch-');
    addTearDown(() => dir.delete(recursive: true));
    final repository = await Directory('${dir.path}/harness').create();
    expect(
        (await Process.run('git',
                ['init', '--quiet', '--template=', '--initial-branch=main'],
                workingDirectory: repository.path))
            .exitCode,
        0);
    final gate = Completer<void>();
    final requested = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.method != 'POST' || request.uri.path != '/v1/responses') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      await request.drain<void>();
      if (!requested.isCompleted) requested.complete();
      await gate.future;
      _reply(request.response);
      await request.response.close();
    });
    final home = await Directory('${dir.path}/codex-home').create();
    await File('${home.path}/config.toml').writeAsString(
        'model="fixture-model"\nmodel_provider="fixture"\n'
        '[features]\nmemories=false\n'
        '[model_providers.fixture]\nname="Local fixture"\n'
        'base_url="http://127.0.0.1:${server.port}/v1"\n'
        'wire_api="responses"\nexperimental_bearer_token="local-fixture"\n'
        '[projects.${jsonEncode(repository.path)}]\ntrust_level="trusted"\n');
    final root = await Directory('${dir.path}/next').create();
    sqfliteFfiInit();
    final store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final engine = TaskEngine(store: store, ownerDeviceId: 'test');
    addTearDown(engine.close);
    await engine.start();
    final endpoint = AgentEndpoint(
        harness: Harness([]),
        seed: {},
        appVersion: 'test',
        port: 0,
        credentialFile: File('${root.path}/endpoint.json'),
        seedRepository: Directory('${root.path}/seed'));
    addTearDown(endpoint.stop);
    final host = ChatHost(
        endpoint: endpoint,
        repository: repository,
        codexExecutable: 'codex',
        labRoot: dir,
        modelLaunch: () async => ModelLaunch(revision: 0, home: home));
    addTearDown(host.close);
    final followups =
        Followups(store.database, engine, _Location(repository.path));
    addTearDown(followups.close);
    await host.start();
    final thread = (await host.getMainSession())['thread']['id'] as String;
    await followups.attach(host);
    await followups.wake({'threadId': thread, 'instruction': 'Do fixture work'},
        Invocation(origin: 'harness_cli', id: 'dispatch'));
    await followups.sweep();
    await requested.future.timeout(const Duration(seconds: 20));
    expect(host.busyFor(thread), true);
    expect((await followups.list()).single['state'], 'started');
    await followups.sweep();
    expect((await followups.list()).single['state'], 'started');
    final ended =
        host.events.firstWhere((event) => event['method'] == 'turn/completed');
    gate.complete();
    await ended.timeout(const Duration(seconds: 20));
    await followups.sweep();
    expect((await followups.list()).single['state'], 'completed');
    expect((await followups.list()).single['turnStatus'], 'completed');
  });
}

final class _Location implements RepositoryLocation {
  _Location(this.path);
  @override
  final String path;
  @override
  Future<void> get ready async {}
}

void _reply(HttpResponse response) {
  response.headers.set('content-type', 'text/event-stream');
  void event(Map<String, Object?> value) =>
      response.write('data: ${jsonEncode(value)}\n\n');
  final item = {
    'id': 'msg_1',
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
      'id': 'resp_1',
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
    'item_id': 'msg_1',
    'output_index': 0,
    'content_index': 0,
    'delta': 'OK'
  });
  event({'type': 'response.output_item.done', 'output_index': 0, 'item': item});
  event({
    'type': 'response.completed',
    'response': {
      'id': 'resp_1',
      'object': 'response',
      'status': 'completed',
      'output': [item],
      'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2}
    }
  });
}
