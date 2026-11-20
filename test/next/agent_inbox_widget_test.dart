import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Action;
import 'package:nipaplay/next/capabilities/classic_action.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart'
    show ChatFailureEvent;
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/shell/agent_inbox.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';

void main() {
  testWidgets(
      'empty inbox leaves no overlay and active messages preserve the control strip',
      (tester) async {
    final world = _Inbox();
    await tester.pumpWidget(world.widget(bottomInset: 120));
    await tester.pump();
    expect(find.text('问题标题'), findsOneWidget);
    expect(find.text('播放器按钮').hitTestable(), findsOneWidget);
    world.rows.clear();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.textContaining('梨花提醒'), findsNothing);
    expect(find.text('播放器按钮').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets(
      'question appears without waiting for turn end; close is not an answer',
      (tester) async {
    final world = _Inbox();
    await tester.pumpWidget(world.widget());
    await tester.pump();
    expect(find.text('问题标题'), findsOneWidget);
    expect(world.answers, isEmpty);
    await tester.tap(find.byKey(const Key('agent-inbox.collapse')));
    await tester.pump();
    expect(world.rows.single['state'], 'pending');
    expect(world.answers, isEmpty);
    await tester.tap(find.text('梨花提醒 · 1'));
    await tester.pump();
    await tester.tap(find.text('仅这次'));
    await tester.pump();
    expect(world.answers.single, {'id': 'q1', 'answer': '仅这次'});
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  for (final closeWithX in [true, false]) {
    testWidgets('notice is cleared durably, closeWithX=$closeWithX',
        (tester) async {
      final world = _Inbox();
      world.rows.single.addAll({
        'kind': 'notice',
        'state': 'unread',
        'title': '普通提醒',
        'body': '任务结果',
        'options': <String>[],
      });
      await tester.pumpWidget(world.widget());
      await tester.pump();
      if (closeWithX) {
        await tester.tap(find.byKey(const Key('agent-inbox.collapse')));
      } else {
        await tester.tap(find.text('清除提醒'));
      }
      await tester.pump();
      expect(world.rows.single['state'], 'read');
      expect(world.answers, isEmpty);
      expect(find.textContaining('梨花提醒'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      // Reopening the overlay uses persisted state, not local collapsed IDs.
      await tester.pumpWidget(world.widget());
      await tester.pump();
      expect(find.text('普通提醒'), findsNothing);
      expect(find.textContaining('梨花提醒'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await world.events.close();
    });
  }

  testWidgets(
      'new notifications do not steal focus or erase an unfinished answer',
      (tester) async {
    final world = _Inbox();
    await tester.pumpWidget(world.widget());
    await tester.pump();
    await tester.enterText(find.byType(TextField), '按我自己的规则');
    world.rows.insert(0, {
      'id': 'n2',
      'kind': 'notice',
      'state': 'unread',
      'hidden': false,
      'title': '新提醒',
      'body': '还有独立任务',
      'severity': 'info'
    });
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('按我自己的规则'), findsOneWidget);
    expect(find.text('问题标题'), findsOneWidget);
    await tester.tap(find.byType(SendButton));
    await tester.pump();
    expect(world.answers.single['id'], 'q1');
    expect(world.answers.single['answer'], '按我自己的规则');
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets(
      'remote outage retains local questions without publishing polling errors',
      (tester) async {
    final world = _Inbox();
    await tester.pumpWidget(world.widget(peer: 'offline-peer'));
    await tester.pump();
    expect(find.text('问题标题'), findsOneWidget);
    expect(find.textContaining('original remote failure'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '保留回复');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('保留回复'), findsOneWidget);
    expect(world.notices, 0);
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets(
      'small viewport contains long errors and options; full error can be copied',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final world = _Inbox();
    final error =
        'HTTP 500\n${List.filled(100, 'original error line').join('\n')}';
    world.rows[0].addAll({
      'severity': 'error',
      'body': error,
      'options': List.generate(6, (i) => '选项 $i：这是一个较长的说明')
    });
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(world.widget());
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('复制完整错误'));
    await tester.tap(find.text('复制完整错误'));
    await tester.pump();
    expect(copied, error);
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets(
      'a burst of library changes reads the inbox at most once a second (#1114)',
      (tester) async {
    final world = _Inbox();
    await tester.pumpWidget(world.widget());
    await tester.pump();
    final before = world.lists;
    expect(before, greaterThan(0));
    // A scan: a change every 20 ms for a second.
    for (var i = 0; i < 50; i++) {
      world.changes.add(null);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    // Unpaced this was 50 reads; the last change is still read.
    expect(world.lists - before, inInclusiveRange(1, 3));
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets("a failed delivery's reminder offers what its followup still allows",
      (tester) async {
    final world = _Inbox()..rows.clear();
    final followup = <String, Object?>{
      'id': 'f1',
      'state': 'ready',
      'title': '帮手找到的番',
      'retryAt': '2026-11-19T02:13:00Z',
      'failedTurns': ['t1'],
    };
    world.followups.add(followup);
    JsonMap kept(String id, String turn) => {
          'id': id,
          'kind': 'notice',
          'state': 'unread',
          'hidden': false,
          'title': '「帮手找到的番」投递失败',
          'body': '{"message": "model returned no content"}',
          'severity': 'error',
          'request': {'requestId': 'turn-$turn', 'followupId': 'f1'},
        };
    // As this device's conversation host keeps it.
    world.rows.add(kept('n1', 't1'));
    await tester.pumpWidget(world.widget());
    await tester.pump();
    await tester.pump();
    expect(find.text('立即重试'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);
    await tester.tap(find.text('停止'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(world.followupCalls, ['cancel f1']);

    // Given up for good: what is left is to retry it.
    followup
      ..['state'] = 'execution_failed'
      ..remove('retryAt');
    world.rows.add(kept('n2', 't3'));
    world.changes.add(null);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('停止'), findsNothing);
    await tester.tap(find.text('立即重试'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(world.followupCalls, ['cancel f1', 'retry f1']);
    expect(world.notified, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets(
      "a conversation's events make no reminder here; an inbox change is read again",
      (tester) async {
    final world = _Inbox();
    await tester.pumpWidget(world.widget());
    await tester.pump(const Duration(seconds: 2));
    for (final event in [
      {
        'method': 'turn/completed',
        'params': {
          'threadId': 'main',
          'turn': {'id': 't', 'status': 'failed', 'error': {'message': '429'}}
        }
      },
      for (var second = 0; second < 3; second++)
        {
          'method': 'host/liveness',
          'params': {
            'threadId': 'main', 'turnId': 't', 'status': 'failed',
            'latestError': 'session is corrupt'
          }
        },
      {'method': 'host/error', 'params': {'message': 'transport closed'}},
    ]) {
      world.events.add(event);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(world.notified, isEmpty);
    expect(find.text('收起错误'), findsNothing);
    final lists = world.lists;
    world.events.add({'method': 'host/inboxChanged', 'params': {}});
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(world.lists, greaterThan(lists));
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets("a window's own failure is kept here once, with its reason",
      (tester) async {
    final world = _Inbox()..beforeNotify = () async =>
        throw const Failure(FailureCode.conflict, 'requestId already names a different message.');
    final errors = ValueNotifier<ChatFailureEvent?>(null);
    await tester.pumpWidget(world.widget(errors: errors));
    await tester.pump();
    errors.value = ChatFailureEvent('这段对话没打开');
    await tester.pump();
    await tester.pump();
    expect(world.notified, hasLength(1));
    expect(find.textContaining('requestId already names a different message.'),
        findsOneWidget);
    expect(find.textContaining("Instance of"), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

}

class _Inbox {
  final events = StreamController<Map>.broadcast();
  final rows = <JsonMap>[
    {
      'id': 'q1',
      'kind': 'question',
      'state': 'pending',
      'hidden': false,
      'title': '问题标题',
      'body': '要不要整理目录和文件名？',
      'severity': 'info',
      'options': ['仅这次', '保持原样']
    }
  ];
  final answers = <JsonMap>[];
  int notices = 0, lists = 0;
  final notified = <JsonMap>[];
  Future<void> Function()? beforeNotify;
  final followups = <JsonMap>[];
  final followupCalls = <String>[];
  final changes = StreamController<void>.broadcast();
  late final calls = GuiCalls(() async => Harness([_Capability(this)]),
      changes: changes.stream);
  Widget widget(
          {String? peer,
          double bottomInset = 0,
          ValueListenable<ChatFailureEvent?>? errors}) =>
      MaterialApp(
          home: Scaffold(
              body: Stack(children: [
        Align(
            alignment: Alignment.bottomRight,
            child: TextButton(onPressed: () {}, child: const Text('播放器按钮'))),
        AgentInboxOverlay(
            bottomInset: bottomInset,
            calls: calls,
            events: events.stream,
            errors: errors,
            peer: () => peer),
      ])));
}

class _Capability implements Capability {
  _Capability(_Inbox world)
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'mesh.invoke',
                  title: 'remote',
                  description: 'remote',
                  effect: Effect.read,
                  input: ObjectSchema({}, additionalProperties: true),
                  output: ObjectSchema({}, additionalProperties: true)),
              (_, invocation) async => throw const Failure(
                  FailureCode.unavailable, 'original remote failure')),
          ClassicAction(
              const ActionSpec(
                  id: 'ui.notify',
                  title: 'notice',
                  description: 'notice',
                  effect: Effect.write,
                  input: ObjectSchema({}, additionalProperties: true),
                  output: ObjectSchema({}, additionalProperties: true)),
              (input, invocation) async {
            world.notices++;
            world.notified.add(Map.of(input));
            if (world.beforeNotify case final before?) await before();
            if (input['followupId'] != null) {
              // As the inbox keeps it: unread, with its request.
              world.rows.insert(0, {
                'id': 'notice-${world.notices}',
                'kind': 'notice',
                'state': 'unread',
                'hidden': false,
                'title': input['title'],
                'body': input['body'],
                'severity': 'error',
                'request': Map.of(input),
              });
            }
            return {};
          }),
          for (final op in ['list', 'retry', 'cancel'])
            ClassicAction(
                ActionSpec(
                    id: 'followup.$op',
                    title: op,
                    description: op,
                    effect: op == 'list' ? Effect.read : Effect.write,
                    input: const ObjectSchema({}, additionalProperties: true),
                    output: const ObjectSchema({}, additionalProperties: true)),
                (input, _) async {
              if (op == 'list') return {'followups': world.followups};
              world.followupCalls.add('$op ${input['id']}');
              return {
                'followup': {'id': input['id']}
              };
            }),
          for (final op in ['list', 'respond', 'dismiss'])
            ClassicAction(
                ActionSpec(
                    id: 'ui.inbox.$op',
                    title: op,
                    description: op,
                    effect: op == 'list' ? Effect.read : Effect.write,
                    input: const ObjectSchema({}, additionalProperties: true),
                    output: const ObjectSchema({}, additionalProperties: true)),
                (input, _) async {
              if (op == 'list') world.lists++;
              if (op == 'list')
                return {
                  'items': world.rows
                      .where((r) =>
                          r['state'] == 'pending' || r['state'] == 'unread')
                      .toList(),
                  'nextOffset': null,
                  'popupsEnabled': true
                };
              final row = world.rows.firstWhere((r) => r['id'] == input['id']);
              if (op == 'respond') {
                world.answers.add(Map.of(input));
                row['state'] = 'answered';
              }
              if (op == 'dismiss') {
                row['hidden'] = true;
                if (row['state'] == 'unread') row['state'] = 'read';
                if (input['cancel'] == true && row['state'] == 'pending') {
                  row['state'] = 'cancelled';
                }
              }
              return row;
            }),
        ];
  @override
  final List<ClassicAction> actions;
}
