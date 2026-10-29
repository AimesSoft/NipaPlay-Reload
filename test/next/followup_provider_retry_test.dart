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
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/repository_location.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _Location implements RepositoryLocation {
  _Location(this.path);
  @override
  final String path;
  @override
  Future<void> get ready async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory lab, root, repository;
  late SqliteJobStore store;
  late TaskEngine engine;
  late Followups followups;
  late AgentEndpoint endpoint;
  late ChatHost host;
  late HttpServer server;
  late StreamSubscription<ChatMessage> subscription;
  late List<ChatMessage> events;
  late String threadId;
  late int responseStatus, rejectedRequests, successfulRequests;
  HttpOverrides? previousOverrides;
  Completer<void>? responseGate;
  late Completer<void> requestStarted;
  late List<String> requestBodies;

  setUp(() async {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final version = await Process.run('codex', ['--version']);
    expect(version.exitCode, 0, reason: version.stderr.toString());

    lab = await Directory.systemTemp.createTemp('y16-followup-retry-');
    addTearDown(() => lab.delete(recursive: true));
    root = await Directory('${lab.path}/next').create();
    repository = await Directory('${lab.path}/harness').create();
    final initialized = await Process.run(
        'git', ['init', '--quiet', '--template=', '--initial-branch=main'],
        workingDirectory: repository.path);
    expect(initialized.exitCode, 0, reason: initialized.stderr.toString());
    await Directory('${repository.path}/.codex').create();
    await File('${repository.path}/.codex/config.toml').writeAsString(
        'sandbox_mode="danger-full-access"\napproval_policy="never"\n'
        '[features]\nmemories=false\n');

    responseGate = null;
    requestStarted = Completer<void>();
    requestBodies = [];
    addTearDown(() { if (responseGate != null && !responseGate!.isCompleted) responseGate!.complete(); });
    responseStatus = 429;
    rejectedRequests = successfulRequests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.method != 'POST' || request.uri.path != '/v1/responses') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      requestBodies.add(await utf8.decoder.bind(request).join());
      if (!requestStarted.isCompleted) requestStarted.complete();
      // Keep rejecting every transport retry until the test observes that the
      // first *turn* ended. A fixed request count could succeed in that turn.
      if (responseStatus != 200) {
        rejectedRequests++;
        request.response.statusCode = responseStatus;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {
            'message': responseStatus == 429
                ? 'Y16 temporary rate limit'
                : 'Y16 invalid request',
            'type': responseStatus == 429
                ? 'rate_limit_error'
                : 'invalid_request_error',
          }
        }));
      } else {
        successfulRequests++;
        await responseGate?.future;
        _replyOk(request.response, successfulRequests);
      }
      await request.response.close();
    });

    final home = await Directory('${lab.path}/codex-home').create();
    await File('${home.path}/config.toml').writeAsString(
        'model="fixture-model"\nmodel_provider="fixture"\n'
        '[model_providers.fixture]\nname="Y16 local Responses"\n'
        'base_url="http://127.0.0.1:${server.port}/v1"\n'
        'wire_api="responses"\nrequest_max_retries=1\nstream_max_retries=1\n'
        '[projects.${jsonEncode(repository.path)}]\ntrust_level="trusted"\n');
    sqfliteFfiInit();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(store: store, ownerDeviceId: 'y16');
    addTearDown(engine.close);
    await engine.start();
    endpoint = AgentEndpoint(
        harness: Harness([]),
        seed: {},
        appVersion: 'y16',
        credentialFile: File('${root.path}/endpoint.json'),
        seedRepository: Directory('${root.path}/harness-seed'),
        port: 0);
    addTearDown(endpoint.stop);
    host = ChatHost(
        endpoint: endpoint,
        repository: repository,
        labRoot: lab,
        sessions: SessionStore(store.database),
        // Exercise the PATH binary even if a managed executable is configured.
        codexExecutable: 'codex',
        modelLaunch: () async => ModelLaunch(revision: 0, home: home));
    addTearDown(host.close);
    events = [];
    subscription = host.events.listen(events.add);
    addTearDown(subscription.cancel);
    followups = Followups(store.database, engine, _Location(repository.path));
    addTearDown(followups.close);
    followups.start();
    await host.start();
    expect(host.launchEnvironment['NO_PROXY']!.split(','),
        containsAll(['127.0.0.1', 'localhost', '::1']));
    await host.getMainSession();
    threadId = host.mainThreadId!;
    expect((await host.readThread(threadId))['turns'], isEmpty);
  });

  List<Map> endedTurns() => [
        for (final event in events)
          if (event['method'] == 'turn/completed' &&
              event['params']['threadId'] == threadId)
            event['params']['turn'] as Map
      ];

  Future<JsonMap> state(String expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (true) {
      await followups.sweep();
      final row = (await followups.list()).single;
      if (row['state'] == expected) return row;
      if (DateTime.now().isAfter(deadline)) {
        fail('Expected $expected; row=${jsonEncode(row)}, '
            'live endings=${jsonEncode(endedTurns())}, '
            'HTTP rejected=$rejectedRequests, OK=$successfulRequests');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<JsonMap> registerReady() async {
    final row = await followups.register({
      'when': {'event': 'library.file_added', 'objectId': '/fixture/video.mp4'},
      'threadId': threadId,
      'instruction': 'Inspect these facts and reply OK.',
    }, Invocation(origin: 'harness_cli', id: 'y16-register'));
    await followups.hookEvent('library.file_added', '/fixture/video.mp4', {
      'event': 'library.file_added',
      'objectId': '/fixture/video.mp4',
    });
    await state('ready');
    return row;
  }

  test('real Codex accepts an inbox answer into the original active turn', () async {
    responseStatus = 200;
    responseGate = Completer<void>();
    await followups.attach(host);
    final first = (await host.startTurn('Start fixture work'))['turn']['id'];
    await requestStarted.future.timeout(const Duration(seconds: 15));
    final question = await followups.publishInbox({
      'requestId': 'codex-choice', 'title': '目录', 'body': '整理吗？'
    }, Invocation(origin: host.originFor(threadId)), question: true);
    await followups.answerInbox(question['id'] as String, 'CODEX_INBOX_ANSWER', Invocation(origin: 'gui'));
    final delivery = await state('started');
    expect(delivery['turnId'], first);
    responseGate!.complete();
    await state('completed');
    expect(requestBodies.any((body) => body.contains('CODEX_INBOX_ANSWER')), true);
    expect(endedTurns(), hasLength(1));
    await followups.sweep();
    expect((await followups.list()).single['turnId'], first);
  });

  test(
      'real Codex 429 failure returns to ready and dispatches exactly one retry',
      () async {
    final registration = await registerReady();
    await followups.attach(host);
    final retry = await state('ready');
    final first = endedTurns().single;
    expect(first['status'], 'failed');
    expect(jsonEncode(first['error']), contains('429'));
    expect(rejectedRequests, greaterThan(0));
    expect(successfulRequests, 0);
    expect(retry['id'], registration['id']);
    expect(retry['turnStatus'], 'failed');
    expect(retry['attempts'], 1);
    expect(retry['failedTurns'], [first['id']]);
    expect(retry['turnId'], isNull);
    final retryAt = DateTime.parse(retry['retryAt'] as String);
    expect(retryAt.isAfter(DateTime.now().toUtc()), true);
    expect(
        retryAt
            .difference(DateTime.parse(retry['updatedAt'] as String))
            .inSeconds,
        inInclusiveRange(119, 120));

    // Codex 0.144.1 reconstructs this provider failure as completed. The live
    // turn/completed event must win over that misleading thread/read history.
    final beforeRetry = (await host.readThread(threadId))['turns'] as List;
    expect(beforeRetry, hasLength(1));
    expect((beforeRetry.single as Map)['id'], first['id']);
    expect((beforeRetry.single as Map)['status'], 'completed');

    responseStatus = 200;
    await followups.sweep();
    await followups.sweep();
    expect((await followups.list()).single, retry);
    expect(successfulRequests, 0, reason: 'retryAt must defer delivery');

    // Advance only the durable deadline; no product clock hook is necessary.
    await store.database.transaction((tx) async {
      final saved = (await tx.query('followups',
              where: 'id=?', whereArgs: [registration['id']]))
          .single;
      final snapshot = jsonDecode(saved['snapshot'] as String) as JsonMap;
      snapshot['retryAt'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      expect(
          await tx.update('followups', {'snapshot': jsonEncode(snapshot)},
              where: 'id=?', whereArgs: [registration['id']]),
          1);
    });
    await followups.sweep();
    final completed = await state('completed');
    expect(completed['id'], registration['id']);
    expect(completed['threadId'], threadId);
    expect(completed['turnStatus'], 'completed');
    expect(completed['attempts'], 1);
    expect(completed['failedTurns'], [first['id']]);
    final endings = endedTurns();
    expect(endings, hasLength(2));
    expect(endings.last['status'], 'completed');
    expect(endings.last['id'], isNot(first['id']));
    expect(completed['turnId'], endings.last['id']);

    await followups.sweep();
    await followups.sweep();
    expect((await followups.list()).single, completed);
    final turns = (await host.readThread(threadId))['turns'] as List;
    expect(turns.map((turn) => (turn as Map)['id']),
        [first['id'], endings.last['id']]);
    expect(successfulRequests, 1);
    expect(
        await store.database.query('followup_events',
            where: 'type=?', whereArgs: ['followup.triggered']),
        hasLength(1));
    expect(
        await store.database.query('followup_events',
            where: 'type=?', whereArgs: ['followup.started']),
        hasLength(2));
    expect(
        await store.database.query('followup_events',
            where: 'type=?', whereArgs: ['followup.retrying']),
        hasLength(1));
  });

  test('real Codex 400 failure is execution_failed and is never redispatched',
      () async {
    responseStatus = 400;
    final registration = await registerReady();
    await followups.attach(host);
    final failed = await state('execution_failed');
    final turn = endedTurns().single;
    expect(turn['status'], 'failed');
    expect(jsonEncode(turn['error']), contains('Y16 invalid request'));
    expect((turn['error'] as Map)['codexErrorInfo'], 'other');
    expect(failed['id'], registration['id']);
    expect(failed['turnId'], turn['id']);
    expect(failed['turnStatus'], 'failed');
    expect(failed['attempts'] ?? 0, 0);
    expect(failed['failedTurns'] ?? [], isEmpty);
    expect(failed['retryAt'], isNull);
    expect(failed['reason'], contains('Y16 invalid request'));
    expect(rejectedRequests, 1);

    responseStatus = 200;
    await followups.sweep();
    await followups.sweep();
    expect((await followups.list()).single, failed);
    expect(endedTurns(), hasLength(1));
    final turns = (await host.readThread(threadId))['turns'] as List;
    expect(turns.map((turn) => (turn as Map)['id']), [turn['id']]);
    expect(successfulRequests, 0);
    expect(
        await store.database.query('followup_events',
            where: 'type=?', whereArgs: ['followup.started']),
        hasLength(1));
    expect(
        await store.database.query('followup_events',
            where: 'type=?', whereArgs: ['followup.retrying']),
        isEmpty);
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
