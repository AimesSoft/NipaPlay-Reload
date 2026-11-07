import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/conversation/nipa_chat.dart';
import 'package:nipaplay/next/ui/widgets/nipa_avatar.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

void main() {
  test(
      'local conversations run together; finishing one keeps the avatar active',
      () async {
    final port = _Port();
    final chat = NipaChat(port: port, data: _Data());
    addTearDown(() {
      chat.dispose();
      port.dispose();
    });
    await chat.refreshSessions();
    await chat.say('A');
    final first = chat.thread!;
    chat.startNew();
    await chat.say('B');
    final second = chat.thread!;
    expect(port.started, [first, second]);
    expect(chat.live!.queued, false);
    expect(chat.doing, '正在进行 2 段对话');
    await chat.say('B 补充');
    expect(port.steered, [second]);
    expect(port.started, hasLength(2));
    port.finish(second);
    await pumpEventQueue();
    expect(chat.mood, isNot(NipaMood.idle));
    port.finish(first);
    await pumpEventQueue();
    expect(chat.mood, NipaMood.idle);
  });

  test(
      'a delayed thread is resumed by a push and can be cancelled without polling',
      () async {
    final port = _Port()..deferThread = true;
    final chat = NipaChat(port: port, data: _Data());
    addTearDown(() {
      chat.dispose();
      port.dispose();
    });
    await chat.refreshSessions();
    chat.startNew();
    final sending = chat.say('等宿主准备');
    await pumpEventQueue();
    expect(chat.live!.queued, true);
    expect(port.opens, 1);
    port.deferThread = false;
    port.emit({'method': 'host/ready', 'params': {}});
    await sending;
    expect(port.opens, 2);
    expect(port.started, hasLength(1));
    chat.startNew();
    port.deferThread = true;
    final cancelled = chat.say('取消');
    await pumpEventQueue();
    await chat.stop();
    await cancelled;
    expect(port.started, hasLength(1));
  });

  test('the session menu consumes every page and refreshes a pushed title',
      () async {
    final port = _Port()
      ..rows = [
        for (var i = 0; i < 105; i++) {'id': 'thread-$i', 'preview': '问题 $i'}
      ];
    final chat = NipaChat(port: port, data: _Data());
    addTearDown(() {
      chat.dispose();
      port.dispose();
    });
    await chat.refreshSessions();
    expect(chat.sessions, hasLength(105));
    port.rows.first['name'] = '重新命名';
    port.emit({
      'method': 'thread/name/updated',
      'params': {'threadId': 'thread-0'}
    });
    await pumpEventQueue();
    expect(chat.sessions.firstWhere((s) => s.id == 'thread-0').title, '重新命名');
  });

  test(
      'opening while a background turn runs restores global activity from a snapshot',
      () async {
    final port = _Port()
      ..rows = [
        {
          'id': 'background',
          'busy': true,
          'turnId': 'running',
          'status': 'inProgress'
        }
      ];
    final chat = NipaChat(port: port, data: _Data());
    addTearDown(() {
      chat.dispose();
      port.dispose();
    });
    await chat.refreshSessions();
    expect(chat.mood, NipaMood.thinking);
    port.rows.clear();
    port.emit({
      'method': 'turn/completed',
      'params': {
        'threadId': 'background',
        'turn': {'id': 'running', 'status': 'completed'}
      }
    });
    await pumpEventQueue();
    expect(chat.mood, NipaMood.idle);
  });
}

final class _Port implements ChatPort {
  final _events = StreamController<ChatEvent>.broadcast();
  final active = <String>{};
  final started = <String>[];
  final steered = <String>[];
  List<Map<String, Object?>> rows = [];
  bool deferThread = false;
  int opens = 0;
  @override
  bool get available => true;
  @override
  bool get busy => active.isNotEmpty;
  @override
  bool busyOn(String threadId) => active.contains(threadId);
  @override
  Stream<ChatEvent> get display => _events.stream;
  @override
  Stream<ChatEvent> get questions => const Stream.empty();
  void emit(ChatEvent event) => _events.add(event);
  @override
  Future<String?> unavailableReason() async => null;
  @override
  Future<String?> mainThread() async => 'main-thread';
  @override
  Future<String?> newThread() async {
    opens++;
    return deferThread ? null : 'new-thread-$opens';
  }

  @override
  Future<String?> switchThread(String threadId) async => threadId;
  @override
  Future<ChatEvent> listThreads({String? cursor}) async {
    final start = int.parse(cursor ?? '0');
    return {
      'data': rows.skip(start).take(40).toList(),
      'nextCursor': start + 40 < rows.length ? '${start + 40}' : null
    };
  }

  @override
  Future<ChatEvent> readThread(String threadId) async => {'turns': []};
  @override
  Future<ChatEvent?> startTurn(String threadId, String text) async {
    started.add(threadId);
    active.add(threadId);
    final turn = {'id': 'turn-$threadId', 'status': 'inProgress'};
    emit({
      'method': 'turn/started',
      'params': {'threadId': threadId, 'turn': turn}
    });
    return {'turn': turn};
  }

  void finish(String threadId) {
    active.remove(threadId);
    emit({
      'method': 'turn/completed',
      'params': {
        'threadId': threadId,
        'turn': {'id': 'turn-$threadId', 'status': 'completed'}
      }
    });
  }

  @override
  Future<void> steer(String text, {String? threadId}) async =>
      steered.add(threadId!);
  @override
  Future<void> interrupt({String? threadId}) async => finish(threadId!);
  @override
  Future<void> answer(
      Object requestId, Map<String, List<String>> answers) async {}
  @override
  void dispose() => _events.close();
}

final class _Data implements NextUiData {
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
