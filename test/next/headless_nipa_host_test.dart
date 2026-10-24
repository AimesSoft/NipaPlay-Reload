@Timeout(Duration(minutes: 8))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/dsh_runtime.dart';
import 'package:path/path.dart' as p;

/// Nipa on a real headless host: the host program is started as the person
/// would start it, the model is entered with `--model-set` (the key on
/// standard input), and a turn is sent, waited for and read back through the
/// same endpoint `./nipa chat` uses. The runtime is a real DeepSeek Harness;
/// the model is a local fixture, so no key or account is involved.
///
/// Needs the Dart SDK (found through FLUTTER_ROOT, or NIPAPLAY_TEST_DART) and
/// an installed DeepSeek Harness (NIPAPLAY_DSH_NODE and NIPAPLAY_DSH_ROOT, or
/// one a download left); without them the tests skip.
void main() {
  final dart = _dart();
  final (runtime, runtimeMissing) = _locateDsh();
  final skip = dart == null
      ? 'No Dart SDK: set NIPAPLAY_TEST_DART.'
      : runtimeMissing ?? false;

  late Directory dir, data;
  late _Fake fake;
  late _Host host;

  // The host program is compiled once; every start below is then quick and
  // the machine is not asked to compile it a dozen times.
  late Directory build;
  late String kernel;
  setUpAll(() async {
    if (dart == null) return;
    build = await Directory.systemTemp.createTemp('headless-nipa-kernel-');
    kernel = '${build.path}/headless.dill';
    final compiled = await Process.run(dart, [
      'compile',
      'kernel',
      '--packages=.dart_tool/package_config.json',
      'bin/nipaplay_headless.dart',
      '-o',
      kernel
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stdout}${compiled.stderr}');
  });
  tearDownAll(() async {
    if (dart != null) await build.delete(recursive: true);
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('headless-nipa-host-');
    data = Directory(p.join(dir.path, 'data'));
    fake = await _Fake.start();
    host = _Host(dart ?? 'dart', dart == null ? '' : kernel, runtime, data, fake);
  });
  tearDown(() async {
    await host.stop();
    await fake.close();
    await dir.delete(recursive: true);
  });

  test('without a model she is not running, and says what she lacks', () async {
    await host.start();
    final runtimeFacts = (await host.call('app.runtime', {}))['result'] as Map;
    final conversation = runtimeFacts['conversationHost'] as Map;
    expect(conversation['runs'], false);
    expect(conversation['state'], 'missing');
    expect(conversation['missing'], containsAll(['model', 'key']));
    expect(conversation['reason'], contains('--model-set'));
    expect((runtimeFacts['model'] as Map)['keyConfigured'], false);

    final sent = await host.call('chat.send', {'text': 'hello'});
    expect(sent['status'], 'failed');
    expect(jsonEncode(sent), contains('no model is set'));
    final sessions = await host.call('chat.session.list', {});
    expect(sessions['status'], 'failed');
    expect(jsonEncode(sessions), contains('--model-set'));
    expect(fake.requests, isEmpty);
  }, skip: dart == null ? 'No Dart SDK: set NIPAPLAY_TEST_DART.' : false);

  test('a key entered from the command line starts her; a turn runs in the background and reads back',
      () async {
    await host.start();
    final entered = await host.modelSet();
    expect(entered.stdout, isNot(contains(_key)));
    expect(entered.stderr, isNot(contains(_key)));
    await host.until(() async => (await host.conversation())['runs'] == true,
        'Nipa is running');
    final facts = await host.conversation();
    expect(facts['model'], 'fixture-model');

    // A turn: sent, running in the background, waited for, read back. While
    // it runs the host keeps answering: the slowest answer is the measure of
    // the event loop (it is the only isolate).
    final answers = <Duration>[];
    final probing = host.probe(answers);
    final sent = (await host.call('chat.send', {'text': 'Say hello. NONCE-1'}))['result'] as Map;
    expect(sent['turnId'], isNotNull);
    final waited = (await host.call(
        'chat.status', {'threadId': sent['threadId'], 'waitSeconds': 55}))['result'] as Map;
    expect(waited['busy'], false, reason: jsonEncode(waited));
    expect((waited['turn'] as Map)['status'], 'completed');
    final read = (await host.call(
        'chat.read', {'threadId': sent['threadId'], 'turns': 1}))['result'] as Map;
    final items = ((read['turns'] as List).single as Map)['items'] as List;
    expect(items.first, containsPair('type', 'userMessage'));
    expect(jsonEncode(items), contains('Fixture reply: hello'));

    // The same conversation, and a command she runs is a step to look back on.
    final second =
        (await host.call('chat.send', {'text': 'RUN_COMMAND NONCE-2'}))['result'] as Map;
    expect(second['threadId'], sent['threadId']);
    await host.call('chat.status', {'threadId': second['threadId'], 'waitSeconds': 55});
    final again = (await host.call('chat.read', {'turns': 1}))['result'] as Map;
    final reply = jsonEncode(again);
    expect(reply, contains('commandExecution'));
    expect(reply, contains('The command printed headless-nipa-fixture.'));
    final process = (await host.call('chat.turn.process',
        {'threadId': second['threadId'], 'turnId': second['turnId']}))['result'] as Map;
    expect(process['found'], true);
    expect(jsonEncode(process), contains('headless-nipa-fixture'));
    host.probing = false;
    await probing;
    expect(answers, isNotEmpty);
    answers.sort();
    expect(answers.last, lessThan(const Duration(milliseconds: 600)),
        reason: 'the host stopped answering for ${answers.last}');

    // The python client the person types into does the same.
    final cli = await host.nipa(['chat', 'say', 'Say hello again. NONCE-3', '--wait', '55']);
    final said = jsonDecode(cli) as Map;
    expect((said['turn'] as Map)['status'], 'completed');
    expect(said['reply'], contains('Fixture reply: hello'));
    expect(jsonDecode(await host.nipa(['chat', 'list']))['data'], isNotEmpty);

    // Her harness is hers: the memory block the hooks build from this host's
    // own harness reached the model with the first message.
    expect(jsonEncode(fake.requests.first['input']), contains('nipa_memory'));

    // The key reached the model and nowhere else on the host.
    expect(fake.keys.toSet(), {_key});
    var found = <String>[];
    await for (final entity in data.list(recursive: true, followLinks: false)) {
      if (entity is! File ||
          entity.path.contains('${p.separator}vault${p.separator}') ||
          entity.path.contains('${p.separator}.git${p.separator}') ||
          entity.path.contains('${p.separator}dsh-runtime${p.separator}')) {
        continue;
      }
      if ((await entity.readAsBytes()).length > 20 * 1024 * 1024) continue;
      if (latin1.decode(await entity.readAsBytes()).contains(_key)) {
        found.add(entity.path);
      }
    }
    expect(found, isEmpty, reason: 'the key was written to $found');
    expect(host.output.join(), isNot(contains(_key)));

    // The main conversation is the one she was started on, and is kept.
    final sessions = (await host.call('chat.session.list', {}))['result'] as Map;
    expect(sessions['mainThreadId'], sent['threadId']);
  }, skip: skip);

  test('Nipa\'s own calls, helpers and hooks cannot speak or stop for the person', () async {
    await host.start();
    await host.modelSet();
    await host.until(() async => (await host.conversation())['runs'] == true,
        'Nipa is running');
    for (final origin in ['abc', 'helper-job1', 'native-thread1']) {
      final refused = await host.call('chat.send', {'text': 'as me'}, chat: origin);
      expect(refused['status'], 'failed', reason: origin);
      expect(jsonEncode(refused), contains('speaks for the person'));
      expect((await host.call('chat.stop', {}, chat: origin))['status'], 'failed',
          reason: origin);
    }
    final hook = await host.call('chat.send', {'text': 'as me'}, hook: 'tick');
    expect(hook['status'], 'failed');
    expect(fake.turns, 0, reason: 'nothing reached the model');
  }, skip: skip);

  test('a busy conversation refuses a second turn, and a turn can be stopped', () async {
    await host.start();
    await host.modelSet();
    await host.until(() async => (await host.conversation())['runs'] == true,
        'Nipa is running');
    final sent = (await host.call('chat.send', {'text': 'HANG NONCE-4'}))['result'] as Map;
    await host.until(() async => fake.hanging > 0, 'the model holds the request');
    final busy = await host.call('chat.send', {'text': 'second'});
    expect(busy['status'], 'failed');
    expect(jsonEncode(busy), contains('already running'));
    final stopped = (await host.call('chat.stop', {}))['result'] as Map;
    expect(stopped['stopped'], true);
    final done = (await host.call(
        'chat.status', {'threadId': sent['threadId'], 'waitSeconds': 30}))['result'] as Map;
    expect(done['busy'], false);
    expect((done['turn'] as Map)['status'], 'interrupted');
    expect(((await host.call('chat.stop', {}))['result'] as Map)['stopped'], false);
  }, skip: skip);

  test('a wake from a script reaches her here, on her main conversation', () async {
    await host.start();
    await host.modelSet();
    await host.until(() async => (await host.conversation())['runs'] == true,
        'Nipa is running');
    final woke = await host.call('agent.wake', {
      'instruction': 'WAKE NONCE-5 look at the library',
      'title': 'wake',
      'facts': {'reason': 'fixture'}
    });
    expect(woke['status'], 'completed', reason: jsonEncode(woke));
    final id = ((woke['result'] as Map)['followup'] as Map)['id'];
    await host.until(() async {
      final listed = (await host.call('followup.list', {}))['result'] as Map;
      final row = (listed['followups'] as List)
          .cast<Map>()
          .firstWhere((row) => row['id'] == id);
      return row['state'] == 'completed';
    }, 'the wake was delivered and its turn ended');
    final main = (await host.call('chat.session.list', {}))['result'] as Map;
    final read = (await host.call('chat.read',
        {'threadId': main['mainThreadId'], 'turns': 1}))['result'] as Map;
    expect(jsonEncode(read), contains('WAKE NONCE-5'));
    expect(fake.turns, 1);
  }, skip: skip);

  test('the agent switch stops her and starts her again, with the same main conversation',
      () async {
    await host.start();
    await host.modelSet();
    await host.until(() async => (await host.conversation())['runs'] == true,
        'Nipa is running');
    final main = (await host.call('chat.session.list', {}))['result'] as Map;
    expect((await host.cli(['--agent-disable'])).exitCode, 0);
    await host.until(() async => (await host.conversation())['state'] == 'disabled',
        'Nipa is off');
    final off = await host.conversation();
    expect(off['enabled'], false);
    expect(off['runs'], false);
    expect(off['reason'], contains('agent switch'));
    expect(await host.call('chat.send', {'text': 'hi'}), containsPair('status', 'failed'));
    await host.cli(['--agent-enable']);
    await host.until(() async => (await host.conversation())['runs'] == true,
        'Nipa is back');
    final back = (await host.call('chat.session.list', {}))['result'] as Map;
    expect(back['mainThreadId'], main['mainThreadId']);
  }, skip: skip);
}

const _key = 'sk-headless-fixture-7d41c2';

String? _dart() {
  final named = Platform.environment['NIPAPLAY_TEST_DART'];
  if (named != null) return named;
  final flutter = Platform.environment['FLUTTER_ROOT'];
  if (flutter != null) {
    final candidate = '$flutter/bin/cache/dart-sdk/bin/dart';
    if (File(candidate).existsSync()) return candidate;
  }
  final home = Platform.environment['HOME'] ?? '';
  for (final root in ['$home/development/flutter-3.44.6']) {
    final candidate = '$root/bin/cache/dart-sdk/bin/dart';
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

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
  // A runtime a download left (read only).
  final installs = Directory('$home/.nipa-next/dp/mac-data/dsh-runtime');
  if (installs.existsSync()) {
    for (final install in installs.listSync().whereType<Directory>()) {
      candidates.add({
        'NIPAPLAY_AGENT_RUNTIME': 'dsh',
        'NIPAPLAY_DSH_NODE': '${install.path}/node/node',
        'NIPAPLAY_DSH_ROOT': '${install.path}/lib',
      });
    }
  }
  for (final environment in candidates) {
    if (environment['NIPAPLAY_DSH_NODE'] == null) continue;
    try {
      final runtime =
          DshRuntime.select({...environment, 'NIPAPLAY_AGENT_RUNTIME': 'dsh'});
      if (runtime != null) return (runtime, null);
    } on StateError {
      continue;
    }
  }
  return (
    null,
    'DeepSeek Harness and Node 24 are not installed on this machine '
        '(set NIPAPLAY_DSH_NODE and NIPAPLAY_DSH_ROOT).'
  );
}

/// The host program as the person starts it, and the ways of reaching it.
final class _Host {
  _Host(this.dart, this.kernel, this.runtime, this.data, this.fake);
  final String dart, kernel;
  final DshRuntime? runtime;
  final Directory data;
  final _Fake fake;
  Process? _child;
  final output = <String>[];
  bool probing = false;

  Map<String, String> get _environment => {
        for (final e in Platform.environment.entries)
          if (!{'http_proxy', 'https_proxy', 'all_proxy'}
              .contains(e.key.toLowerCase()))
            e.key: e.value,
        'NO_PROXY': '127.0.0.1,localhost',
        if (runtime != null) ...{
          'NIPAPLAY_AGENT_RUNTIME': 'dsh',
          'NIPAPLAY_DSH_NODE': runtime!.node,
          'NIPAPLAY_DSH_BIN': runtime!.bin,
        },
      };

  List<String> _arguments(List<String> more) => [
        kernel,
        '--data',
        data.path,
        '--agent-assets',
        Directory('assets/next/agent').absolute.path,
        ...more,
      ];

  Future<void> start() async {
    final child = _child = await Process.start(dart, _arguments(['--seed', Directory('assets/next/harness').absolute.path]),
        environment: _environment, includeParentEnvironment: false);
    child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(output.add);
    child.stderr.transform(utf8.decoder).listen(output.add);
    await until(() async => output.any((l) => l.contains('"status":"running"')),
        'the host is running',
        timeout: const Duration(seconds: 90));
  }

  /// The command line, e.g. `--model-set …`; returns its exit and output.
  Future<({int exitCode, String stdout, String stderr})> cli(List<String> more,
      {String? stdin}) async {
    final process = await Process.start(dart, _arguments(more),
        environment: _environment, includeParentEnvironment: false);
    if (stdin != null) process.stdin.write(stdin);
    await process.stdin.close();
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(const Duration(minutes: 2));
    return (exitCode: code, stdout: await out, stderr: await err);
  }

  Future<({int exitCode, String stdout, String stderr})> modelSet() => cli([
        '--model-set',
        '--provider',
        'Fixture',
        '--base-url',
        'http://127.0.0.1:${fake.port}/v1',
        '--model',
        'fixture-model',
        '--key-stdin',
      ], stdin: '$_key\n');

  /// `./nipa …` of the host's harness, as the person types it.
  Future<String> nipa(List<String> arguments) async {
    final result = await Process.run(
        'python3', ['${data.path}/harness/nipa', ...arguments],
        environment: {'PATH': Platform.environment['PATH'] ?? '', 'HOME': Platform.environment['HOME'] ?? ''},
        includeParentEnvironment: false);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    return result.stdout as String;
  }

  Future<Map<String, Object?>> call(String action, Map<String, Object?> input,
      {String? chat, String? hook}) async {
    final endpoint =
        jsonDecode(await File('${data.path}/endpoint.json').readAsString()) as Map;
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.postUrl(Uri.parse(endpoint['url'] as String));
      request.headers
        ..set('Authorization', 'Bearer ${endpoint['token']}')
        ..contentType = ContentType.json;
      if (chat != null) request.headers.set('X-NipaPlay-Chat', chat);
      if (hook != null) request.headers.set('X-Nipa-Hook', hook);
      request.add(utf8.encode(jsonEncode(
          {'operation': 'call', 'action': action, 'input': input, 'execute': false})));
      final response = await request.close();
      return jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map> conversation() async =>
      ((await call('app.runtime', {}))['result'] as Map)['conversationHost'] as Map;

  /// Calls the host over and over while [probing]; each answer's time goes to [times].
  Future<void> probe(List<Duration> times) async {
    probing = true;
    while (probing) {
      final watch = Stopwatch()..start();
      await call('chat.status', {});
      times.add(watch.elapsed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> until(Future<bool> Function() test, String what,
      {Duration timeout = const Duration(seconds: 120)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await test()) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('Not reached in $timeout: $what\n${output.take(30).join('\n')}');
  }

  Future<void> stop() async {
    final child = _child;
    if (child == null) return;
    child.kill();
    await child.exitCode.timeout(const Duration(seconds: 20), onTimeout: () {
      child.kill(ProcessSignal.sigkill);
      return -1;
    });
  }
}

/// An OpenAI Responses endpoint for the host to think with. It answers by
/// what the request holds: a tool result, `RUN_COMMAND` (one shell command),
/// `HANG` (never answers), or otherwise a short reply.
final class _Fake {
  _Fake(this.server);
  final HttpServer server;
  final requests = <Map<String, Object?>>[];
  final keys = <String>[];
  int hanging = 0, turns = 0;
  final _held = <HttpResponse>[];
  int get port => server.port;

  static Future<_Fake> start() async {
    final fake = _Fake(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    fake.server.listen(fake._handle);
    return fake;
  }

  Future<void> close() async {
    for (final held in _held) {
      try {
        await held.close();
      } catch (_) {}
    }
    await server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.method != 'POST' || !request.uri.path.endsWith('/responses')) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    final auth = request.headers.value('authorization') ?? '';
    keys.add(auth.replaceFirst('Bearer ', ''));
    final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
    if (jsonEncode(body).contains('What colour is this image?')) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'output': [
          {
            'content': [
              {'type': 'output_text', 'text': 'Red'}
            ]
          }
        ]
      }));
      await request.response.close();
      return;
    }
    turns++;
    final n = requests.length;
    requests.add(body);
    // Each turn's text carries NONCE-k; the newest k is the turn being
    // answered (the history and the memory block hold the older ones).
    final input = jsonEncode(body['input']);
    final k = RegExp(r'NONCE-(\d+)')
        .allMatches(input)
        .map((m) => int.parse(m.group(1)!))
        .fold(0, (a, b) => a > b ? a : b);
    final toolResult =
        input.contains('function_call_output') && input.contains('call_NONCE-$k');
    final wantsCommand = input.contains('RUN_COMMAND NONCE-$k');
    final hangs = input.contains('HANG NONCE-$k') && !toolResult;
    final response = request.response..headers.set('content-type', 'text/event-stream');
    void send(String type, Map<String, Object?> data) => response
        .add(utf8.encode('event: $type\ndata: ${jsonEncode({'type': type, ...data})}\n\n'));
    final created = {
      'id': 'resp_$n',
      'object': 'response',
      'status': 'in_progress',
      'model': 'fixture-model',
      'output': <Object>[]
    };
    send('response.created', {'response': created});
    if (hangs) {
      hanging++;
      _held.add(response);
      return;
    }
    final output = <Map<String, Object?>>[];
    if (wantsCommand && !toolResult) {
      final item = {
        'type': 'function_call',
        'id': 'fc_$n',
        'call_id': 'call_NONCE-$k',
        'name': 'bash',
        'arguments': jsonEncode(
            {'description': 'fixture', 'command': 'echo headless-nipa-fixture'}),
        'status': 'completed'
      };
      send('response.output_item.added',
          {'output_index': 0, 'item': {...item, 'arguments': '', 'status': 'in_progress'}});
      send('response.function_call_arguments.delta',
          {'item_id': item['id'], 'output_index': 0, 'delta': item['arguments']});
      send('response.function_call_arguments.done',
          {'item_id': item['id'], 'output_index': 0, 'arguments': item['arguments']});
      send('response.output_item.done', {'output_index': 0, 'item': item});
      output.add(item);
    } else {
      final text = toolResult
          ? 'The command printed headless-nipa-fixture.'
          : 'Fixture reply: hello';
      final done = {
        'type': 'message',
        'id': 'msg_$n',
        'role': 'assistant',
        'status': 'completed',
        'content': [
          {'type': 'output_text', 'text': text, 'annotations': <Object>[]}
        ]
      };
      send('response.output_item.added', {
        'output_index': 0,
        'item': {...done, 'content': <Object>[], 'status': 'in_progress'}
      });
      send('response.content_part.added', {
        'item_id': 'msg_$n',
        'output_index': 0,
        'content_index': 0,
        'part': {'type': 'output_text', 'text': '', 'annotations': <Object>[]}
      });
      final half = text.length ~/ 2;
      for (final delta in [text.substring(0, half), text.substring(half)]) {
        send('response.output_text.delta',
            {'item_id': 'msg_$n', 'output_index': 0, 'content_index': 0, 'delta': delta});
      }
      send('response.output_text.done',
          {'item_id': 'msg_$n', 'output_index': 0, 'content_index': 0, 'text': text});
      send('response.output_item.done', {'output_index': 0, 'item': done});
      output.add(done);
    }
    send('response.completed', {
      'response': {
        ...created,
        'status': 'completed',
        'output': output,
        'usage': {'input_tokens': 10, 'output_tokens': 2, 'total_tokens': 12}
      }
    });
    await response.close();
  }
}
