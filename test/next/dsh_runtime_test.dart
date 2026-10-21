@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/dsh_runtime.dart';
import 'package:nipaplay/next/chat/helpers.dart';
import 'package:nipaplay/next/chat/model_launch.dart';
import 'package:nipaplay/next/chat/session_store.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/repository_location.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Real DeepSeek Harness processes against a local Responses fixture. DSH and
/// Node are not part of the repository: set NIPAPLAY_DSH_NODE plus
/// NIPAPLAY_DSH_ROOT (or NIPAPLAY_DSH_BIN), or keep the experiment installs in
/// ~/.nipa-next/dsh or ~/.nipa-next/y15. Without them these tests skip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final (runtime, missing) = _locateDsh();

  test('the Codex config of a lab profile becomes a DSH route with no secret in the overlay', () {
    final route = DshRoute.fromCodexConfig('''
model = "deepseek-v4.1-flash" # chosen in the lab
model_provider = "cpa"
model_reasoning_effort = "high"
[model_providers.cpa]
name = "CPA"
base_url = "https://relay.example/v1/"
wire_api = "responses"
experimental_bearer_token = "fixture-bearer"
request_max_retries = 2
[projects."/tmp/a.b"]
trust_level = "trusted"
''');
    expect(route.baseUrl, 'https://relay.example/v1');
    expect(route.model, 'deepseek-v4.1-flash');
    expect(route.key, 'fixture-bearer');
    expect(route.reasoningEffort, 'high');
    expect(route.maxRetries, 2);
    final patch = jsonEncode(dshPatch(
        route: route,
        plugins: Directory('/plugins'),
        baseInstructions: File('/agent/nipa-base-dsh.md'),
        harness: '/harness',
        version: 'x'));
    expect(patch, isNot(contains('fixture-bearer')));
    expect(patch, contains(DshRoute.keyVariable));
    final env = DshRoute.fromCodexConfig(
        'model = "m"\nmodel_provider = "p"\n[model_providers.p]\n'
        'base_url = "http://127.0.0.1:1/v1"\nenv_key = "P_KEY"\n',
        environment: {'P_KEY': 'from-env'});
    expect(env.key, 'from-env');
    expect(() => DshRoute.fromCodexConfig('model = "m"\nmodel_provider = "openai"\n'),
        throwsStateError);
  });

  group('DSH runtime', () {
    late _Fake fake;
    late _Lab lab;

    Future<void> open(List<_Rule> rules, {int maxRetries = 0}) async {
      fake = await _Fake.start(rules);
      addTearDown(fake.close);
      lab = await _Lab.open(runtime!, fake, maxRetries: maxRetries);
      addTearDown(lab.close);
    }

    test('a turn runs as Nipa with AGENTS.md and memory, history and names readable',
        () async {
      await open([_Rule(when: ['你好'], reasoning: '想一想', text: '你好，我是 Nipa。')]);
      final host = await lab.start();
      expect(host.launchEnvironment['NIPAPLAY_AGENT_RUNTIME'], 'dsh');
      expect(jsonEncode(host.launchEnvironment), isNot(contains(_key)));
      await host.getMainSession();
      final thread = host.mainThreadId!;
      expect((await host.readThread(thread))['turns'], isEmpty);
      final started = await host.startTurn('你好');
      final turnId = started['turn']['id'] as String;
      final ended = await lab.next((e) => e['method'] == 'turn/completed');
      expect(ended['params']['turn']['id'], turnId);
      expect(ended['params']['turn']['status'], 'completed');
      expect(lab.events.any((e) => e['method'] == 'item/agentMessage/delta'), isTrue);
      expect(lab.events.any((e) => e['method'] == 'item/reasoning/textDelta'), isTrue);

      final request = fake.requests.first;
      final input = request['input'] as List;
      final system = (input.first as Map)['content'] as String;
      expect((input.first as Map)['role'], 'system');
      expect(system, startsWith('You are Nipa, the assistant inside NipaPlay'));
      expect(system, isNot(contains('coding agent')));
      expect(system, isNot(contains('DeepSeek Harness')));
      final context = jsonEncode(input.skip(1).toList());
      expect(context, contains('AGENTS_FIXTURE_MARKER'));
      expect(context, contains('PREFERENCE_MARKER'));
      expect(context, contains('INDEX_MARKER'));
      expect(context, contains('RECENT_FIXTURE for $thread'));
      final tools = [for (final tool in request['tools'] as List) tool['name']];
      expect(tools, containsAll(['bash', 'read', 'read_image', 'write', 'web_fetch', 'subagent', 'subagent_fork',
          'send_message', 'interrupt_agent', 'list_agents', 'job_output', 'job_list', 'job_kill', 'todo_write',
          'ask_user_question']));
      for (final removed in ['edit', 'glob', 'grep', 'workflow', 'skill', 'exit_plan_mode', 'working_directory',
          'create_goal', 'get_goal', 'update_goal']) {
        expect(tools, isNot(contains(removed)));
      }
      // The hook ran as the main conversation's shell would.
      final hook = jsonDecode((await File('${lab.repository.path}/hook-calls.jsonl').readAsLines()).first) as Map;
      expect(hook['chat'], host.sessionId);

      final history = await host.readThread(thread);
      final turn = (history['turns'] as List).single as Map;
      expect(turn['id'], turnId);
      expect([for (final item in turn['items'] as List) item['type']],
          ['userMessage', 'reasoning', 'agentMessage']);
      expect((turn['items'] as List).last['text'], '你好，我是 Nipa。');
      final sessions = await host.listSessions();
      expect((sessions['data'] as List).single['name'], 'NipaPlay 主会话');
      expect((sessions['data'] as List).single['preview'], '你好');
      final patch = await File('${lab.root.path}/dsh/nipa-patch.json').readAsString();
      expect(patch, isNot(contains(_key)));
      expect(jsonEncode(lab.events), isNot(contains(_key)));
    });

    test('steering reaches the running turn; interrupting stops it and clears the queue', () async {
      await open([
        _Rule(when: ['first'], unless: ['call_'], calls: [_bash('sleep 2; echo waited')]),
        _Rule(when: ['first', 'STEER_MARKER'], text: 'Saw it.'),
        _Rule(when: ['second'], calls: [_bash('sleep 30; echo never')]),
      ]);
      final host = await lab.start();
      await host.getMainSession();
      final thread = host.mainThreadId!;
      final first = (await host.startTurn('first'))['turn']['id'] as String;
      await lab.next((e) => e['method'] == 'item/started' && e['params']['item']['type'] == 'commandExecution');
      expect((await host.steer('STEER_MARKER'))['turnId'], first);
      final ended = await lab.next((e) => e['method'] == 'turn/completed');
      expect(ended['params']['turn']['id'], first);
      expect(ended['params']['turn']['status'], 'completed');
      final steered = fake.requests.indexWhere((r) => jsonEncode(r['input']).contains('STEER_MARKER'));
      expect(steered, 1, reason: 'the step after the command carries the steer');
      expect(jsonEncode(fake.requests[1]['input']), contains('waited'));

      lab.events.clear();
      final second = (await host.startTurn('second'))['turn']['id'] as String;
      await lab.next((e) => e['method'] == 'item/started' && e['params']['item']['type'] == 'commandExecution');
      final clock = Stopwatch()..start();
      await host.interrupt();
      final stopped = await lab.next((e) => e['method'] == 'turn/completed');
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
      expect(stopped['params']['turn']['id'], second);
      expect(stopped['params']['turn']['status'], 'interrupted');
      expect(host.liveness.status, 'interrupted');
      final turns = (await host.readThread(thread))['turns'] as List;
      expect([for (final t in turns) t['status']], ['completed', 'interrupted']);
      final command = ((turns.first as Map)['items'] as List).firstWhere((i) => i['type'] == 'commandExecution') as Map;
      expect(command['exitCode'], 0);
      expect(command['aggregatedOutput'], contains('waited'));
    });

    test('a restarted host resumes the thread with its history, memory and AGENTS.md', () async {
      await open([
        _Rule(when: ['one'], unless: ['two'], text: 'ANSWER_ONE'),
        _Rule(when: ['two'], unless: ['three'], text: 'ANSWER_TWO'),
        _Rule(when: ['three'], text: 'ANSWER_THREE'),
      ]);
      var host = await lab.start();
      await host.getMainSession();
      final thread = host.mainThreadId!;
      await host.startTurn('one');
      await lab.next((e) => e['method'] == 'turn/completed');
      await lab.stop();

      host = await lab.start();
      await host.getMainSession();
      expect(host.mainThreadId, thread);
      final history = await host.readThread(thread);
      expect((history['turns'] as List).single['items'].last['text'], 'ANSWER_ONE');
      await File('${lab.repository.path}/memory/preferences.md').writeAsString('PREFERENCE_MARKER_2\n');
      await host.startTurn('two');
      await lab.next((e) => e['method'] == 'turn/completed');
      final resumed = jsonEncode(fake.requests.last['input']);
      expect(resumed, contains('ANSWER_ONE'));
      expect(resumed, contains('AGENTS_FIXTURE_MARKER'));
      expect(resumed, contains('PREFERENCE_MARKER_2'));

      await host.compactThread(thread);
      lab.events.clear();
      await host.startTurn('three');
      await lab.next((e) => e['method'] == 'turn/completed');
      final compacted = jsonEncode(fake.requests.last['input']);
      expect(compacted, contains('PREFERENCE_MARKER_2'));
      expect(compacted, contains('RECENT_FIXTURE'));
      final sources = [
        for (final line in await File('${lab.repository.path}/hook-calls.jsonl').readAsLines())
          (jsonDecode(line) as Map)['action']
      ];
      expect(sources.length, greaterThanOrEqualTo(3), reason: 'start, resume, compaction');
    });

    test('a DSH subagent is a native helper task, uses its own origin and returns through DSH', () async {
      await open([
        _Rule(when: ['CHILD_TASK do it'], unless: ['started subagent', 'CHILDCHAT'],
            calls: [_bash(r'echo CHILDCHAT=$NIPAPLAY_CHAT; sleep 1')]),
        _Rule(when: ['CHILD_TASK do it', 'CHILDCHAT'], unless: ['started subagent'], text: 'CHILD_RESULT finished'),
        _Rule(when: ['请找帮手'], unless: ['started subagent'],
            calls: [{'name': 'subagent', 'args': {'description': 'child job', 'prompt': 'CHILD_TASK do it'}}]),
        _Rule(when: ['started subagent'], unless: ['CHILD_RESULT'], text: 'Parent waiting.'),
        _Rule(when: ['CHILD_RESULT'], text: 'Parent got result.'),
      ]);
      final host = await lab.start();
      await host.getMainSession();
      final parent = host.mainThreadId!;
      await lab.attachFollowups(host);
      await host.startTurn('请找帮手');
      final spawned = await lab.next((e) => e['method'] == 'item/completed' &&
          e['params']['item']['type'] == 'collabAgentToolCall' && e['params']['item']['tool'] == 'spawnAgent');
      final child = (spawned['params']['item']['receiverThreadIds'] as List).single as String;
      expect(host.threadOrigins[child], 'codex_native:$child');

      final job = await lab.until(() async => (await lab.engine.list(type: 'agent.helper'))
          .where((job) => job.input['threadId'] == child)
          .firstOrNull);
      expect(job.input['source'], 'codexNative');
      expect(job.input['parentThreadId'], parent);
      expect(job.title, 'CHILD_TASK do it');

      final command = await lab.next((e) => e['method'] == 'item/completed' &&
          e['params']['threadId'] == child && e['params']['item']['type'] == 'commandExecution');
      expect(command['params']['item']['aggregatedOutput'], contains('CHILDCHAT=native-$child'));

      await lab.next((e) => e['method'] == 'item/completed' && e['params']['item']['text'] == 'Parent got result.');
      final wait = lab.events.firstWhere((e) => e['method'] == 'item/completed' && e['params']['item']['tool'] == 'wait');
      expect(wait['params']['threadId'], parent);
      expect(wait['params']['item']['agentsStates'][child]['message'], 'CHILD_RESULT finished');
      final waitAt = lab.events.indexOf(wait);
      final childEnd = lab.events.indexWhere((e) => e['method'] == 'turn/completed' && e['params']['threadId'] == child);
      expect(childEnd, greaterThan(waitAt), reason: 'DSH hands the result over before the child is reported done');

      final finished = await lab.until(() async {
        final current = await lab.engine.get(job.jobId);
        return current.state.isTerminal ? current : null;
      });
      expect(finished.state, JobState.succeeded);
      expect(finished.receipt!.details['summary'], 'CHILD_RESULT finished');
      final row = await lab.until(() async {
        await lab.followups.sweep();
        final rows = await lab.followups.list();
        return rows.where((r) => (r['condition'] as Map)['jobId'] == job.jobId && r['state'] == 'cancelled').firstOrNull;
      });
      expect(row['consumedBy'], isNotNull);
      await lab.followups.sweep();
      await Future<void>.delayed(const Duration(seconds: 1));
      final turns = (await host.readThread(parent))['turns'] as List;
      expect(turns, hasLength(2), reason: 'DSH delivered the result; no NipaPlay followup turn');
      final children = await host.listThreads(sourceKinds: ['subAgentThreadSpawn']);
      expect([for (final t in children['data'] as List) t['id']], [child]);
      expect((children['data'] as List).single['parentThreadId'], parent);
      final mine = await host.listSessions();
      expect([for (final t in mine['data'] as List) t['id']], [parent]);
    });

    test("a host-dispatched helper thread runs its shell as that helper", () async {
      await open([
        _Rule(when: ['HELPER_WORK'], unless: ['call_'], calls: [_bash(r'echo HELPERCHAT=$NIPAPLAY_CHAT')]),
        _Rule(when: ['HELPER_WORK', 'call_'], text: 'helper done'),
      ]);
      final host = await lab.start();
      await host.getMainSession();
      final helper = await host.helperThread('job-fixture', '补齐弹幕');
      expect(helper, isNot(host.mainThreadId));
      await host.startThreadTurn(helper, '[NipaPlay helper job-fixture]\nHELPER_WORK');
      final command = await lab.next((e) => e['method'] == 'item/completed' &&
          e['params']['threadId'] == helper && e['params']['item']['type'] == 'commandExecution');
      expect(command['params']['item']['aggregatedOutput'], contains('HELPERCHAT=helper-job-fixture'));
      await lab.next((e) => e['method'] == 'turn/completed' && e['params']['threadId'] == helper);
      expect(host.originFor(helper), 'harness_cli:helper:job-fixture');
      final named = (await host.listThreads())['data'] as List;
      expect(named.firstWhere((t) => t['id'] == helper)['name'], '补齐弹幕');
    });

    test('task.cancel stops a running DSH subagent', () async {
      await open([
        _Rule(when: ['CHILD_TASK long'], unless: ['started subagent'], calls: [_bash('sleep 30')]),
        _Rule(when: ['请找帮手'], unless: ['started subagent'],
            calls: [{'name': 'subagent', 'args': {'description': 'long job', 'prompt': 'CHILD_TASK long'}}]),
        _Rule(when: ['started subagent'], unless: ['Background subagent'], text: 'Parent waiting.'),
        _Rule(when: ['Background subagent'], text: 'Parent heard.', once: false),
      ]);
      final host = await lab.start();
      await host.getMainSession();
      await lab.attachFollowups(host);
      await host.startTurn('请找帮手');
      final running = await lab.next((e) => e['method'] == 'item/started' &&
          e['params']['item']['type'] == 'commandExecution');
      final child = running['params']['threadId'] as String;
      final job = await lab.until(() async => (await lab.engine.list(type: 'agent.helper'))
          .where((job) => job.input['threadId'] == child && job.state == JobState.running)
          .firstOrNull);
      await lab.engine.cancel(job.jobId);
      final stopped = await lab.next((e) => e['method'] == 'turn/completed' && e['params']['threadId'] == child);
      expect(stopped['params']['turn']['status'], 'interrupted');
      final cancelled = await lab.until(() async {
        final current = await lab.engine.get(job.jobId);
        return current.state.isTerminal ? current : null;
      });
      expect(cancelled.state, JobState.cancelled);
      final heard = await lab.next((e) => e['method'] == 'item/completed' && e['params']['item']['tool'] == 'wait');
      expect(heard['params']['item']['agentsStates'][child]['status'], 'interrupted');
    });

    test('a provider 429 fails the turn and the followup is redelivered later', () async {
      await open([_Rule(when: ['Inspect these facts'], status: 429, once: false)]);
      final host = await lab.start();
      await host.getMainSession();
      final thread = host.mainThreadId!;
      lab.followups.start();
      await lab.followups.register({
        'when': {'event': 'library.file_added', 'objectId': '/fixture/video.mp4'},
        'threadId': thread,
        'instruction': 'Inspect these facts and reply OK.',
      }, Invocation(origin: 'harness_cli', id: 'dsh-429'));
      await lab.followups.hookEvent('library.file_added', '/fixture/video.mp4',
          {'event': 'library.file_added', 'objectId': '/fixture/video.mp4'});
      await lab.followups.attach(host);
      final ended = await lab.next((e) => e['method'] == 'turn/completed');
      expect(ended['params']['turn']['status'], 'failed');
      expect(jsonEncode(ended['params']['turn']['error']), contains('429'));
      final retry = await lab.until(() async {
        await lab.followups.sweep();
        final row = (await lab.followups.list()).single;
        return row['state'] == 'ready' && row['attempts'] == 1 ? row : null;
      });
      expect(retry['turnStatus'], 'failed');
      expect(retry['failedTurns'], [ended['params']['turn']['id']]);
      expect(retry['turnId'], isNull);
      expect(DateTime.parse(retry['retryAt'] as String).isAfter(DateTime.now().toUtc()), isTrue);
      final history = ((await host.readThread(thread))['turns'] as List).single as Map;
      expect(history['status'], 'failed');
      expect(jsonEncode(history['error']), contains('429'));
    });

    test("ask_user_question reaches the person as Codex's request_user_input", () async {
      await open([
        _Rule(when: ['ask me'], unless: ['call_'], calls: [
          {
            'name': 'ask_user_question',
            'args': {
              'questions': [
                {'id': 'res', 'question': '要哪个清晰度？', 'header': '清晰度',
                  'options': [{'label': '1080p'}, {'label': '720p'}]}
              ]
            }
          }
        ]),
        _Rule(when: ['ask me', 'call_'], text: '好。'),
      ]);
      final host = await lab.start();
      await host.getMainSession();
      final asked = host.userInputRequests.first;
      await host.startTurn('ask me');
      final request = await asked.timeout(const Duration(seconds: 30));
      final question = (request['params']['questions'] as List).single as Map;
      expect(question['question'], '要哪个清晰度？');
      expect([for (final o in question['options'] as List) o['label']], ['1080p', '720p']);
      await host.answerUserInput(request['id'] as Object, {'res': ['1080p', '带中文字幕']});
      await lab.next((e) => e['method'] == 'turn/completed');
      final output = jsonEncode(fake.requests.last['input']);
      expect(output, contains('1080p'));
      expect(output, contains('带中文字幕'));
    });
  }, skip: missing);
}

const _key = 'dsh-fixture-bearer-7f3c';

Map<String, Object?> _bash(String command) =>
    {'name': 'bash', 'args': {'description': 'fixture', 'command': command}};

(DshRuntime?, String?) _locateDsh() {
  final home = Platform.environment['HOME'] ?? '';
  final candidates = <Map<String, String>>[
    Platform.environment,
    for (final base in ['$home/.nipa-next/dsh', '$home/.nipa-next/y15'])
      {
        'NIPAPLAY_AGENT_RUNTIME': 'dsh',
        'NIPAPLAY_DSH_NODE': '$base/node-install/node_modules/node/bin/node',
        'NIPAPLAY_DSH_ROOT': '$base/dsh-install',
      },
  ];
  for (final environment in candidates) {
    if (environment['NIPAPLAY_DSH_NODE'] == null) continue;
    try {
      final runtime = DshRuntime.select({...environment, 'NIPAPLAY_AGENT_RUNTIME': 'dsh'});
      if (runtime != null) return (runtime, null);
    } on StateError {
      continue;
    }
  }
  return (null, 'DeepSeek Harness and Node 24 are not installed on this machine '
      '(set NIPAPLAY_DSH_NODE and NIPAPLAY_DSH_ROOT).');
}

final class _Rule {
  _Rule({this.when = const [], this.unless = const [], this.once = true, this.text, this.reasoning,
      this.calls = const [], this.status});
  final List<String> when, unless;
  final bool once;
  final String? text, reasoning;
  final List<Map<String, Object?>> calls;
  final int? status;
  bool used = false;
}

/// An OpenAI Responses endpoint that answers by rule from the request input.
final class _Fake {
  _Fake(this.server, this.rules);
  final HttpServer server;
  final List<_Rule> rules;
  final requests = <Map<String, Object?>>[];
  int get port => server.port;

  static Future<_Fake> start(List<_Rule> rules) async {
    final fake = _Fake(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), rules);
    fake.server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    if (request.method != 'POST' || !request.uri.path.endsWith('/responses')) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
    final n = requests.length;
    requests.add(body);
    final blob = jsonEncode(body['input']);
    final rule = rules.where((r) => !r.used && r.when.every(blob.contains) && !r.unless.any(blob.contains)).firstOrNull;
    if (rule != null && rule.once) rule.used = true;
    final response = request.response;
    if (rule?.status case final status?) {
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      response.add(utf8.encode(jsonEncode({'error': {'message': 'fixture $status', 'type': 'rate_limit_error'}})));
      await response.close();
      return;
    }
    response.headers.set('content-type', 'text/event-stream');
    void send(String type, Map<String, Object?> data) => response
        .add(utf8.encode('event: $type\ndata: ${jsonEncode({'type': type, ...data})}\n\n'));
    final created = {'id': 'resp_$n', 'object': 'response', 'status': 'in_progress', 'model': 'fixture-model', 'output': []};
    send('response.created', {'response': created});
    final output = <Map<String, Object?>>[];
    void add(Map<String, Object?> item) {
      final index = output.length;
      send('response.output_item.added', {'output_index': index, 'item': item});
      output.add(item);
    }
    if (rule?.reasoning case final thought?) {
      final item = {'type': 'reasoning', 'id': 'rs_$n', 'summary': <Object>[]};
      add(item);
      final index = output.length - 1;
      send('response.reasoning_summary_part.added', {'item_id': 'rs_$n', 'output_index': index, 'summary_index': 0, 'part': {'type': 'summary_text', 'text': ''}});
      send('response.reasoning_summary_text.delta', {'item_id': 'rs_$n', 'output_index': index, 'summary_index': 0, 'delta': thought});
      send('response.reasoning_summary_text.done', {'item_id': 'rs_$n', 'output_index': index, 'summary_index': 0, 'text': thought});
      output[index] = {...item, 'summary': [{'type': 'summary_text', 'text': thought}]};
      send('response.output_item.done', {'output_index': index, 'item': output[index]});
    }
    final text = rule == null ? 'OK' : rule.text;
    if (text != null) {
      final done = {'type': 'message', 'id': 'msg_$n', 'role': 'assistant', 'status': 'completed',
        'content': [{'type': 'output_text', 'text': text, 'annotations': <Object>[]}]};
      add({...done, 'content': <Object>[], 'status': 'in_progress'});
      final index = output.length - 1;
      send('response.content_part.added', {'item_id': 'msg_$n', 'output_index': index, 'content_index': 0, 'part': {'type': 'output_text', 'text': '', 'annotations': <Object>[]}});
      final half = text.length ~/ 2;
      for (final delta in [text.substring(0, half), text.substring(half)]) {
        send('response.output_text.delta', {'item_id': 'msg_$n', 'output_index': index, 'content_index': 0, 'delta': delta});
      }
      send('response.output_text.done', {'item_id': 'msg_$n', 'output_index': index, 'content_index': 0, 'text': text});
      output[index] = done;
      send('response.output_item.done', {'output_index': index, 'item': done});
    }
    for (final (k, call) in (rule?.calls ?? const <Map<String, Object?>>[]).indexed) {
      final item = {'type': 'function_call', 'id': 'fc_${n}_$k', 'call_id': 'call_${n}_$k', 'name': call['name'],
        'arguments': jsonEncode(call['args']), 'status': 'completed'};
      add({...item, 'arguments': '', 'status': 'in_progress'});
      final index = output.length - 1;
      send('response.function_call_arguments.delta', {'item_id': item['id'], 'output_index': index, 'delta': item['arguments']});
      send('response.function_call_arguments.done', {'item_id': item['id'], 'output_index': index, 'arguments': item['arguments']});
      output[index] = item;
      send('response.output_item.done', {'output_index': index, 'item': item});
    }
    send('response.completed', {
      'response': {...created, 'status': 'completed', 'output': output,
        'usage': {'input_tokens': 10, 'output_tokens': 2, 'total_tokens': 12}}
    });
    await response.close();
  }
}

final class _Location implements RepositoryLocation {
  _Location(this.path);
  @override
  final String path;
  @override
  Future<void> get ready async {}
}

/// A disposable lab profile: harness repository, Next data, Codex-style model
/// configuration pointing at the fixture, and NipaPlay's task services.
final class _Lab {
  _Lab(this.runtime, this.dir);
  final DshRuntime runtime;
  final Directory dir;
  late final Directory root, repository;
  late final SqliteJobStore store;
  late final TaskEngine engine;
  late final Followups followups;
  late final Helpers helpers;
  late final AgentEndpoint endpoint;
  ChatHost? host;
  StreamSubscription<ChatMessage>? _subscription;
  final events = <ChatMessage>[];
  HttpOverrides? _overrides;

  static Future<_Lab> open(DshRuntime runtime, _Fake fake, {int maxRetries = 0}) async {
    final lab = _Lab(runtime, await Directory.systemTemp.createTemp('dsh-runtime-'));
    lab._overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    lab.root = await Directory('${lab.dir.path}/next').create();
    lab.repository = await Directory('${lab.dir.path}/harness').create();
    final git = await Process.run('git', ['init', '--quiet', '--template=', '--initial-branch=main'],
        workingDirectory: lab.repository.path);
    expect(git.exitCode, 0, reason: git.stderr.toString());
    await File('${lab.repository.path}/AGENTS.md').writeAsString('# Harness fixture\n\nAGENTS_FIXTURE_MARKER\n');
    await Directory('${lab.repository.path}/memory').create();
    await File('${lab.repository.path}/memory/preferences.md').writeAsString('PREFERENCE_MARKER\n');
    await File('${lab.repository.path}/memory/MEMORY.md').writeAsString('INDEX_MARKER\n');
    await Directory('${lab.repository.path}/hooks').create();
    await File('assets/next/harness/hooks/session_start.py').copy('${lab.repository.path}/hooks/session_start.py');
    // The seed hook loads ./nipa for memory.context; this one answers offline.
    await File('${lab.repository.path}/nipa').writeAsString(r'''#!/usr/bin/env python3
import json, os
class Client:
    token = 'fixture-endpoint-token'
    def call(self, action, inputs):
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hook-calls.jsonl'), 'a') as log:
            log.write(json.dumps({'action': action, 'inputs': inputs, 'chat': os.environ.get('NIPAPLAY_CHAT')}) + '\n')
        return {'status': 'completed', 'result': {'settings': {'subtitle': 'zh-Hans'},
                'recent': {'text': 'RECENT_FIXTURE for ' + str(inputs.get('threadId')), 'omitted': []}}}
    def result(self, value):
        return value['result']
def redact(text, secrets=()):
    for secret in secrets:
        text = text.replace(secret, '[redacted]')
    return text
''');
    final home = await Directory('${lab.dir.path}/codex-home').create();
    await File('${home.path}/config.toml').writeAsString(
        'model = "fixture-model"\nmodel_provider = "fixture"\n'
        '[model_providers.fixture]\nname = "DSH fixture"\n'
        'base_url = "http://127.0.0.1:${fake.port}/v1"\nwire_api = "responses"\n'
        'experimental_bearer_token = "$_key"\nrequest_max_retries = $maxRetries\n');
    sqfliteFfiInit();
    lab.store = await SqliteJobStore.open(lab.root, factory: databaseFactoryFfi);
    lab.helpers = Helpers();
    lab.engine = TaskEngine(store: lab.store, ownerDeviceId: 'dsh', executors: [lab.helpers]);
    lab.followups = Followups(lab.store.database, lab.engine, _Location(lab.repository.path));
    lab.helpers.engine = lab.engine;
    lab.helpers.followups = lab.followups;
    lab.followups.helpers = lab.helpers;
    await lab.engine.start();
    lab.endpoint = AgentEndpoint(
        harness: Harness([]),
        seed: {},
        appVersion: 'dsh',
        credentialFile: File('${lab.root.path}/endpoint.json'),
        seedRepository: Directory('${lab.root.path}/harness-seed'),
        port: 0);
    return lab;
  }

  Future<ChatHost> start() async {
    final created = host = ChatHost(
        endpoint: endpoint,
        repository: repository,
        labRoot: dir,
        sessions: SessionStore(store.database),
        modelLaunch: () async => const ModelLaunch(revision: 0),
        baseInstructions: File('assets/next/agent/nipa-base-dsh.md'),
        dsh: runtime,
        dshPlugins: Directory('assets/next/agent/dsh'));
    events.clear();
    _subscription = created.events.listen(events.add);
    await created.start();
    return created;
  }

  Future<void> attachFollowups(ChatHost host) async {
    followups.start();
    await followups.attach(host);
  }

  Future<void> stop() async {
    await followups.attach(null);
    await host?.close();
    await _subscription?.cancel();
    host = null;
  }

  Future<ChatMessage> next(bool Function(ChatMessage) test,
      {Duration timeout = const Duration(seconds: 45)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final event in List.of(events)) {
        if (test(event)) return event;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Event not seen; last: ${jsonEncode(events.reversed.take(5).toList())}');
  }

  Future<T> until<T>(Future<T?> Function() probe,
      {Duration timeout = const Duration(seconds: 45)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await probe() case final T value) return value;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('Condition not met in $timeout');
  }

  Future<void> close() async {
    await stop();
    await followups.close();
    await engine.close();
    await endpoint.stop();
    HttpOverrides.global = _overrides;
    await dir.delete(recursive: true);
  }
}
