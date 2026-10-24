import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/headless/ports.dart' show HeadlessRepository;
import 'package:nipaplay/next/chat/delegation_message.dart';
import 'package:nipaplay/next/mesh/delegation.dart';
import 'package:nipaplay/next/ui/conversation/chat_context.dart';
import 'package:nipaplay/next/mesh/delegation_host.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mesh_delegation_support.dart';

const _devices = {'mac': 'MacBook', 'ipad': 'iPad'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeChat chat;
  late AgentDelegations receiver;
  var running = true;
  final notes = <(String, String, JsonMap)>[];

  AgentDelegations makeReceiver(Directory root) => AgentDelegations(
      root: root,
      chat: () => running && chat.available ? chat : null,
      unavailableReason: () => 'Next chat host is disabled.',
      deviceName: (id) => _devices[id],
      record: (peer, title, facts) async => notes.add((peer, title, facts)),
      startedTasks: (thread, since) async => [
            {'jobId': 'job-9', 'type': 'download', 'title': 'a file', 'state': 'running'}
          ]);

  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('mesh-delegation-');
    chat = FakeChat();
    running = true;
    notes.clear();
    receiver = makeReceiver(Directory('${dir.path}/receiver'));
    await receiver.attach(chat);
  });
  tearDown(() async {
    await chat.close();
    await receiver.close();
    await dir.delete(recursive: true);
  });

  Future<JsonMap> turn(String id, {String from = 'mac', String text = 'list the library', List? refs}) =>
      receiver.handle('mesh/agent/turn',
          {'delegationId': id, 'text': text, if (refs != null) 'refs': refs}, from);
  Future<JsonMap> wait(String id,
          {String from = 'mac', int since = -1, int seconds = 0}) =>
      receiver.handle('mesh/agent/wait',
          {'delegationId': id, 'since': since, 'waitSeconds': seconds}, from);

  group('the receiving device', () {
    test('opens a conversation that begins with where the task came from', () async {
      final answer = await turn('delegation-0001',
          text: 'Make a list of what is in the library.',
          refs: [
            {'kind': 'work', 'id': 'work-1'}
          ]);
      final thread = answer['threadId'] as String;
      expect(answer['state'], 'inProgress');
      expect(answer['conversationContinued'], false);
      expect(chat.titles[thread], '来自 MacBook 的委托');
      final (_, text) = chat.started.single;
      expect(text, startsWith('来自 MacBook 上的 Nipa 的委托。 [NipaPlay 委托 delegation-0001]\n'));
      expect(text, contains('Make a list of what is in the library.'));
      expect(text, contains('"id":"work-1"'));
      // Its calls are attributed to it, not to the conversation of the person.
      expect(chat.threadOrigins[thread], startsWith('harness_cli:chat:delegate-'));
    });

    test('the person reads where it came from and the task, without the marker', () {
      final message = delegationMessage('delegation-0001', 'MacBook',
          'Make a list.', [
        {'kind': 'work', 'id': 'work-1'}
      ]);
      expect(ChatContext.isFollowup(message), false);
      expect(
          ChatContext.strip(message),
          '来自 MacBook 上的 Nipa 的委托。\n\nMake a list.\n\n'
              '对方带来的引用（原样，未经核对）：\n- {"kind":"work","id":"work-1"}');
      expect(ChatContext.strip(message), isNot(contains('delegation-0001')));
      // The runtime keeps only the first line as a conversation's preview; it
      // still says where the task came from.
      expect(ChatContext.strip(message.split('\n').first), '来自 MacBook 上的 Nipa 的委托。');
      expect(isDelegation(message), true);
      expect(isDelegation('来自 a 上的 Nipa 的委托。 but not marked'), false);
      expect(ChatContext.strip('plain words'), 'plain words');
    });

    test('puts the beginning and the end of a delegation into 动态', () async {
      final first = await turn('delegation-0001', text: 'Make a list.');
      await pumpEventQueue();
      expect(notes.map((n) => n.$2), ['来自 MacBook 的委托']);
      expect(notes.single.$1, 'mac');
      expect(notes.single.$3['task'], 'Make a list.');
      expect(notes.single.$3['threadId'], first['threadId']);
      chat.step(first['threadId'] as String);
      chat.finish(first['threadId'] as String);
      await until(() async => notes.length == 2, 'the end is noted');
      expect(notes.last.$2, '来自 MacBook 的委托已完成');
      expect(notes.last.$3['state'], 'completed');
      expect(notes.last.$3['steps'], 1);
      // A failure and a stop are said the same way, once.
      final second = await turn('delegation-0002');
      chat.finish(second['threadId'] as String, status: 'failed', error: 'boom');
      await until(() async => notes.length == 4, 'the failure is noted');
      expect(notes.last.$2, '来自 MacBook 的委托失败了');
      expect(notes.last.$3['error'], 'boom');
      await wait('delegation-0002');
      await pumpEventQueue();
      expect(notes, hasLength(4));
    });

    test('continues the conversation of the same device while it is idle, and opens another when it is not', () async {
      final first = await turn('delegation-0001');
      chat.finish(first['threadId'] as String);
      await pumpEventQueue();
      final second = await turn('delegation-0002');
      expect(second['threadId'], first['threadId']);
      expect(second['conversationContinued'], true);
      // Someone is speaking in it (or a delegated turn runs there): the next
      // task does not wait behind it.
      final third = await turn('delegation-0003');
      expect(third['threadId'], isNot(first['threadId']));
      expect(third['conversationContinued'], false);
      // Another device has a conversation of its own.
      final other = await turn('delegation-0004', from: 'ipad');
      expect(other['threadId'], isNot(third['threadId']));
      expect(chat.titles[other['threadId']], '来自 iPad 的委托');
    });

    test('says why when Nipa is not running here', () async {
      running = false;
      await expectLater(
          turn('delegation-0001'),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.unavailable)
              .having((f) => f.message, 'message', 'Next chat host is disabled.')));
      expect(chat.started, isEmpty);
    });

    test('takes work only from a device of this account', () async {
      await expectLater(
          turn('delegation-0001', from: 'stranger'),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.unavailable)
              .having((f) => f.message, 'message', contains('of this account'))));
      expect(chat.started, isEmpty);
      // A delegation can be followed or stopped only by the device that made it.
      final mine = await turn('delegation-0002');
      for (final method in ['mesh/agent/wait', 'mesh/agent/interrupt']) {
        await expectLater(
            receiver.handle(method, {'delegationId': 'delegation-0002'}, 'ipad'),
            throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.notFound)));
      }
      expect(chat.interrupted, isEmpty);
      expect(mine['state'], 'inProgress');
    });

    test('a task asked twice starts one turn', () async {
      final first = await turn('delegation-0001');
      final again = await turn('delegation-0001');
      expect(again['repeated'], true);
      expect(again['turnId'], first['turnId']);
      expect(chat.started, hasLength(1));
      await expectLater(turn('delegation-0001', from: 'ipad'),
          throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.conflict)));
    });

    test('reports progress as it happens, then the reply and what she started', () async {
      final first = await turn('delegation-0001');
      final thread = first['threadId'] as String;
      final waiting = wait('delegation-0001', since: first['version'] as int, seconds: 10);
      chat.step(thread);
      var seen = await waiting;
      expect(seen['steps'], 1);
      expect(seen['state'], 'inProgress');
      expect(seen.containsKey('reply'), false);

      final saying = wait('delegation-0001', since: seen['version'] as int, seconds: 10);
      chat.say(thread, '我先看了片库。一共 12 部作品。');
      seen = await saying;
      expect(seen['lastSentence'], '一共 12 部作品');

      final ending = wait('delegation-0001', since: seen['version'] as int, seconds: 10);
      chat.finish(thread);
      final done = await ending;
      expect(done['state'], 'completed');
      expect(done['reply'], '我先看了片库。一共 12 部作品。');
      expect(done['steps'], 1);
      expect((done['startedTasks'] as List).single['jobId'], 'job-9');
    });

    test('an unchanged wait returns when its time is up, still in progress', () async {
      final first = await turn('delegation-0001');
      final watch = Stopwatch()..start();
      final seen = await wait('delegation-0001', since: first['version'] as int, seconds: 1);
      expect(seen['state'], 'inProgress');
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(900));
    });

    test('a failed turn is reported as failed with the host\'s words', () async {
      final first = await turn('delegation-0001');
      chat.finish(first['threadId'] as String, status: 'failed', error: 'model unavailable');
      await pumpEventQueue();
      final done = await wait('delegation-0001');
      expect(done['state'], 'failed');
      expect(done['error'], 'model unavailable');
    });

    test('stopping a delegation stops its turn', () async {
      final first = await turn('delegation-0001');
      final stopped = await receiver.handle(
          'mesh/agent/interrupt', {'delegationId': 'delegation-0001'}, 'mac');
      expect(chat.interrupted, [first['threadId']]);
      await pumpEventQueue();
      expect((await wait('delegation-0001'))['state'], 'interrupted');
      expect(stopped['delegationId'], 'delegation-0001');
    });

    test('a turn the host can no longer end is interrupted, and waiters are told at once', () async {
      final first = await turn('delegation-0001');
      final waiting = wait('delegation-0001', since: first['version'] as int, seconds: 30);
      running = false;
      chat.available = false;
      await receiver.attach(null);
      final seen = await waiting.timeout(const Duration(seconds: 5));
      expect(seen['state'], 'interrupted');
      expect(seen['error'], contains('stopped'));
    });

    test('after a restart a finished delegation is still there and an unfinished one is interrupted', () async {
      final done = await turn('delegation-0001');
      chat.say(done['threadId'] as String, 'All done.');
      chat.finish(done['threadId'] as String);
      await until(() async => (await wait('delegation-0001'))['state'] == 'completed',
          'the first ended');
      // Persisted after the reply is read.
      await pumpEventQueue();
      final open = await turn('delegation-0002');
      expect(open['state'], 'inProgress');

      final again = makeReceiver(Directory('${dir.path}/receiver'));
      await again.attach(chat);
      final finished = await again.handle(
          'mesh/agent/wait', {'delegationId': 'delegation-0001'}, 'mac');
      expect(finished['state'], 'completed');
      expect(finished['reply'], 'All done.');
      final lost = await again.handle(
          'mesh/agent/wait', {'delegationId': 'delegation-0002'}, 'mac');
      expect(lost['state'], 'interrupted');
      // The conversation made for the device is attributed to itself again.
      expect(chat.threadOrigins[done['threadId']], startsWith('harness_cli:chat:delegate-'));
    });

    test('a turn the host refuses leaves nothing behind', () async {
      chat.refuse = 'runtime busy';
      await expectLater(turn('delegation-0001'),
          throwsA(isA<Failure>().having((f) => f.message, 'message', contains('runtime busy'))));
      chat.refuse = null;
      final retried = await turn('delegation-0001');
      expect(retried['repeated'], isNull);
      expect(chat.started, hasLength(1));
    });

    test('rejects a malformed request', () async {
      await expectLater(
          receiver.handle('mesh/agent/turn', {'delegationId': 'x', 'text': 'hi'}, 'mac'),
          throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.invalidInput)));
      await expectLater(turn('delegation-0001', text: '  '),
          throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.invalidInput)));
    });
  });

  group('the sending device', () {
    late Directory root;
    late SqliteJobStore store;
    late TaskEngine engine;
    late Followups followups;
    late MeshDelegations sender;
    var reachable = true;
    final calls = <String>[];

    setUp(() async {
      root = Directory('${dir.path}/sender');
      await root.create();
      store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
      reachable = true;
      calls.clear();
      sender = MeshDelegations(
          call: (peer, method, params) async {
            calls.add(method);
            if (!reachable && method != 'mesh/agent/turn') {
              throw const Failure(FailureCode.unavailable,
                  'No authenticated direct route to Mesh device.',
                  retryable: true);
            }
            return receiver.handle(method, params, 'mac');
          },
          devices: () => [
                {'deviceId': 'mac', 'name': 'MacBook', 'revoked': false},
                {'deviceId': 'workstation', 'name': '工作站', 'revoked': false},
                {'deviceId': 'ipad', 'name': 'iPad', 'revoked': false},
                {'deviceId': 'gone', 'name': 'Old', 'revoked': true},
                {'deviceId': 'twin-1', 'name': 'Twin', 'revoked': false},
                {'deviceId': 'twin-2', 'name': 'Twin', 'revoked': false},
              ],
          selfDeviceId: () => 'mac',
          retryBase: const Duration(milliseconds: 40));
      engine = TaskEngine(
          store: store, ownerDeviceId: 'mac', executors: [sender]);
      await engine.start();
      followups = Followups(store.database, engine, HeadlessRepository(root.path));
      sender
        ..engine = engine
        ..followups = followups;
    });
    tearDown(() async {
      await followups.close();
      await engine.close();
    });

    final invocation = Invocation(origin: 'harness_cli');

    Future<Job> job(String id) => engine.get(id);

    test('returns a local background task at once and follows the other turn to its end', () async {
      final started = await sender.delegate({
        'deviceId': 'workstation',
        'task': 'List what is in your library as a table.',
        'references': [
          {'kind': 'work', 'id': 'work-1'}
        ]
      }, invocation);
      final id = started['jobId'] as String;
      expect(started['deviceName'], '工作站');
      expect((started['remote'] as Map)['conversationContinued'], false);
      final thread = (started['remote'] as Map)['threadId'] as String;
      expect((await job(id)).type, 'agent.delegate');
      expect((await job(id)).input['task'], contains('List what is in your library'));

      // Progress: the other turn's state, steps and last sentence.
      chat.step(thread);
      chat.say(thread, '正在整理。已经读到 12 部。');
      await until(() async {
        final now = await job(id);
        return now.details['steps'] == 1 && now.details['lastSentence'] == '已经读到 12 部';
      }, 'progress reached the task');
      expect((await job(id)).details['remoteState'], 'inProgress');
      expect((await job(id)).details['currentActivity'], '已经读到 12 部');
      expect((await job(id)).state.isTerminal, false);

      // The end: her final reply is the receipt.
      chat.say(thread, '清单：A、B、C。');
      chat.finish(thread);
      await until(() async => (await job(id)).state == JobState.succeeded,
          'the task ended: ${jsonEncode((await job(id)).toJson())}');
      final ended = await job(id);
      final details = ended.receipt!.details;
      expect(details['summary'], contains('正在整理。已经读到 12 部。\n清单：A、B、C。'));
      expect(details['turnStatus'], 'completed');
      expect(details['deviceName'], '工作站');
      expect(details['threadId'], thread);
      expect((details['startedTasks'] as List).single['jobId'], 'job-9');

      // The end returns to the conversation that delegated, as a followup.
      await followups.sweep();
      final rows = (await followups.list())
          .where((row) => (row['condition'] as Map)['jobId'] == id)
          .toList();
      expect(rows, hasLength(1));
      expect(rows.single['instruction'], contains('工作站'));
      final trigger = jsonEncode(rows.single['trigger']);
      expect(trigger, contains('清单：A、B、C。'));
    });

    test('fails at once, in the other device\'s words, when Nipa is not running there', () async {
      running = false;
      await expectLater(
          sender.delegate({'deviceId': 'workstation', 'task': 'anything'}, invocation),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.unavailable)
              .having((f) => f.message, 'message',
                  allOf(contains('工作站'), contains('Next chat host is disabled.')))));
      expect(await engine.list(type: 'agent.delegate'), isEmpty);
    });

    test('names its devices by id or by a name that is theirs alone', () async {
      Future<void> refused(String wanted, FailureCode code, [String? words]) =>
          expectLater(
              sender.delegate({'deviceId': wanted, 'task': 'x'}, invocation),
              throwsA(isA<Failure>()
                  .having((f) => f.code, 'code', code)
                  .having((f) => f.message, 'message', contains(words ?? ''))));
      await refused('nobody', FailureCode.notFound);
      await refused('gone', FailureCode.notFound);
      await refused('mac', FailureCode.invalidInput, 'itself');
      await refused('Twin', FailureCode.invalidInput, 'twin-1');
      final byName = await sender.delegate({'deviceId': '工作站', 'task': 'x'}, invocation);
      expect(byName['deviceId'], 'workstation');
    });

    test('cancelling the task stops the other device\'s turn', () async {
      final started = await sender.delegate(
          {'deviceId': 'workstation', 'task': 'a long task'}, invocation);
      final id = started['jobId'] as String;
      final thread = (started['remote'] as Map)['threadId'] as String;
      await until(() async => calls.contains('mesh/agent/wait'), 'following');
      await engine.cancel(id);
      await until(() async => (await job(id)).state == JobState.cancelled, 'cancelled');
      expect(chat.interrupted, [thread]);
      final details = (await job(id)).receipt!.details;
      expect(details['remoteStopped'], true);
      expect(details['turnStatus'], 'interrupted');
    });

    test('cancelling when the other device cannot be reached says so', () async {
      final started = await sender.delegate(
          {'deviceId': 'workstation', 'task': 'a long task'}, invocation);
      final id = started['jobId'] as String;
      await until(() async => calls.contains('mesh/agent/wait'), 'following');
      reachable = false;
      await engine.cancel(id);
      await until(() async => (await job(id)).state == JobState.cancelled, 'cancelled');
      final details = (await job(id)).receipt!.details;
      expect(details['remoteStopped'], false);
      expect(details['remoteUnreached'], contains('No authenticated direct route'));
      expect(chat.interrupted, isEmpty);
    });

    test('an unreachable device is waited for, and the task goes on when it is back', () async {
      final started = await sender.delegate(
          {'deviceId': 'workstation', 'task': 'a long task'}, invocation);
      final id = started['jobId'] as String;
      final thread = (started['remote'] as Map)['threadId'] as String;
      await until(() async => calls.contains('mesh/agent/wait'), 'following');
      reachable = false;
      chat.step(thread);
      await until(() async {
        final now = await job(id);
        return now.state == JobState.waitingRetry &&
            now.details['remoteState'] == 'unreachable';
      }, 'waiting for the device');
      reachable = true;
      await until(() async => (await job(id)).details['steps'] == 1, 'following again');
      chat.finish(thread);
      await until(() async => (await job(id)).state == JobState.succeeded,
          'the task ended: ${jsonEncode((await job(id)).toJson())}');
    });

    test('a delegation the other device does not know ends the task as failed', () async {
      final started = await sender.delegate(
          {'deviceId': 'workstation', 'task': 'a long task'}, invocation);
      final id = started['jobId'] as String;
      // The other device lost its records (a new data directory).
      await File('${dir.path}/receiver/mesh-delegations.json').delete().catchError((_) => File(''));
      receiver = makeReceiver(Directory('${dir.path}/receiver-new'));
      await receiver.attach(chat);
      await until(() async => (await job(id)).state == JobState.failed, 'the task failed');
      expect((await job(id)).error!.code, FailureCode.notFound);
    });

    test('a turn that ends badly ends the task as failed, with what it did', () async {
      final started = await sender.delegate(
          {'deviceId': 'workstation', 'task': 'a long task'}, invocation);
      final id = started['jobId'] as String;
      final thread = (started['remote'] as Map)['threadId'] as String;
      chat.step(thread);
      chat.finish(thread, status: 'failed', error: 'provider error');
      await until(() async => (await job(id)).state == JobState.failed, 'the task failed');
      final details = (await job(id)).receipt!.details;
      expect(details['turnStatus'], 'failed');
      expect(details['remoteError'], 'provider error');
      expect(details['steps'], 1);
    });
  });
}
