import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Invocation;
import 'package:nipaplay/next/mesh/chat_guest_host.dart';
import 'package:nipaplay/next/mesh/nipa_peers.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/conversation/mesh_chat_port.dart';
import 'package:nipaplay/next/ui/conversation/nipa_chat.dart';
import 'package:nipaplay/next/ui/widgets/nipa_avatar.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

import 'mesh_delegation_support.dart';

const _devices = {'ipad': 'iPad', 'phone': 'Phone'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeChat chat;
  late ChatGuests guests;
  var running = true;
  final notes = <(String, String, JsonMap)>[];

  ChatGuests make(Directory root) => ChatGuests(
      root: root,
      chat: () => running && chat.available ? chat : null,
      unavailableReason: () => 'Next chat host is disabled.',
      deviceName: (id) => _devices[id],
      record: (peer, title, facts) async => notes.add((peer, title, facts)));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mesh-chat-guest-');
    chat = FakeChat();
    running = true;
    notes.clear();
    guests = make(Directory('${dir.path}/host'));
    await guests.attach(chat);
  });
  tearDown(() async {
    await guests.close();
    await chat.close();
    await dir.delete(recursive: true);
  });

  Future<JsonMap> call(String method,
          [JsonMap params = const {}, String from = 'ipad']) =>
      guests.handle(method, params, from);

  group('the device that serves a guest', () {
    test('opens a conversation named for the guest, attributed to itself',
        () async {
      final opened = await call('mesh/chat/open');
      final thread = opened['threadId'] as String;
      expect(chat.titles[thread], '来自 iPad 的对话');
      expect(chat.threadOrigins[thread],
          startsWith('harness_cli:chat:delegate-ipad-'));
      expect(notes.single.$2, 'iPad 开了一段对话');
      // The main one is the same again, another is a new one.
      expect((await call('mesh/chat/open'))['threadId'], thread);
      final another = await call('mesh/chat/open', {'new': true});
      expect(another['threadId'], isNot(thread));
      final listed = await call('mesh/chat/threads');
      expect(listed['mainThreadId'], thread);
    });

    test(
        'each sentence carries where the guest said it, as the guest reported it',
        () async {
      final thread = (await call('mesh/chat/open'))['threadId'] as String;
      await call('mesh/chat/turn', {
        'threadId': thread,
        'text': '把弹幕关掉',
        'context': {
          'page': '播放',
          'nowPlaying': {'work': '寻龙记', 'episode': '第 3 集', 'paused': false},
          'progress': {'positionMs': 754000, 'durationMs': 1420000},
        },
      });
      final (_, text) = chat.started.single;
      expect(text, startsWith('把弹幕关掉\n\n[NipaPlay 界面] '));
      expect(text, contains('「iPad」的对话面板里说的'));
      expect(text, contains('页面：播放'));
      expect(text, contains('在播放《寻龙记》 第 3 集'));
      expect(text, contains('位置 12:34 / 23:40'));
      expect(text, contains('设备 ID：ipad'));
      // Read back, the person sees what was said and which device said it.
      expect(ChatContext.strip(text), '把弹幕关掉');
      expect(ChatContext.guestOf(text), 'iPad');
      expect(ChatContext.guestOf('plain'), isNull);
    });

    test('says one more thing into a running turn, and stops it', () async {
      final thread = (await call('mesh/chat/open'))['threadId'] as String;
      await expectLater(
          call('mesh/chat/steer', {'threadId': thread, 'text': 'x'}),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.conflict)));
      await call('mesh/chat/turn', {'threadId': thread, 'text': 'a'});
      await expectLater(
          call('mesh/chat/turn', {'threadId': thread, 'text': 'b'}),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.conflict)));
      await call('mesh/chat/steer', {'threadId': thread, 'text': 'and this'});
      expect(chat.steered.single.$1, thread);
      expect(chat.steered.single.$2, startsWith('and this\n\n[NipaPlay 界面]'));
      expect(ChatContext.guestOf(chat.steered.single.$2), 'iPad');
      await call('mesh/chat/interrupt', {'threadId': thread});
      expect(chat.interrupted, [thread]);
    });

    test(
        'account devices share host and guest conversations; strangers cannot read or act',
        () async {
      final mine = (await call('mesh/chat/open'))['threadId'] as String;
      await call('mesh/chat/open', {}, 'phone');
      chat.threads['host-main'] = [];
      chat.mainThreadId = 'host-main';
      expect(
          (await call('mesh/chat/read', {'threadId': mine}, 'phone'))['thread'],
          isNotNull);
      await call(
          'mesh/chat/turn', {'threadId': 'host-main', 'text': 'x'}, 'phone');
      expect(chat.started.single.$1, 'host-main');
      expect(ChatContext.guestOf(chat.started.single.$2), 'Phone');
      await expectLater(
          call('mesh/chat/open', {}, 'stranger'),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.unavailable)));
      expect(((await call('mesh/chat/threads', {}, 'phone'))['data'] as List),
          hasLength(3));
      final listed = await call('mesh/chat/threads');
      expect(listed['mainThreadId'], 'host-main');
      expect((listed['data'] as List).last['busy'], true);
      for (final method in chatGuestMethods) {
        await expectLater(
            call(method, {}, 'stranger'), throwsA(isA<Failure>()));
      }
    });

    test('says why when Nipa is not running here', () async {
      running = false;
      await expectLater(
          call('mesh/chat/open'),
          throwsA(isA<Failure>().having(
              (f) => f.message, 'message', 'Next chat host is disabled.')));
    });

    test(
        'shared lists preserve pagination and conversations beyond the old fifty limit',
        () async {
      for (var i = 0; i < 105; i++) {
        chat.threads['local-$i-thread'] = [];
      }
      final first = await call('mesh/chat/threads');
      expect(first['data'], hasLength(100));
      final second =
          await call('mesh/chat/threads', {'cursor': first['nextCursor']});
      expect(second['data'], hasLength(5));
      expect(second['nextCursor'], isNull);
      final oldest = (await call('mesh/chat/open'))['threadId'] as String;
      for (var i = 0; i < 51; i++) {
        await call('mesh/chat/open', {'new': true});
      }
      expect((await call('mesh/chat/read', {'threadId': oldest}))['thread'],
          isNotNull);
      final saved =
          await File('${dir.path}/host/mesh-chat-guests.json').readAsString();
      expect(saved, contains(oldest));
    });

    test('reads the conversation back with its turns', () async {
      final thread = (await call('mesh/chat/open'))['threadId'] as String;
      await call('mesh/chat/turn', {'threadId': thread, 'text': 'hello'});
      chat.say(thread, 'hi');
      final read = await call('mesh/chat/read', {'threadId': thread});
      expect(read['busy'], true);
      expect(((read['thread'] as Map)['turns'] as List), hasLength(1));
    });

    test('a conversation outlives this host and is still the guest\'s',
        () async {
      final thread = (await call('mesh/chat/open'))['threadId'] as String;
      final again = make(Directory('${dir.path}/host'));
      final fresh = FakeChat()..threads[thread] = [];
      await again.attach(fresh);
      expect(fresh.threadOrigins[thread],
          startsWith('harness_cli:chat:delegate-ipad-'));
      expect((await again.handle('mesh/chat/open', {}, 'ipad'))['threadId'],
          thread);
      await again.close();
      await fresh.close();
    });
  });

  group('what happens in a guest\'s conversation', () {
    test('is told by one long wait that ends when something happens', () async {
      final thread = (await call('mesh/chat/open'))['threadId'] as String;
      await call('mesh/chat/turn', {'threadId': thread, 'text': 'hello'});
      final first = await call('mesh/chat/events', {});
      final sequence = first['sequence'] as int;
      final waiting = call('mesh/chat/events',
          {'after': sequence, 'epoch': first['epoch'], 'waitSeconds': 30});
      var done = false;
      unawaited(waiting.then((_) => done = true));
      await pumpEventQueue();
      expect(done, false);
      chat.say(thread, 'hi');
      final answer = await waiting.timeout(const Duration(seconds: 5));
      final events = (answer['events'] as List).cast<Map>();
      expect(events, isNotEmpty);
      expect(answer['sequence'], greaterThan(sequence));
      // From where it was, nothing new: the wait runs out empty.
      final empty = await call('mesh/chat/events', {
        'after': answer['sequence'],
        'epoch': answer['epoch'],
        'waitSeconds': 0
      });
      expect(empty['events'], isEmpty);
    });

    test('host and other guests receive the same live conversation events',
        () async {
      final mine = (await call('mesh/chat/open'))['threadId'] as String;
      await call('mesh/chat/open', {}, 'phone');
      await call('mesh/chat/turn', {'threadId': mine, 'text': 'hello'});
      final base = await call('mesh/chat/events', {}, 'phone');
      chat.say(mine, 'for the iPad');
      final phone = await call('mesh/chat/events',
          {'after': base['sequence'], 'epoch': base['epoch']}, 'phone');
      expect(phone['events'], hasLength(1));
      final ipad =
          await call('mesh/chat/events', {'after': 0, 'epoch': guests.epoch});
      expect((ipad['events'] as List).last, (phone['events'] as List).single);
    });

    test(
        'a guest that missed more than was kept, or a host that started again, is told to read again',
        () async {
      final thread = (await call('mesh/chat/open'))['threadId'] as String;
      final base = await call('mesh/chat/events', {});
      for (var i = 0; i < chatEventsKept + 5; i++) {
        chat.step(thread);
      }
      await pumpEventQueue();
      final lost = await call('mesh/chat/events',
          {'after': base['sequence'], 'epoch': base['epoch']});
      expect(lost['reset'], true);
      final other =
          await call('mesh/chat/events', {'after': 3, 'epoch': 'an-older-run'});
      expect(other['reset'], true);
    });

    test('any account device can read a pending question and answer it',
        () async {
      final thread = (await call('mesh/chat/open'))['threadId'] as String;
      await call('mesh/chat/open', {}, 'phone');
      chat.ask(thread, 7);
      await pumpEventQueue();
      final read = await call('mesh/chat/read', {'threadId': thread}, 'phone');
      expect(read['questions'], hasLength(1));
      await call(
          'mesh/chat/answer',
          {
            'requestId': 7,
            'answers': {
              'q': ['yes']
            }
          },
          'phone');
      expect(chat.answered.single.$2, {
        'q': ['yes']
      });
      final events =
          await call('mesh/chat/events', {'after': 0, 'epoch': guests.epoch});
      expect(
          (events['events'] as List).any((e) => e['question'] == true), true);
      expect((events['events'] as List).last['message']['method'],
          'host/questionAnswered');
      expect((await call('mesh/chat/read', {'threadId': thread}))['questions'],
          isEmpty);
    });
  });

  group('a request that did not leave, and one that may have arrived', () {
    test(
        'the first says it was not sent and why, the second says it is unknown',
        () {
      final notSent = meshNotDelivered(
          'ipad', meshConnectCause('connect: connect timeout'));
      expect(notSent.details['reason'], 'not_delivered');
      expect(notSent.details['cause'], 'connect timeout');
      expect(notSent.retryable, true);
      expect(notSent.message, startsWith('not_delivered:'));
      final unknown = meshOutcomeUnknown('ipad', 'tools/call');
      expect(unknown.details['reason'], 'outcome_unknown');
      expect(unknown.retryable, false);
      expect(meshOutcomeUnknown('ipad', 'mesh/describe').retryable, true);
      expect(unknown.message, isNot(contains('route')));
    });
  });

  group('the conversation panel of a device that cannot run Nipa', () {
    late NipaPeers peers;
    late MeshChatPort port;
    late Future<JsonMap> Function(String, String, JsonMap) rpc;
    final changed = StreamController<void>.broadcast();
    var gone = false;
    var agents = <JsonMap>[];

    setUp(() async {
      gone = false;
      agents = [
        {
          'deviceId': 'mac',
          'name': 'MacBook',
          'online': true,
          'agent': {'runs': true, 'busy': false}
        },
        {
          'deviceId': 'nas',
          'name': 'NAS',
          'online': true,
          'agent': {'runs': false, 'reason': 'x'}
        },
      ];
      peers = NipaPeers(
          root: Directory('${dir.path}/ipad')..createSync(),
          devices: () async => agents,
          hostChanges: changed.stream);
      rpc = (peer, method, params) async {
        if (gone) throw meshNotDelivered(peer, 'connect timeout');
        return guests.handle(method, params, 'ipad');
      };
      port = MeshChatPort(
          call: (peer, method, params) => rpc(peer, method, params),
          hostChanges: changed.stream,
          peers: peers,
          retry: const Duration(milliseconds: 100),
          playback: () => {
                'nowPlaying': {'work': 'W', 'paused': true}
              })
        ..page = () => '播放';
    });
    tearDown(() async {
      port.dispose();
      await peers.close();
    });

    test(
        'lists the devices whose Nipa runs, and keeps the choice on the device',
        () async {
      await peers.refresh();
      expect(peers.peers.map((p) => p.id), ['mac']);
      expect(peers.chosen, isNull);
      await peers.choose('mac');
      expect(peers.chosenName, 'MacBook');
      final again = NipaPeers(
          root: Directory('${dir.path}/ipad'),
          devices: () async => agents,
          hostChanges: changed.stream);
      await again.load();
      expect(again.chosen, 'mac');
      expect(again.chosenName, 'MacBook');
      // The chosen one stays listed when Nipa stops there.
      agents[0]['agent'] = {'runs': false};
      await again.refresh();
      expect(again.peers.single.usable, false);
      await again.choose(null);
      expect(again.chosen, isNull);
      await again.close();
    });

    test('with no device chosen it says to choose one', () async {
      await peers.load();
      expect(port.available, false);
      expect(await port.unavailableReason(), '选一台设备的梨花。在设置的“梨花”里选。');
      expect(port.note, isNull);
      await expectLater(port.mainThread(), throwsA(isA<ChatUnavailable>()));
    });

    test('with the chosen device away it says so by name', () async {
      await peers.refresh();
      gone = true;
      await peers.choose('mac');
      expect(await port.unavailableReason(), 'MacBook 现在不在。');
      expect(port.available, false);
      expect(port.note, 'MacBook 现在不在。');
      await expectLater(
          port.startTurn('x', 'hello'),
          throwsA(isA<ChatUnavailable>()
              .having((e) => e.message, 'message', 'MacBook 现在不在。')));
    });

    test(
        'speaks in a conversation on the chosen device and hears what happens there',
        () async {
      await peers.refresh();
      await peers.choose('mac');
      expect(await port.unavailableReason(), isNull);
      expect(port.available, true);
      final thread = (await port.mainThread())!;
      final seen = <String>[];
      final sub = port.display
          .where((e) => e['method'] == 'item/completed')
          .listen((e) =>
              seen.add('${e['method']}:${(e['params'] as Map)['threadId']}'));
      final started = await port.startTurn(thread, '关掉弹幕');
      expect(started!['turn'], isNotNull);
      expect(chat.started.single.$2, contains('页面：播放'));
      expect(chat.started.single.$2, contains('在播放《W》'));
      expect(port.busyOn(thread), true);
      chat.say(thread, '好了');
      await until(() async => seen.isNotEmpty, 'the reply arrives');
      expect(seen.single, 'item/completed:$thread');
      chat.finish(thread);
      await until(() async => !port.busyOn(thread), 'the turn ends');
      final history = await port.readThread(thread);
      expect((history['turns'] as List), hasLength(1));
      await sub.cancel();
    });

    test('is back when the device is', () async {
      await peers.refresh();
      gone = true;
      await peers.choose('mac');
      await port.unavailableReason();
      expect(port.available, false);
      gone = false;
      changed.add(null);
      await until(() async => port.available, 'the device is back');
      expect(port.note, isNull);
    });

    test('two conversations start immediately and the same conversation steers',
        () async {
      await peers.refresh();
      await peers.choose('mac');
      await port.unavailableReason();
      final ui = NipaChat(port: port, data: _ChatData());
      addTearDown(ui.dispose);
      await ui.refreshSessions();
      await ui.say('第一段');
      final first = ui.thread!;
      expect(port.busyOn(first), true);
      ui.startNew();
      await ui.say('第二段');
      final second = ui.thread!;
      expect(second, isNot(first));
      expect(chat.started, hasLength(2));
      expect(port.busyOn(first), true);
      expect(port.busyOn(second), true);
      expect(ui.live!.queued, false);
      expect(ui.doing, '正在进行 2 段对话');
      await ui.say('补充');
      expect(chat.started, hasLength(2));
      expect(chat.steered.single.$1, second);
      expect(chat.steered.single.$2, contains('页面：播放'));
      await ui.stop();
      await until(() async => !port.busyOn(second), 'second stopped');
      expect(port.busy, true);
      expect(ui.mood, isNot(NipaMood.idle));
      chat.finish(first);
      await until(() async => !port.busy, 'all finished');
      expect(ui.mood, NipaMood.idle);
    });

    test(
        'the session menu receives additions, names and host replies by long wait',
        () async {
      chat.mainThreadId = 'host-main';
      chat.threads['host-main'] = [];
      await peers.refresh();
      await peers.choose('mac');
      await port.unavailableReason();
      final ui = NipaChat(port: port, data: _ChatData());
      addTearDown(ui.dispose);
      await ui.refreshSessions();
      await ui.select('host-main');
      await chat.startThreadTurn('host-main', '宿主说的');
      chat.publish({
        'method': 'turn/started',
        'params': {
          'threadId': 'host-main',
          'turn': {
            'id': chat.threads['host-main']!.single['id'],
            'status': 'inProgress'
          }
        }
      });
      chat.say('host-main', '实时回复');
      await until(() async => ui.turns.any((t) => t.lastWords == '实时回复'),
          'reply is pushed');
      await ui.say('手机接着说');
      expect(chat.steered.last.$1, 'host-main');
      final opened = await call('mesh/chat/open', {'new': true}, 'phone');
      final added = opened['threadId'] as String;
      await until(() async => ui.sessions.any((s) => s.id == added),
          'list addition is pushed');
      chat.rename(added, '周末看片');
      await until(
          () async =>
              ui.sessions.any((s) => s.id == added && s.title == '周末看片'),
          'name is pushed');
    });

    test(
        'new guests fall back to the old protocol without extra RPCs or fields',
        () async {
      final methods = <String>[];
      final owned = <String>{};
      chat.threads['host-only-thread'] = [];
      rpc = (peer, method, params) async {
        methods.add(method);
        if (method == 'mesh/chat/state') {
          final state = await guests.handle(method, params, 'ipad');
          return {...state}..remove('sharedThreads');
        }
        if (method == 'mesh/chat/open') {
          final opened = await guests.handle(method, params, 'ipad');
          owned.add(opened['threadId'] as String);
          return opened;
        }
        if (method == 'mesh/chat/threads') {
          expect(params, isEmpty);
          final listed = await guests.handle(method, params, 'ipad');
          return {
            ...listed,
            'data': (listed['data'] as List)
                .where((t) => owned.contains(t['id']))
                .toList()
          }
            ..remove('sharedThreads')
            ..remove('nextCursor');
        }
        if (method == 'mesh/chat/read') {
          final result = await guests.handle(method, params, 'ipad');
          return {...result}..remove('questions');
        }
        return guests.handle(method, params, 'ipad');
      };
      await peers.refresh();
      await peers.choose('mac');
      expect(await port.unavailableReason(), isNull);
      final thread = (await port.mainThread())!;
      await port.startTurn(thread, '旧协议');
      await port.readThread(thread);
      final listed = await port.listThreads(cursor: 'ignored-by-old-host');
      expect((listed['data'] as List).map((t) => t['id']), [thread]);
      expect(methods.toSet().difference(chatGuestMethods), isEmpty);
    });

    test('Nipa not running there says so, not that the device is away',
        () async {
      await peers.refresh();
      running = false;
      await peers.choose('mac');
      expect(await port.unavailableReason(), 'MacBook 上的梨花现在不能用。');
    });
  });
}

final class _ChatData implements NextUiData {
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Stream<List<UiTask>> tasks() => const Stream.empty();
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
