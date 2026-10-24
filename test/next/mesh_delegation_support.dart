import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/delegation_chat.dart';
import 'package:nipaplay/next/chat/liveness.dart';

/// A conversation host that does what the real one reports and nothing else:
/// threads, turns, and the wire events a turn produces.
final class FakeChat implements DelegationChat {
  @override
  bool available = true;
  @override
  String? model = 'fixture-model', provider = 'fixture';
  @override
  final threadOrigins = <String, String>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  final busy = <String>{};
  final threads = <String, List<Map<String, dynamic>>>{};
  final titles = <String, String>{};
  final started = <(String, String)>[];
  final interrupted = <String>[];
  final _liveness = <String, ChatLiveness>{};
  String? refuse;
  int _n = 0;

  @override
  bool busyFor(String threadId) => busy.contains(threadId);
  @override
  ChatLiveness livenessFor(String id) =>
      _liveness.putIfAbsent(id, ChatLiveness.new);

  @override
  Future<String> delegationThread(String token, String title) async {
    final id = 'thread-${++_n}';
    threads[id] = [];
    titles[id] = title;
    threadOrigins[id] = 'harness_cli:chat:delegate-$token';
    return id;
  }

  @override
  Future<Map<String, dynamic>> startThreadTurn(String id, String text) async {
    if (refuse != null) throw StateError(refuse!);
    busy.add(id);
    final turn = 'turn-${++_n}';
    started.add((id, text));
    threads[id]!.add({
      'id': turn,
      'status': 'inProgress',
      'items': [
        {
          'type': 'userMessage',
          'content': [
            {'type': 'text', 'text': text}
          ]
        }
      ],
    });
    return {
      'turn': {'id': turn, 'status': 'inProgress'}
    };
  }

  @override
  Future<Map<String, dynamic>> readThread(String id,
      {bool withProcess = true}) async {
    final turns = threads[id];
    if (turns == null) throw StateError('No such thread.');
    return {'id': id, 'turns': turns};
  }

  @override
  Future<Map<String, dynamic>> interrupt({String? onThread}) async {
    interrupted.add(onThread!);
    finish(onThread, status: 'interrupted');
    return {};
  }

  @override
  Future<int?> conversationCount() async => threads.length;

  void step(String thread) => _events.add({
        'method': 'item/completed',
        'params': {
          'threadId': thread,
          'item': {'type': 'commandExecution', 'command': 'ls'}
        }
      });

  void say(String thread, String text) {
    threads[thread]!.last['items'].add({'type': 'agentMessage', 'text': text});
    _events.add({
      'method': 'item/completed',
      'params': {
        'threadId': thread,
        'item': {'type': 'agentMessage', 'text': text}
      }
    });
  }

  void finish(String thread, {String status = 'completed', String? error}) {
    final turn = threads[thread]!.last;
    turn['status'] = status;
    busy.remove(thread);
    _events.add({
      'method': 'turn/completed',
      'params': {
        'threadId': thread,
        'turn': {
          'id': turn['id'],
          'status': status,
          if (error != null) 'error': {'message': error}
        }
      }
    });
  }

  Future<void> close() => _events.close();
}

Future<void> until(Future<bool> Function() test, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    if (await test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Not reached: $what');
}

